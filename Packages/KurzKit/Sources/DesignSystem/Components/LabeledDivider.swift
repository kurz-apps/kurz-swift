import SwiftUI

public struct LabeledDivider: View {
    let title: LocalizedStringKey
    let titleIdentifier: String?

    public init(_ title: LocalizedStringKey, titleIdentifier: String? = nil) {
        self.title = title
        self.titleIdentifier = titleIdentifier
    }

    public var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Color.appBorder).frame(height: 1)
            Text(title).font(.footnote).foregroundStyle(Color.appMutedForeground).accessibilityIdentifier(titleIdentifier ?? "")
            Rectangle().fill(Color.appBorder).frame(height: 1)
        }
    }
}

#Preview("LabeledDivider · light") {
    LabeledDivider("or").padding(24).background(Color.appCard).preferredColorScheme(.light)
}

#Preview("LabeledDivider · dark") {
    LabeledDivider("or").padding(24).background(Color.appCard).preferredColorScheme(.dark)
}
