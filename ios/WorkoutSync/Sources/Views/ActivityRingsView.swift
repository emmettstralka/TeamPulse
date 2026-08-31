import SwiftUI

/// Apple Watch–style Move / Exercise / Stand rings. Drawn with SwiftUI paths, no SF Symbols.
struct ActivityRingsView: View {
    var move: Double
    var exercise: Double
    var stand: Double
    var lineWidth: CGFloat = 14
    var gap: CGFloat = 6

    private let moveColor = Color(hex: "FA114F")
    private let exerciseColor = Color(hex: "96F22B")
    private let standColor = Color(hex: "32ADE6")

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let cx = geo.size.width / 2
            let cy = geo.size.height / 2
            let outer = size / 2 - lineWidth / 2
            let middle = outer - lineWidth - gap
            let inner = middle - lineWidth - gap

            ZStack {
                ringTrack(radius: outer, color: moveColor)
                ringFill(radius: outer, progress: move, color: moveColor)
                ringTrack(radius: middle, color: exerciseColor)
                ringFill(radius: middle, progress: exercise, color: exerciseColor)
                ringTrack(radius: inner, color: standColor)
                ringFill(radius: inner, progress: stand, color: standColor)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .position(x: cx, y: cy)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func ringTrack(radius: CGFloat, color: Color) -> some View {
        Circle()
            .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: radius * 2, height: radius * 2)
    }

    private func ringFill(radius: CGFloat, progress: Double, color: Color) -> some View {
        Circle()
            .trim(from: 0, to: CGFloat(min(max(progress, 0.001), 1)))
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .frame(width: radius * 2, height: radius * 2)
            .shadow(color: color.opacity(0.45), radius: 4, x: 0, y: 0)
    }
}

struct HealthMetricIcon: View {
    enum Kind { case heart, sleep, workout, figure }

    var kind: Kind
    var color: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            Path { path in
                switch kind {
                case .heart:
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.82))
                    path.addCurve(
                        to: CGPoint(x: w * 0.12, y: h * 0.38),
                        control1: CGPoint(x: w * 0.18, y: h * 0.62),
                        control2: CGPoint(x: w * 0.05, y: h * 0.50)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.28),
                        control1: CGPoint(x: w * 0.18, y: h * 0.12),
                        control2: CGPoint(x: w * 0.42, y: h * 0.14)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.88, y: h * 0.38),
                        control1: CGPoint(x: w * 0.58, y: h * 0.14),
                        control2: CGPoint(x: w * 0.82, y: h * 0.12)
                    )
                    path.addCurve(
                        to: CGPoint(x: w * 0.5, y: h * 0.82),
                        control1: CGPoint(x: w * 0.95, y: h * 0.50),
                        control2: CGPoint(x: w * 0.82, y: h * 0.62)
                    )
                case .sleep:
                    path.addEllipse(in: CGRect(x: w * 0.18, y: h * 0.16, width: w * 0.64, height: h * 0.64))
                    path.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.10, width: w * 0.52, height: h * 0.52))
                case .workout:
                    path.addEllipse(in: CGRect(x: w * 0.08, y: h * 0.58, width: w * 0.28, height: h * 0.28))
                    path.addEllipse(in: CGRect(x: w * 0.64, y: h * 0.58, width: w * 0.28, height: h * 0.28))
                    path.move(to: CGPoint(x: w * 0.22, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.72))
                    path.move(to: CGPoint(x: w * 0.48, y: h * 0.38))
                    path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.18))
                case .figure:
                    path.addEllipse(in: CGRect(x: w * 0.38, y: h * 0.06, width: w * 0.24, height: h * 0.24))
                    path.move(to: CGPoint(x: w * 0.18, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.42))
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.30))
                    path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.92))
                    path.move(to: CGPoint(x: w * 0.5, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.92))
                }
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
