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

    private func contrast(_ first: [Int], _ second: [Int]) -> Double {
        func luminance(_ rgb: [Int]) -> Double {
            let linear = rgb.map { Double($0) / 255 }.map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
        }
        let sorted = [luminance(first), luminance(second)].sorted()
        return (sorted[1] + 0.05) / (sorted[0] + 0.05)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua]) func pendingBadgeMeetsAAContrast(_ appearance: NSAppearance.Name) {
        #expect(contrast(rgb("appPending", appearance), rgb("appPendingForeground", appearance)) >= 4.5)
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
