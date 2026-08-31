import SwiftUI

enum Pulse {
    static let bg = Color.black
    static let card = Color(hex: "1C1C1E")
    static let card2 = Color(hex: "2C2C2E")
    static let hair = Color(hex: "3A3A3C")
    static let text = Color(hex: "F5F5F7")
    static let muted = Color(hex: "8E8E93")
    static let move = Color(hex: "FA114F")
    static let exercise = Color(hex: "92ED2C")
    static let stand = Color(hex: "00D3EA")
    static let ok = Color(hex: "30D158")
    static let watch = Color(hex: "FFD60A")
    static let rest = Color(hex: "FF453A")
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

