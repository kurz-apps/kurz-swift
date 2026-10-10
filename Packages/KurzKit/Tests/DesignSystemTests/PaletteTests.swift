#if canImport(AppKit)
import AppKit
import SwiftUI
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

    private func over(_ color: [Int], _ alpha: Double, _ background: [Int]) -> [Int] {
        zip(color, background).map { Int((Double($0) * alpha + Double($1) * (1 - alpha)).rounded()) }
    }

    @Test func contrastHelperMatchesWCAG() {
        #expect(abs(contrast([255, 255, 255], [0, 0, 0]) - 21) < 0.01)
        #expect(contrast([0x77, 0x77, 0x77], [0x77, 0x77, 0x77]) == 1)
        #expect(abs(contrast([255, 255, 255], [0xB4, 0x23, 0x2F]) - 6.52) < 0.01)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua]) func todayNumeralMeetsAAContrast(_ appearance: NSAppearance.Name) {
        #expect(contrast(rgb("appDestructive", appearance), rgb("appDestructiveForeground", appearance)) >= 4.5)
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua]) func categoryColorsStandOutFromTheBackground(_ appearance: NSAppearance.Name) {
        for name in Color.appCategoryNames {
            #expect(contrast(rgb(name, appearance), rgb("appBackground", appearance)) >= 3, "\(name)")
            #expect(contrast(rgb(name, appearance), rgb("appCard", appearance)) >= 3, "\(name)")
        }
    }

    @Test(arguments: [NSAppearance.Name.aqua, .darkAqua]) func blockTextStaysReadableOnCategoryTints(_ appearance: NSAppearance.Name) {
        let alpha = appearance == .aqua ? Color.appCategoryTintOpacity.light : Color.appCategoryTintOpacity.dark
        for name in Color.appCategoryNames {
            let tint = over(rgb(name, appearance), alpha, rgb("appBackground", appearance))
            #expect(contrast(rgb("appForeground", appearance), tint) >= 4.5, "\(name)")
            #expect(contrast(rgb("appMutedForeground", appearance), tint) >= 4.5, "\(name)")
        }
    }

    @Test func lightCategoryColorsKeepTheDesignOrder() {
        #expect(rgb("appCategoryViolet", .aqua) == [0x98, 0x7B, 0xE9])
        #expect(rgb("appCategoryOrange", .aqua) == [0xA6, 0x5F, 0x0B])
        #expect(rgb("appCategoryTeal", .aqua) == [0x1B, 0x93, 0x90])
        #expect(rgb("appCategoryBlue", .aqua) == [0x36, 0x73, 0xB7])
        #expect(rgb("appCategoryGreen", .aqua) == [0x50, 0x93, 0x41])
        #expect(rgb("appCategoryViolet", .darkAqua) == [0xA7, 0x8B, 0xFA])
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
