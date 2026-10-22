import AppKit
import SwiftUI

enum Theme {
    // Palette: cool carbon. Light / dark pairs.
    static let ground = dyn(0xECEEF2, 0x131419)
    static let ink = dyn(0x1B1C22, 0xE6E7ED)
    static let carbon = dyn(0x3B3FC4, 0x8C90FF)
    static let ghost = dyn(0xB8BBD3, 0x3A3C52)
    static let cliff = dyn(0xD98A2B, 0xF0A948)

    static var inkSoft: Color { ink.opacity(0.62) }
    static var inkFaint: Color { ink.opacity(0.42) }
    static var rule: Color { ghost.opacity(0.7) }
    static var wash: Color { ghost.opacity(0.28) }

    static let nsInk = dynNS(0x1B1C22, 0xE6E7ED)
    static let nsGround = dynNS(0xECEEF2, 0x131419)
    static let nsCarbon = dynNS(0x3B3FC4, 0x8C90FF)
    static let nsCliff = dynNS(0xB86E14, 0xF0A948)

    // Type
    static func body(_ size: CGFloat) -> Font { .custom("MartianGrotesk-Regular", size: size) }
    static func bodyMedium(_ size: CGFloat) -> Font { .custom("MartianGrotesk-Medium", size: size) }
    static func mono(_ size: CGFloat) -> Font { .custom("MartianMono-Regular", size: size) }
    static func monoMedium(_ size: CGFloat) -> Font { .custom("MartianMono-Medium", size: size) }
    static func display(_ size: CGFloat, level: Int = 0) -> Font {
        .custom(level == 0 ? "Redaction-Regular" : "Redaction\(level)-Regular", size: size)
    }
    static func nsBody(_ size: CGFloat) -> NSFont {
        NSFont(name: "MartianGrotesk-Regular", size: size) ?? .systemFont(ofSize: size)
    }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: dynNS(light, dark))
    }
    private static func dynNS(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { ap in
            ap.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? hex(dark) : hex(light)
        }
    }
    private static func hex(_ v: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

enum Stamp {
    private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()
    private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; return f }()

    static func short(_ d: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(d) { return time.string(from: d) }
        if cal.isDateInYesterday(d) { return "Yest " + time.string(from: d) }
        return day.string(from: d)
    }
    static func count(_ n: Int) -> String {
        n.formatted(.number) + (n == 1 ? " char" : " chars")
    }
}
