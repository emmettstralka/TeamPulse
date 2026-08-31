"""Database models and initialization."""

import sqlite3
import json
import uuid
import secrets
from datetime import datetime, timedelta
from typing import Optional, List
from contextlib import contextmanager

from config import DB_PATH


def init_db():
    """Initialize the SQLite database with required tables."""
    with get_connection() as conn:
        c = conn.cursor()

        # Sessions table
        c.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                athlete_id TEXT NOT NULL,
                workout_type TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                duration_seconds INTEGER,
                total_calories REAL DEFAULT 0,
                total_distance REAL DEFAULT 0,
                avg_hr INTEGER,
                max_hr INTEGER,
                min_hr INTEGER,
                status TEXT DEFAULT 'active',
                healthkit_uuid TEXT,
                source TEXT DEFAULT 'live'
            )
        """)

        # Heart rate data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS heart_rate_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                hr INTEGER NOT NULL,
                zone TEXT NOT NULL,
                device_status TEXT DEFAULT 'watch',
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Calories data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS calorie_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                calories REAL NOT NULL,
                cumulative_calories REAL DEFAULT 0,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Distance data points
        c.execute("""
            CREATE TABLE IF NOT EXISTS distance_data (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                distance REAL NOT NULL,
                FOREIGN KEY (session_id) REFERENCES sessions(id)
            )
        """)

        # Offline message queue (for eventual consistency)
        c.execute("""
            CREATE TABLE IF NOT EXISTS message_queue (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id TEXT NOT NULL,
                athlete_id TEXT NOT NULL,
                payload TEXT NOT NULL,
                received_at TEXT NOT NULL,
                synced INTEGER DEFAULT 0
            )
        """)

        # Recovery metrics (post-workout sync from HealthKit)
        c.execute("""
            CREATE TABLE IF NOT EXISTS recovery_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                athlete_id TEXT NOT NULL,
                session_id TEXT,
                date TEXT NOT NULL,
                sleep_hours REAL,
                sleep_deep_hours REAL,
                sleep_rem_hours REAL,
                sleep_awake_minutes INTEGER,
                spo2_avg REAL,
                spo2_min REAL,
                resting_hr INTEGER,
                hrv_avg INTEGER,
                vo2_max REAL,
                recovery_score REAL,
                fatigue_score REAL,
                readiness_score REAL,
                synced_at TEXT NOT NULL,
                UNIQUE(athlete_id, date)
            )
        """)

        # Athletes (lightweight - just for tracking)
        c.execute("""
            CREATE TABLE IF NOT EXISTS athletes (
                id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                last_seen TEXT,
                display_name TEXT
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS teams (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                join_code TEXT UNIQUE NOT NULL,
                sport TEXT DEFAULT 'soccer',
                created_at TEXT NOT NULL
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS team_members (
                team_id TEXT NOT NULL,
                athlete_id TEXT NOT NULL,
                display_name TEXT NOT NULL,
                role TEXT DEFAULT 'athlete',
                joined_at TEXT NOT NULL,
                PRIMARY KEY (team_id, athlete_id),
                FOREIGN KEY (team_id) REFERENCES teams(id),
                FOREIGN KEY (athlete_id) REFERENCES athletes(id)
            )
        """)

        c.execute("""
            CREATE TABLE IF NOT EXISTS activity_rings (
                athlete_id TEXT NOT NULL,
                date TEXT NOT NULL,
                move_kcal REAL DEFAULT 0,
                move_goal REAL DEFAULT 500,
                exercise_min REAL DEFAULT 0,
                exercise_goal REAL DEFAULT 30,
                stand_hours REAL DEFAULT 0,
                stand_goal REAL DEFAULT 12,
                synced_at TEXT NOT NULL,
                UNIQUE(athlete_id, date)
            )
        """)

        _ensure_column(c, "sessions", "healthkit_uuid", "TEXT")
        _ensure_column(c, "sessions", "source", "TEXT DEFAULT 'live'")
        _ensure_column(c, "athletes", "display_name", "TEXT")

        c.execute("CREATE INDEX IF NOT EXISTS idx_sessions_hk ON sessions(healthkit_uuid)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_members_team ON team_members(team_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_rings_athlete ON activity_rings(athlete_id)")

        # Indexes for performance
        c.execute("CREATE INDEX IF NOT EXISTS idx_hr_session ON heart_rate_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_hr_timestamp ON heart_rate_data(timestamp)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_calories_session ON calorie_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_distance_session ON distance_data(session_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_recovery_athlete ON recovery_metrics(athlete_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_sessions_athlete ON sessions(athlete_id)")
        c.execute("CREATE INDEX IF NOT EXISTS idx_queue_synced ON message_queue(synced)")

        conn.commit()
        seed_demo_team_if_needed()


def _ensure_column(cursor, table: str, column: str, ddl: str):
    existing = [row[1] for row in cursor.execute(f"PRAGMA table_info({table})").fetchall()]
    if column not in existing:
        cursor.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")


@contextmanager
def get_connection():
    """Get a database connection with row factory."""
    conn = sqlite3.connect(DB_PATH, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
    finally:
        conn.close()


# ─── Session Operations ────────────────────────────────────────────────────────


def create_session(session_id: str, athlete_id: str, workout_type: str) -> dict:
    """Create a new workout session."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()
        c.execute(
            """INSERT INTO sessions (id, athlete_id, workout_type, started_at, status)
               VALUES (?, ?, ?, ?, 'active')""",
            (session_id, athlete_id, workout_type, now),
        )
        conn.commit()
        return get_session(session_id)


def get_session(session_id: str) -> Optional[dict]:
    """Get a session by ID."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM sessions WHERE id = ?", (session_id,))
        row = c.fetchone()
        return dict(row) if row else None


def end_session(session_id: str, duration_seconds: int, total_calories: float, total_distance: float) -> Optional[dict]:
    """End a workout session."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()

        # Calculate HR stats
        c.execute(
            "SELECT MIN(hr), MAX(hr), AVG(hr) FROM heart_rate_data WHERE session_id = ?",
            (session_id,),
        )
        hr_row = c.fetchone()
        min_hr = hr_row["MIN(hr)"]
        max_hr = hr_row["MAX(hr)"]
        avg_raw = hr_row["AVG(hr)"]
        avg_hr = int(avg_raw) if avg_raw is not None else None

        c.execute(
            """UPDATE sessions SET
               ended_at = ?, duration_seconds = ?, total_calories = ?,
               total_distance = ?, avg_hr = ?, max_hr = ?, min_hr = ?,
               status = 'completed'
               WHERE id = ?""",
            (now, duration_seconds, total_calories, total_distance, avg_hr, max_hr, min_hr, session_id),
        )
        conn.commit()
        return get_session(session_id)


# ─── Data Point Operations ────────────────────────────────────────────────────


def store_heart_rate(session_id: str, timestamp: str, hr: int, zone: str, device_status: str):
    """Store a heart rate data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO heart_rate_data (session_id, timestamp, hr, zone, device_status) VALUES (?, ?, ?, ?, ?)",
            (session_id, timestamp, hr, zone, device_status),
        )
        conn.commit()


def store_calories(session_id: str, timestamp: str, calories: float, cumulative: float):
    """Store a calorie data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO calorie_data (session_id, timestamp, calories, cumulative_calories) VALUES (?, ?, ?, ?)",
            (session_id, timestamp, calories, cumulative),
        )
        conn.commit()


def store_distance(session_id: str, timestamp: str, distance: float):
    """Store a distance data point."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO distance_data (session_id, timestamp, distance) VALUES (?, ?, ?)",
            (session_id, timestamp, distance),
        )
        conn.commit()


# ─── Queue Operations ────────────────────────────────────────────────────────


def queue_message(session_id: str, athlete_id: str, payload: dict):
    """Queue a message for processing."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "INSERT INTO message_queue (session_id, athlete_id, payload, received_at) VALUES (?, ?, ?, ?)",
            (session_id, athlete_id, json.dumps(payload), datetime.utcnow().isoformat()),
        )
        conn.commit()


def get_pending_messages(limit: int = 100) -> List[dict]:
    """Get pending messages for processing."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            "SELECT * FROM message_queue WHERE synced = 0 ORDER BY id LIMIT ?",
            (limit,),
        )
        return [dict(row) for row in c.fetchall()]


def mark_messages_synced(message_ids: List[int]):
    """Mark messages as synced."""
    if not message_ids:
        return
    placeholders = ",".join("?" * len(message_ids))
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(f"UPDATE message_queue SET synced = 1 WHERE id IN ({placeholders})", message_ids)
        conn.commit()


# ─── Recovery Metrics Operations ─────────────────────────────────────────────


def upsert_recovery_metrics(athlete_id: str, date: str, metrics: dict) -> dict:
    """Insert or update recovery metrics for an athlete."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """INSERT INTO recovery_metrics (
                athlete_id, session_id, date, sleep_hours, sleep_deep_hours, sleep_rem_hours,
                sleep_awake_minutes, spo2_avg, spo2_min, resting_hr, hrv_avg, vo2_max,
                recovery_score, fatigue_score, readiness_score, synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(athlete_id, date) DO UPDATE SET
                sleep_hours = excluded.sleep_hours,
                sleep_deep_hours = excluded.sleep_deep_hours,
                sleep_rem_hours = excluded.sleep_rem_hours,
                sleep_awake_minutes = excluded.sleep_awake_minutes,
                spo2_avg = excluded.spo2_avg,
                spo2_min = excluded.spo2_min,
                resting_hr = excluded.resting_hr,
                hrv_avg = excluded.hrv_avg,
                vo2_max = excluded.vo2_max,
                recovery_score = excluded.recovery_score,
                fatigue_score = excluded.fatigue_score,
                readiness_score = excluded.readiness_score,
                synced_at = excluded.synced_at
            """,
            (
                athlete_id,
                metrics.get("session_id"),
                date,
                metrics.get("sleep_hours"),
                metrics.get("sleep_deep_hours"),
                metrics.get("sleep_rem_hours"),
                metrics.get("sleep_awake_minutes"),
                metrics.get("spo2_avg"),
                metrics.get("spo2_min"),
                metrics.get("resting_hr"),
                metrics.get("hrv_avg"),
                metrics.get("vo2_max"),
                metrics.get("recovery_score"),
                metrics.get("fatigue_score"),
                metrics.get("readiness_score"),
                datetime.utcnow().isoformat(),
            ),
        )
        conn.commit()

        c.execute(
            "SELECT * FROM recovery_metrics WHERE athlete_id = ? AND date = ?",
            (athlete_id, date),
        )
        return dict(c.fetchone())


def get_recovery_metrics(athlete_id: str, days: int = 7) -> List[dict]:
    """Get recovery metrics for the last N days."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """SELECT * FROM recovery_metrics
               WHERE athlete_id = ?
               ORDER BY date DESC
               LIMIT ?""",
            (athlete_id, days),
        )
        return [dict(row) for row in c.fetchall()]


# ─── Athlete Operations ───────────────────────────────────────────────────────


def upsert_athlete(athlete_id: str, display_name: Optional[str] = None):
    """Create or update athlete last-seen timestamp."""
    with get_connection() as conn:
        c = conn.cursor()
        now = datetime.utcnow().isoformat()
        c.execute(
            """INSERT INTO athletes (id, created_at, last_seen, display_name)
               VALUES (?, ?, ?, ?)
               ON CONFLICT(id) DO UPDATE SET
                 last_seen = excluded.last_seen,
                 display_name = COALESCE(excluded.display_name, athletes.display_name)""",
            (athlete_id, now, now, display_name),
        )
        conn.commit()


def get_athlete(athlete_id: str) -> Optional[dict]:
    """Get athlete by ID."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM athletes WHERE id = ?", (athlete_id,))
        row = c.fetchone()
        return dict(row) if row else None


# ─── Session History ──────────────────────────────────────────────────────────


def get_sessions(athlete_id: str, limit: int = 20) -> List[dict]:
    """Get recent sessions for an athlete."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """SELECT * FROM sessions
               WHERE athlete_id = ? AND status = 'completed'
               ORDER BY started_at DESC LIMIT ?""",
            (athlete_id, limit),
        )
        return [dict(row) for row in c.fetchall()]


def get_session_data(session_id: str) -> dict:
    """Get all data for a session."""
    with get_connection() as conn:
        c = conn.cursor()

        session = get_session(session_id)
        if not session:
            return {}

        c.execute(
            "SELECT timestamp, hr, zone FROM heart_rate_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        hr_data = [dict(row) for row in c.fetchall()]

        c.execute(
            "SELECT timestamp, calories, cumulative_calories FROM calorie_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        calorie_data = [dict(row) for row in c.fetchall()]

        c.execute(
            "SELECT timestamp, distance FROM distance_data WHERE session_id = ? ORDER BY timestamp",
            (session_id,),
        )
        distance_data = [dict(row) for row in c.fetchall()]

        # Calculate time in zones
        c.execute(
            "SELECT zone, COUNT(*) as count FROM heart_rate_data WHERE session_id = ? GROUP BY zone",
            (session_id,),
        )
        zone_counts = {row["zone"]: row["count"] for row in c.fetchall()}

        total_points = sum(zone_counts.values()) if zone_counts else 1
        time_in_zones = {
            zone: {"seconds": count, "percentage": round(count / total_points * 100, 1)}
            for zone, count in zone_counts.items()
        }

        return {
            **session,
            "hr_data": hr_data,
            "calorie_data": calorie_data,
            "distance_data": distance_data,
            "time_in_zones": time_in_zones,
        }


# ─── Teams ────────────────────────────────────────────────────────────────────


def generate_join_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "".join(secrets.choice(alphabet) for _ in range(6))


def create_team(name: str, sport: str = "soccer") -> dict:
    team_id = str(uuid.uuid4())
    join_code = generate_join_code()
    with get_connection() as conn:
        c = conn.cursor()
        for _ in range(8):
            try:
                c.execute(
                    "INSERT INTO teams (id, name, join_code, sport, created_at) VALUES (?, ?, ?, ?, ?)",
                    (team_id, name.strip(), join_code, sport, datetime.utcnow().isoformat()),
                )
                conn.commit()
                break
            except sqlite3.IntegrityError:
                join_code = generate_join_code()
        else:
            raise RuntimeError("Could not allocate a unique join code")
    return get_team(team_id)


def get_team(team_id: str) -> Optional[dict]:
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM teams WHERE id = ?", (team_id,))
        row = c.fetchone()
        return dict(row) if row else None


def get_team_by_code(join_code: str) -> Optional[dict]:
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT * FROM teams WHERE join_code = ?", (join_code.strip().upper(),))
        row = c.fetchone()
        return dict(row) if row else None


def join_team(join_code: str, athlete_id: str, display_name: str, role: str = "athlete") -> dict:
    team = get_team_by_code(join_code)
    if not team:
        raise ValueError("Invalid join code")
    upsert_athlete(athlete_id, display_name)
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """INSERT INTO team_members (team_id, athlete_id, display_name, role, joined_at)
               VALUES (?, ?, ?, ?, ?)
               ON CONFLICT(team_id, athlete_id) DO UPDATE SET
                 display_name = excluded.display_name""",
            (team["id"], athlete_id, display_name.strip(), role, datetime.utcnow().isoformat()),
        )
        conn.commit()
    return {**team, "athlete_id": athlete_id, "display_name": display_name, "role": role}


def list_team_members(team_id: str) -> List[dict]:
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """SELECT m.*, a.last_seen
               FROM team_members m
               LEFT JOIN athletes a ON a.id = m.athlete_id
               WHERE m.team_id = ?
               ORDER BY m.display_name COLLATE NOCASE""",
            (team_id,),
        )
        return [dict(row) for row in c.fetchall()]


def upsert_healthkit_workout(
    athlete_id: str,
    healthkit_uuid: str,
    workout_type: str,
    started_at: str,
    ended_at: Optional[str],
    duration_seconds: int,
    total_calories: float,
    total_distance: float,
    avg_hr: Optional[int],
    max_hr: Optional[int],
    min_hr: Optional[int],
) -> dict:
    upsert_athlete(athlete_id)
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT id FROM sessions WHERE healthkit_uuid = ?", (healthkit_uuid,))
        existing = c.fetchone()
        session_id = existing["id"] if existing else healthkit_uuid
        status = "completed" if ended_at else "active"
        if existing:
            c.execute(
                """UPDATE sessions SET
                     athlete_id = ?, workout_type = ?, started_at = ?, ended_at = ?,
                     duration_seconds = ?, total_calories = ?, total_distance = ?,
                     avg_hr = ?, max_hr = ?, min_hr = ?, status = ?, source = 'healthkit'
                   WHERE id = ?""",
                (
                    athlete_id, workout_type, started_at, ended_at,
                    duration_seconds, total_calories, total_distance,
                    avg_hr, max_hr, min_hr, status, session_id,
                ),
            )
        else:
            c.execute(
                """INSERT INTO sessions (
                     id, athlete_id, workout_type, started_at, ended_at, duration_seconds,
                     total_calories, total_distance, avg_hr, max_hr, min_hr, status,
                     healthkit_uuid, source
                   ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'healthkit')""",
                (
                    session_id, athlete_id, workout_type, started_at, ended_at,
                    duration_seconds, total_calories, total_distance,
                    avg_hr, max_hr, min_hr, status, healthkit_uuid,
                ),
            )
        conn.commit()
    return get_session(session_id)


def upsert_activity_rings(
    athlete_id: str,
    date: str,
    move_kcal: float,
    move_goal: float,
    exercise_min: float,
    exercise_goal: float,
    stand_hours: float,
    stand_goal: float,
) -> dict:
    upsert_athlete(athlete_id)
    with get_connection() as conn:
        c = conn.cursor()
        c.execute(
            """INSERT INTO activity_rings (
                athlete_id, date, move_kcal, move_goal, exercise_min, exercise_goal,
                stand_hours, stand_goal, synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(athlete_id, date) DO UPDATE SET
                move_kcal = excluded.move_kcal,
                move_goal = excluded.move_goal,
                exercise_min = excluded.exercise_min,
                exercise_goal = excluded.exercise_goal,
                stand_hours = excluded.stand_hours,
                stand_goal = excluded.stand_goal,
                synced_at = excluded.synced_at""",
            (
                athlete_id, date, move_kcal, move_goal, exercise_min, exercise_goal,
                stand_hours, stand_goal, datetime.utcnow().isoformat(),
            ),
        )
        conn.commit()
        c.execute(
            "SELECT * FROM activity_rings WHERE athlete_id = ? AND date = ?",
            (athlete_id, date),
        )
        return dict(c.fetchone())


def _flag_for_athlete(today_session: Optional[dict], recovery: Optional[dict]) -> str:
    sleep = (recovery or {}).get("sleep_hours") or 0
    readiness = (recovery or {}).get("readiness_score")
    duration = (today_session or {}).get("duration_seconds") or 0
    if sleep and sleep < 6:
        return "rest"
    if readiness is not None and readiness < 45:
        return "rest"
    if duration >= 90 * 60 or (sleep and sleep < 7):
        return "watch"
    return "ok"


def _average_rings(rows: List[dict]) -> dict:
    """Team-average Activity rings, same units as Apple Watch (CAL / MIN / HRS)."""
    empty = {
        "move_kcal": 0,
        "move_goal": 500,
        "exercise_min": 0,
        "exercise_goal": 30,
        "stand_hours": 0,
        "stand_goal": 12,
        "closed_move": 0,
        "closed_exercise": 0,
        "closed_stand": 0,
        "count": 0,
    }
    if not rows:
        return empty
    n = len(rows)

    def avg(key, default=0):
        return round(sum((r.get(key) or default) for r in rows) / n, 1)

    move_kcal = avg("move_kcal")
    move_goal = avg("move_goal", 500) or 500
    exercise_min = avg("exercise_min")
    exercise_goal = avg("exercise_goal", 30) or 30
    stand_hours = avg("stand_hours")
    stand_goal = avg("stand_goal", 12) or 12
    return {
        "move_kcal": move_kcal,
        "move_goal": move_goal,
        "exercise_min": exercise_min,
        "exercise_goal": exercise_goal,
        "stand_hours": stand_hours,
        "stand_goal": stand_goal,
        "closed_move": sum(1 for r in rows if (r.get("move_goal") or 0) > 0 and (r.get("move_kcal") or 0) >= r["move_goal"]),
        "closed_exercise": sum(1 for r in rows if (r.get("exercise_goal") or 0) > 0 and (r.get("exercise_min") or 0) >= r["exercise_goal"]),
        "closed_stand": sum(1 for r in rows if (r.get("stand_goal") or 0) > 0 and (r.get("stand_hours") or 0) >= r["stand_goal"]),
        "count": n,
    }


def get_team_board(team_id: str) -> Optional[dict]:
    team = get_team(team_id)
    if not team:
        return None

    today = datetime.utcnow().strftime("%Y-%m-%d")
    members = list_team_members(team_id)
    roster = []
    practiced = 0
    flagged = 0
    sleep_values = []
    ring_rows = []

    with get_connection() as conn:
        c = conn.cursor()
        for member in members:
            athlete_id = member["athlete_id"]
            c.execute(
                """SELECT * FROM sessions
                   WHERE athlete_id = ? AND substr(started_at, 1, 10) = ?
                   ORDER BY started_at DESC LIMIT 1""",
                (athlete_id, today),
            )
            session_row = c.fetchone()
            today_session = dict(session_row) if session_row else None

            c.execute(
                """SELECT COUNT(*) AS n, COALESCE(SUM(duration_seconds), 0) AS load_sec
                   FROM sessions
                   WHERE athlete_id = ? AND started_at >= datetime('now', '-7 days')
                     AND status = 'completed'""",
                (athlete_id,),
            )
            week = dict(c.fetchone())

            c.execute(
                "SELECT * FROM recovery_metrics WHERE athlete_id = ? ORDER BY date DESC LIMIT 1",
                (athlete_id,),
            )
            rec_row = c.fetchone()
            recovery = dict(rec_row) if rec_row else None

            c.execute(
                "SELECT * FROM activity_rings WHERE athlete_id = ? AND date = ?",
                (athlete_id, today),
            )
            ring_row = c.fetchone()
            rings = dict(ring_row) if ring_row else None

            flag = _flag_for_athlete(today_session, recovery)
            if today_session:
                practiced += 1
            if flag != "ok":
                flagged += 1
            if recovery and recovery.get("sleep_hours"):
                sleep_values.append(recovery["sleep_hours"])
            if rings:
                ring_rows.append(rings)

            roster.append({
                "athlete_id": athlete_id,
                "display_name": member["display_name"],
                "role": member["role"],
                "last_seen": member.get("last_seen"),
                "today": {
                    "practiced": today_session is not None,
                    "workout_type": (today_session or {}).get("workout_type"),
                    "duration_seconds": (today_session or {}).get("duration_seconds") or 0,
                    "distance": (today_session or {}).get("total_distance") or 0,
                    "calories": (today_session or {}).get("total_calories") or 0,
                    "avg_hr": (today_session or {}).get("avg_hr"),
                    "started_at": (today_session or {}).get("started_at"),
                },
                "week": {
                    "sessions": week["n"],
                    "load_seconds": week["load_sec"],
                },
                "recovery": recovery,
                "rings": rings,
                "flag": flag,
            })

    return {
        "team": team,
        "date": today,
        "summary": {
            "athletes": len(roster),
            "practiced_today": practiced,
            "flagged": flagged,
            "avg_sleep": round(sum(sleep_values) / len(sleep_values), 1) if sleep_values else None,
            "rings": _average_rings(ring_rows),
        },
        "roster": roster,
    }


def seed_demo_team_if_needed():
    """Seed a demo club so the coach dashboard has something to show."""
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("SELECT COUNT(*) AS n FROM teams")
        if c.fetchone()["n"] > 0:
            today = datetime.utcnow().strftime("%Y-%m-%d")
            c.execute(
                """UPDATE sessions SET started_at = ?, ended_at = ?
                   WHERE id LIKE 'demo-wk-%' OR healthkit_uuid LIKE 'demo-wk-%'""",
                (f"{today}T16:00:00", f"{today}T17:12:00"),
            )
            c.execute(
                "UPDATE activity_rings SET date = ? WHERE athlete_id LIKE 'demo-%'",
                (today,),
            )
            c.execute(
                "UPDATE recovery_metrics SET date = ? WHERE athlete_id LIKE 'demo-%'",
                (today,),
            )
            conn.commit()
            return

    team = create_team("Northside FC", "soccer")
    # Stable demo join code
    with get_connection() as conn:
        c = conn.cursor()
        c.execute("UPDATE teams SET join_code = ? WHERE id = ?", ("NORTH1", team["id"]))
        conn.commit()
    team = get_team(team["id"])

    names = [
        "Maya Chen", "Jordan Blake", "Sam Rivera", "Avery Cole",
        "Riley Patel", "Chris Nguyen", "Taylor Brooks", "Quinn Walsh",
        "Jamie Ortiz", "Morgan Lee", "Casey Dunn", "Alex Romero",
    ]
    today = datetime.utcnow().strftime("%Y-%m-%d")

    for i, name in enumerate(names):
        athlete_id = f"demo-{i+1:02d}"
        join_team("NORTH1", athlete_id, name)
        practiced = i < 9
        if practiced:
            duration = 48 * 60 + i * 90
            hr = 142 + (i % 7) * 3
            started_at = f"{today}T16:00:00"
            ended_at = f"{today}T17:12:00"
            upsert_healthkit_workout(
                athlete_id=athlete_id,
                healthkit_uuid=f"demo-wk-{athlete_id}-{today}",
                workout_type="soccer",
                started_at=started_at,
                ended_at=ended_at,
                duration_seconds=duration,
                total_calories=420 + i * 12,
                total_distance=6200 + i * 180,
                avg_hr=hr,
                max_hr=hr + 28,
                min_hr=hr - 22,
            )

        sleep = 7.4 - (0.35 if i in (2, 7, 10) else 0) - (1.8 if i == 10 else 0)
        upsert_recovery_metrics(
            athlete_id,
            today,
            {
                "sleep_hours": sleep,
                "sleep_deep_hours": 1.4,
                "sleep_rem_hours": 1.6,
                "resting_hr": 54 + i,
                "hrv_avg": 62 - i,
                "recovery_score": 78 - i * 2,
                "fatigue_score": 22 + i,
                "readiness_score": 74 - (30 if i == 10 else i * 2),
            },
        )
        upsert_activity_rings(
            athlete_id,
            today,
            move_kcal=380 + i * 18,
            move_goal=500,
            exercise_min=22 + i,
            exercise_goal=30,
            stand_hours=8 + (i % 4),
            stand_goal=12,
        )

