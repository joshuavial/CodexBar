import AppKit
import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct MenuPopulatePhaseTimingTests {
    private func makeController() -> StatusItemController {
        _ = NSApplication.shared
        let settings = SettingsStore(
            configStore: testConfigStore(suiteName: "MenuPopulatePhaseTiming"),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        let fetcher = UsageFetcher()
        let store = UsageStore(
            fetcher: fetcher,
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings)
        return StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: .system)
    }

    @Test
    func `phases format worst-first`() {
        let formatted = StatusItemController.formatMenuPopulatePhases([
            MenuPopulatePhaseTiming(label: "descriptor", durationMs: 2.04),
            MenuPopulatePhaseTiming(label: "primaryContent", durationMs: 4012.5),
            MenuPopulatePhaseTiming(label: "width", durationMs: 18.2),
        ])
        #expect(formatted == "primaryContent=4012.5 width=18.2 descriptor=2.0")
    }

    @Test
    func `phases beyond the limit collapse into a remainder total`() {
        let phases = (0..<15).map { index in
            MenuPopulatePhaseTiming(label: "cardItem:\(index)", durationMs: Double(100 - index))
        }
        let formatted = StatusItemController.formatMenuPopulatePhases(phases, limit: 12)
        #expect(formatted.hasSuffix("+3 more=261.0"))
        #expect(formatted.contains("cardItem:0=100.0"))
        #expect(!formatted.contains("cardItem:12=88.0"))
    }

    @Test
    func `phase capture records phases and clears after finish`() {
        let controller = self.makeController()
        defer { controller.releaseStatusItemsForTesting() }

        #expect(controller.recordMenuPopulatePhase("ignored") { 1 } == 1)

        #expect(controller.beginMenuPopulatePhaseCaptureIfNeeded())
        #expect(!controller.beginMenuPopulatePhaseCaptureIfNeeded())
        let value = controller.recordMenuPopulatePhase("outer") { 42 }
        #expect(value == 42)
        let phases = controller.finishMenuPopulatePhaseCapture()
        #expect(phases?.map(\.label) == ["outer"])
        #expect(controller.finishMenuPopulatePhaseCapture() == nil)
    }
}
