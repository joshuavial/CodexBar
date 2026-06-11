import AppKit
import CodexBarCore
import QuartzCore

struct MenuPopulatePhaseTiming {
    let label: String
    let durationMs: Double
}

extension StatusItemController {
    private static let defaultDeferredMenuInteractionRefreshDelay: Duration = .milliseconds(250)
    private static let slowMenuOperationThreshold: TimeInterval = 0.15
    private static let slowChartRenderThreshold: TimeInterval = 0.050

    #if DEBUG
    private static var deferredMenuInteractionRefreshDelayForTesting: Duration = .milliseconds(250)

    static func setDeferredMenuInteractionRefreshDelayForTesting(_ delay: Duration) {
        self.deferredMenuInteractionRefreshDelayForTesting = delay
    }

    static func resetDeferredMenuInteractionRefreshDelayForTesting() {
        self.deferredMenuInteractionRefreshDelayForTesting = self.defaultDeferredMenuInteractionRefreshDelay
    }
    #endif

    private static var deferredMenuInteractionRefreshDelay: Duration {
        #if DEBUG
        deferredMenuInteractionRefreshDelayForTesting
        #else
        defaultDeferredMenuInteractionRefreshDelay
        #endif
    }

    func logMenuOperationDurationIfSlow(
        _ operation: String,
        startedAt: CFTimeInterval,
        menu: NSMenu,
        provider: UsageProvider?,
        phases: [MenuPopulatePhaseTiming]? = nil)
    {
        let elapsed = CACurrentMediaTime() - startedAt
        guard elapsed >= Self.slowMenuOperationThreshold else { return }
        var metadata: [String: String] = [
            "operation": operation,
            "durationMs": String(format: "%.1f", elapsed * 1000),
            "items": "\(menu.items.count)",
            "provider": provider?.rawValue ?? "nil",
            "openMenus": "\(self.openMenus.count)",
            "storeRefreshing": self.store.isRefreshing ? "1" : "0",
        ]
        if let phases, !phases.isEmpty {
            metadata["phases"] = Self.formatMenuPopulatePhases(phases)
        }
        self.menuLogger.warning("slow menu operation", metadata: metadata)
    }

    /// Worst-first phase breakdown for the slow-operation log line, truncated so a
    /// card-heavy menu (one entry per card item) cannot flood the unified log.
    static func formatMenuPopulatePhases(
        _ phases: [MenuPopulatePhaseTiming],
        limit: Int = 12) -> String
    {
        let sorted = phases.sorted { $0.durationMs > $1.durationMs }
        let shown = sorted.prefix(limit)
            .map { "\($0.label)=\(String(format: "%.1f", $0.durationMs))" }
            .joined(separator: " ")
        let remainder = sorted.dropFirst(limit)
        guard !remainder.isEmpty else { return shown }
        let remainderMs = remainder.reduce(0) { $0 + $1.durationMs }
        return "\(shown) +\(remainder.count) more=\(String(format: "%.1f", remainderMs))"
    }

    func beginMenuPopulatePhaseCaptureIfNeeded() -> Bool {
        guard self.menuPopulatePhaseTimings == nil else { return false }
        self.menuPopulatePhaseTimings = []
        return true
    }

    func finishMenuPopulatePhaseCapture() -> [MenuPopulatePhaseTiming]? {
        defer { self.menuPopulatePhaseTimings = nil }
        return self.menuPopulatePhaseTimings
    }

    func recordMenuPopulatePhase(_ label: String, startedAt: CFTimeInterval) {
        guard self.menuPopulatePhaseTimings != nil else { return }
        self.menuPopulatePhaseTimings?
            .append(MenuPopulatePhaseTiming(
                label: label,
                durationMs: (CACurrentMediaTime() - startedAt) * 1000))
    }

    func recordMenuPopulatePhase<T>(_ label: String, _ work: () -> T) -> T {
        guard self.menuPopulatePhaseTimings != nil else { return work() }
        let startedAt = CACurrentMediaTime()
        let result = work()
        self.recordMenuPopulatePhase(label, startedAt: startedAt)
        return result
    }

    func logChartRenderDurationIfSlow(_ label: String, startedAt: CFTimeInterval) {
        let elapsed = CACurrentMediaTime() - startedAt
        guard elapsed >= Self.slowChartRenderThreshold else { return }
        self.menuLogger.warning(
            "slow chart render",
            metadata: [
                "section": label,
                "durationMs": String(format: "%.1f", elapsed * 1000),
            ])
    }

    func deferMenuInteractionRefreshIfNeeded(providers: [UsageProvider]) {
        guard !self.store.isRefreshing else { return }
        self.deferredMenuInteractionRefreshProviders.formUnion(providers)
    }

    func clearSatisfiedDeferredMenuInteractionRefreshes(for providers: [UsageProvider]) {
        for provider in providers
            where !self.store.isStale(provider: provider) && self.store.snapshot(for: provider) != nil
        {
            self.deferredMenuInteractionRefreshProviders.remove(provider)
        }
    }

    func deferOpenAIDashboardRefreshUntilMenuCloses(reason: String) {
        if let existingReason = self.deferredOpenAIDashboardRefreshReason {
            self.deferredOpenAIDashboardRefreshReason = "\(existingReason), \(reason)"
        } else {
            self.deferredOpenAIDashboardRefreshReason = reason
        }
    }

    func cancelDeferredMenuInteractionRefreshTask() {
        self.deferredMenuInteractionRefreshTask?.cancel()
        self.deferredMenuInteractionRefreshTask = nil
    }

    func scheduleDeferredMenuInteractionRefreshIfNeeded(delay: Duration? = nil) {
        guard self.openMenus.isEmpty else { return }
        guard self.deferredMenuInteractionRefreshPending || self.deferredOpenAIDashboardRefreshReason != nil else {
            return
        }
        guard !self.hasPreparedForAppShutdown else { return }

        self.cancelDeferredMenuInteractionRefreshTask()
        let delay = delay ?? Self.deferredMenuInteractionRefreshDelay
        self.deferredMenuInteractionRefreshTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            guard self.openMenus.isEmpty else {
                self.deferredMenuInteractionRefreshTask = nil
                return
            }
            let shouldRefreshStore = self.deferredMenuInteractionRefreshPending
            let openAIDashboardRefreshReason = self.deferredOpenAIDashboardRefreshReason
            guard shouldRefreshStore || openAIDashboardRefreshReason != nil else {
                self.deferredMenuInteractionRefreshTask = nil
                return
            }
            guard !self.hasPreparedForAppShutdown else {
                self.deferredMenuInteractionRefreshTask = nil
                return
            }
            guard !self.store.isRefreshing else {
                self.deferredMenuInteractionRefreshTask = nil
                self
                    .scheduleDeferredMenuInteractionRefreshIfNeeded(delay: Self
                        .defaultDeferredMenuInteractionRefreshDelay)
                return
            }
            self.deferredMenuInteractionRefreshTask = nil
            self.deferredMenuInteractionRefreshProviders.removeAll()
            self.deferredOpenAIDashboardRefreshReason = nil
            #if DEBUG
            self.onDeferredMenuInteractionRefreshForTesting?()
            #endif
            if shouldRefreshStore {
                await self.performStoreRefresh(
                    forceTokenUsage: false,
                    refreshOpenMenusWhenComplete: false,
                    interaction: .background)
                guard !Task.isCancelled else { return }
            }
            if let openAIDashboardRefreshReason {
                guard self.openMenus.isEmpty else {
                    self.deferOpenAIDashboardRefreshUntilMenuCloses(reason: openAIDashboardRefreshReason)
                    return
                }
                // Keep menu-originated automatic dashboard refreshes non-interactive:
                // opening a menu is not consent to show macOS Keychain prompts.
                self.store.requestOpenAIDashboardRefreshIfStale(reason: openAIDashboardRefreshReason)
            }
        }
    }
}
