# TeamPulse

Team tracking for clubs that already have Apple Watches. Athletes keep **Apple Workout**. TeamPulse is the HealthKit bridge and coach board.

Move, Exercise, and Stand use the same units and colors as Fitness: **CAL**, **MIN**, **HRS**.

## What it does

- **Players** allow Health on iPhone. Completed workouts, rings, sleep, and HRV sync to the club after the phone is unlocked.
- **Coaches** open a club by join code and see today’s roster: who practiced, who closed rings, who needs rest.
- **Apple Watch** is optional. The Watch app shows today’s rings. Live HR is not the product — Apple Workout already does that, and only one `HKWorkoutSession` can run at a time.

There is no HealthKit cloud API. Something on the athlete’s phone has to read Health and POST. That is the iPhone app.

## What’s in the repo

```
TeamPulse/
├── backend/          FastAPI + SQLite (teams, rings, workouts, board)
├── dashboard/        Coach web board (served at GET /)
└── ios/              Xcode project
    ├── WorkoutSync   iPhone app (player + coach)
    └── WatchWorkout  Optional Watch companion
```

Demo club: **Northside FC**, join code **NORTH1**.

## Run the backend

Needs Python 3.10+ (3.14 is fine).

```bash
cd backend
./run.sh
```

That creates `.venv`, installs `requirements.txt`, and binds `0.0.0.0:8000`.

Coach board: [http://127.0.0.1:8000/](http://127.0.0.1:8000/)

```bash
curl http://127.0.0.1:8000/api/health
```

`backend/workout.db` is local SQLite. Do not commit it.

## Run the iOS apps

```bash
open ios/WorkoutSystem.xcodeproj
```

Schemes:

| Scheme | Device |
|---|---|
| **WorkoutSync** | iPhone |
| **WatchWorkout** | Apple Watch |

Set your Development Team on both targets. Bundle IDs are `com.workoutsystem.iphone` and `com.workoutsystem.iphone.watch`.

Simulators are fine for UI. HealthKit, rings, and workout sessions need a **physical iPhone** (and Watch if you use the companion).

On a real device, `localhost` is the phone itself. Set `BACKEND_HOST` to your Mac’s LAN IP (and keep the backend on `0.0.0.0:8000`).

```swift
// ios/WorkoutSync/Sources/Networking/BackendSyncService.swift
backendHost = ProcessInfo.processInfo.environment["BACKEND_HOST"] ?? "localhost"
```

## How people use it

1. Start the backend.
2. On iPhone, finish onboarding and pick **Player** or **Coach**.
3. **Player:** allow Health, join with a code (or create a club). Pull to sync.
4. **Coach:** create a club or open **NORTH1**. Same board exists on the web at `/`.

Health data is encrypted while the phone is locked. Sync happens after unlock, not as a live cloud stream.

## API (club board)

| Method | Path | Purpose |
|---|---|---|
| `GET` | `/` | Coach dashboard |
| `GET` | `/api/health` | Liveness |
| `POST` | `/api/teams` | Create club (returns join code) |
| `POST` | `/api/teams/join` | Athlete joins |
| `GET` | `/api/teams/code/{code}/board` | Roster + rings for today |
| `POST` | `/api/workouts/sync` | Apple Workout from HealthKit |
| `POST` | `/api/rings/sync` | Today’s Activity rings |
| `POST` | `/api/recovery/sync` | Sleep / HRV / readiness |

Live session WebSockets still exist for the optional Watch HR path. They are not required for the coach board.

## Constraints worth knowing

- HealthKit does not leave the device unless the athlete grants access and joins a club.
- High-frequency live HR needs `HKWorkoutSession` and conflicts with Apple Workout.
- One Watch workout session at a time.
- This is not a Terra-style developer API. It ingests Apple Health for one club’s coaches.
