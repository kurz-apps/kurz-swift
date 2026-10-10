import SwiftUI

public struct StatusBadge: View {
    public enum Status: Equatable, Sendable {
        case pending, confirmed, unverified, other(String)

        public init(_ value: String) {
            switch value {
            case "pending": self = .pending
            case "confirmed": self = .confirmed
            case "unverified": self = .unverified
            default: self = .other(value)
            }
        }

        var label: LocalizedStringKey {
            switch self {
            case .pending: "Pending"
            case .confirmed: "Confirmed"
            case .unverified: "Unverified"
            case .other(let value): LocalizedStringKey(value.capitalized)
            }
        }
    }

    let status: Status

    public init(_ status: Status) { self.status = status }

    public init(status: String) { self.status = Status(status) }

    public var body: some View {
        Text(status.label).font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .foregroundStyle(status == .pending ? Color.appPendingForeground : Color.appPrimaryForeground)
            .background(status == .pending ? Color.appPending : Color.appPrimary, in: Capsule())
    }
}

private struct StatusBadgePreview: View {
    var body: some View {
        HStack {
            StatusBadge(.pending)
            StatusBadge(.confirmed)
            StatusBadge(.unverified)
        }
        .padding()
        .background(Color.appBackground)
    }
}

#Preview("StatusBadge · light") { StatusBadgePreview().preferredColorScheme(.light) }

#Preview("StatusBadge · dark") { StatusBadgePreview().preferredColorScheme(.dark) }
