import SwiftUI

public extension Color {
    static let appBackground = Color("appBackground", bundle: .module)
    static let appForeground = Color("appForeground", bundle: .module)
    static let appCard = Color("appCard", bundle: .module)
    static let appMuted = Color("appMuted", bundle: .module)
    static let appMutedForeground = Color("appMutedForeground", bundle: .module)
    static let appBorder = Color("appBorder", bundle: .module)
    static let appPrimary = Color("appPrimary", bundle: .module)
    static let appPrimaryForeground = Color("appPrimaryForeground", bundle: .module)
    static let appAccent = Color("appAccent", bundle: .module)
    static let appAccentForeground = Color("appAccentForeground", bundle: .module)
    static let appDestructive = Color("appDestructive", bundle: .module)
    static let appRing = Color("appRing", bundle: .module)
    static let appPlaceholder = Color("appPlaceholder", bundle: .module)
    static let appCategoryPalette: [Color] = [0xA78BFA, 0xF0A35E, 0x5EC8C4, 0x6AA8F0, 0x8BD17C].map { Color(hex: $0) }

    static func appCategory(id: String?, name: String? = nil) -> Color {
        guard let id else { return .appPrimary }
        let named = ["spa": 0, "unhas": 1, "danca": 2, "musica": 3, "outros": 4]
        let key = name?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).trimmingCharacters(in: .whitespaces)
        let hash = id.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 }
        return appCategoryPalette[key.flatMap { named[$0] } ?? Int(hash % UInt32(appCategoryPalette.count))]
    }

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

public struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(Color.appPrimaryForeground)
            .background(Color.appPrimary.opacity(configuration.isPressed ? 0.85 : 1), in: RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

public struct OutlineButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        OutlineButton(configuration: configuration)
    }

    private struct OutlineButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: 12)
            configuration.label
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(Color.appForeground)
                .background(configuration.isPressed ? Color.appMuted : isHovered && isEnabled ? Color.appMuted.opacity(0.6) : Color.appCard, in: shape)
                .overlay(shape.stroke(Color.appBorder, lineWidth: 1))
                .contentShape(shape)
                .onHover { isHovered = $0 }
                .opacity(isEnabled ? 1 : 0.45)
        }
    }
}
