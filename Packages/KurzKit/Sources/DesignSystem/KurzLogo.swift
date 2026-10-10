import SwiftUI

public struct KurzLogo: View {
    public var size: CGFloat

    public init(size: CGFloat = 64) { self.size = size }

    public var body: some View {
        Canvas { context, canvas in
            let k = canvas.width / 64
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }

            let tile = Path(roundedRect: CGRect(origin: .zero, size: canvas), cornerRadius: 15 * k)
            context.fill(tile, with: .color(Color(hex: 0x101418)))
            context.stroke(Path(roundedRect: CGRect(x: 0.75 * k, y: 0.75 * k, width: 62.5 * k, height: 62.5 * k), cornerRadius: 14.25 * k), with: .color(Color(hex: 0x29333C)), lineWidth: 1.5 * k)
            context.fill(Path(roundedRect: CGRect(x: 14 * k, y: 13 * k, width: 10 * k, height: 38 * k), cornerRadius: 2.5 * k), with: .color(Color(hex: 0xEEF2F5)))

            var lower = Path()
            lower.move(to: point(27, 32)); lower.addLine(to: point(38.5, 32)); lower.addLine(to: point(52, 51)); lower.addLine(to: point(40.5, 51)); lower.closeSubpath()
            context.fill(lower, with: .linearGradient(Gradient(colors: [Color(hex: 0x1F8F8B), Color(hex: 0x136E6B)]), startPoint: point(27, 32), endPoint: point(52, 51)))

            var upper = Path()
            upper.move(to: point(27, 32)); upper.addLine(to: point(40.5, 13)); upper.addLine(to: point(52, 13)); upper.addLine(to: point(38.5, 32)); upper.closeSubpath()
            context.fill(upper, with: .linearGradient(Gradient(colors: [Color(hex: 0x7AE0DC), Color(hex: 0x2FA9A5)]), startPoint: point(27, 13), endPoint: point(52, 32)))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
