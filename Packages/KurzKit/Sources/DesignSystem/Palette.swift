import SwiftUI

public extension Color {
    static let appBackground = adaptive(light: 0xF7F8FA, dark: 0x101418)
    static let appForeground = adaptive(light: 0x111827, dark: 0xEEF2F5)
    static let appCard = adaptive(light: 0xFFFFFF, dark: 0x151B20)
    static let appMuted = adaptive(light: 0xEEF2F5, dark: 0x1D252C)
    static let appMutedForeground = adaptive(light: 0x5D6675, dark: 0xA7B0BC)
    static let appBorder = adaptive(light: 0xD9E0E7, dark: 0x29333C)
    static let appPrimary = adaptive(light: 0x116D6E, dark: 0x4FB5B3)
    static let appPrimaryForeground = adaptive(light: 0xFFFFFF, dark: 0x061819)
    static let appAccent = adaptive(light: 0xE7F3F3, dark: 0x183436)
    static let appAccentForeground = adaptive(light: 0x0E4F51, dark: 0xB7EEEE)
    static let appDestructive = adaptive(light: 0xB4232F, dark: 0xFF6B73)
    static let appRing = adaptive(light: 0x158083, dark: 0x6AC7C5)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
        #else
        Color(hex: light)
        #endif
    }

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.appPrimaryForeground)
            .background(Color.appPrimary.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 12))
    }
}
