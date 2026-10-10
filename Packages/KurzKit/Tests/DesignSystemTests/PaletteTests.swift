#if canImport(AppKit)
import AppKit
import Testing
@testable import DesignSystem

@Suite struct PaletteTests {
    private func rgb(_ name: String, _ appearance: NSAppearance.Name) -> [Int] {
        var out: [Int] = []
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            guard let color = NSColor(named: name, bundle: .module)?.usingColorSpace(.sRGB) else { return }
            let red = Int((color.redComponent * 255).rounded())
            let green = Int((color.greenComponent * 255).rounded())
            let blue = Int((color.blueComponent * 255).rounded())
            out = [red, green, blue]
        }
        return out
    }

    @Test func backgroundFollowsTheAppearance() {
        #expect(rgb("appBackground", .aqua) == [0xF7, 0xF8, 0xFA])
        #expect(rgb("appBackground", .darkAqua) == [0x10, 0x14, 0x18])
    }

    @Test func primaryFollowsTheAppearance() {
        #expect(rgb("appPrimary", .aqua) == [0x11, 0x6D, 0x6E])
        #expect(rgb("appPrimary", .darkAqua) == [0x4F, 0xB5, 0xB3])
    }
}
#endif
