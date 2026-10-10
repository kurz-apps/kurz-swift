#if os(macOS)
import AppKit
import SwiftUI

struct MacWindowSizing: NSViewRepresentable {
    let isSignedIn: Bool

    static let loginSize = CGSize(width: 590, height: 610)
    static let appSize = CGSize(width: 1180, height: 760)
    static let appMinimumSize = CGSize(width: 880, height: 560)

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        let signedIn = isSignedIn
        DispatchQueue.main.async {
            guard let window = view.window, context.coordinator.lastSignedIn != signedIn else { return }
            let first = context.coordinator.lastSignedIn == nil
            context.coordinator.lastSignedIn = signedIn
            window.contentMinSize = signedIn ? Self.appMinimumSize : Self.loginSize
            let target = signedIn ? Self.appSize : Self.loginSize
            let content = window.contentRect(forFrameRect: window.frame).size
            guard first == false || abs(content.width - target.width) > 1 || abs(content.height - target.height) > 1 else { return }
            let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            let size = CGSize(width: min(target.width, visible.width), height: min(target.height, visible.height))
            var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: size))
            frame.origin.x = window.frame.midX - frame.width / 2
            frame.origin.y = window.frame.midY - frame.height / 2
            frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
            frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
            window.setFrame(frame, display: true, animate: !first)
        }
    }

    final class Coordinator {
        var lastSignedIn: Bool?
    }
}
#endif
