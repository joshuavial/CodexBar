import AppKit
import CodexBarCore

extension StatusItemController {
    struct MenuPopulateReusePlan {
        let canSmartUpdate: Bool
        let canPreserveProviderSwitcher: Bool
        let providerSwitcherWidthMatches: Bool
    }

    struct MenuPopulateReuseQuery {
        let enabledProviders: [UsageProvider]
        let includesOverview: Bool
        let switcherSelection: ProviderSwitcherSelection?
        let isOverviewSelected: Bool
        let menuWidth: CGFloat
        let codexAccountDisplay: CodexAccountMenuDisplay?
        let tokenAccountDisplay: TokenAccountMenuDisplay?
    }

    /// Decides how much of the existing menu content can be reused for this populate pass:
    /// a smart update (switcher and fixed rows kept), a switcher-preserving rebuild, or a
    /// full rebuild when neither set of compatibility checks holds.
    func menuPopulateReusePlan(menu: NSMenu, query: MenuPopulateReuseQuery) -> MenuPopulateReusePlan {
        let enabledProviders = query.enabledProviders
        let includesOverview = query.includesOverview
        let switcherSelection = query.switcherSelection
        let isOverviewSelected = query.isOverviewSelected
        let menuWidth = query.menuWidth
        let codexAccountDisplay = query.codexAccountDisplay
        let tokenAccountDisplay = query.tokenAccountDisplay
        let hasTokenSwitcher = menu.items.contains { $0.view is TokenAccountSwitcherView }
        let hasCodexSwitcher = menu.items.contains { $0.view is CodexAccountSwitcherView }
        let switcherProvidersMatch = enabledProviders == self.lastSwitcherProviders
        let switcherUsageBarsShowUsedMatch = self.settings.usageBarsShowUsed == self.lastSwitcherUsageBarsShowUsed
        let switcherSelectionMatches = switcherSelection == self.lastMergedSwitcherSelection
        let switcherOverviewAvailabilityMatches = includesOverview == self.lastSwitcherIncludesOverview
        let menuLocalizationMatches = self.menuLocalizationSignature() == self.lastMenuLocalizationSignature
        let tokenSwitcherCompatible = tokenAccountDisplay == self.lastTokenAccountMenuDisplay &&
            ((tokenAccountDisplay?.showSwitcher == true && hasTokenSwitcher) ||
                (tokenAccountDisplay?.showSwitcher != true && !hasTokenSwitcher))
        let codexSwitcherCompatible = codexAccountDisplay == self.lastCodexAccountMenuDisplay &&
            ((codexAccountDisplay?.showSwitcher == true && hasCodexSwitcher) ||
                (codexAccountDisplay?.showSwitcher != true && !hasCodexSwitcher))
        let reusableRowWidthsMatch = self.reusableFixedWidthRows(in: menu).allSatisfy { item in
            guard let view = item.view else { return false }
            return abs(view.frame.width - menuWidth) <= 0.5
        }
        let providerSwitcherWidthMatches = (menu.items.first?.view as? ProviderSwitcherView).map { view in
            abs(view.frame.width - menuWidth) <= 0.5
        } ?? false
        let canSmartUpdate = self.shouldMergeIcons &&
            enabledProviders.count > 1 &&
            !isOverviewSelected &&
            switcherProvidersMatch &&
            switcherUsageBarsShowUsedMatch &&
            switcherSelectionMatches &&
            switcherOverviewAvailabilityMatches &&
            menuLocalizationMatches &&
            tokenSwitcherCompatible &&
            codexSwitcherCompatible &&
            reusableRowWidthsMatch &&
            !menu.items.isEmpty &&
            menu.items.first?.view is ProviderSwitcherView
        let canPreserveProviderSwitcher = self.shouldMergeIcons &&
            enabledProviders.count > 1 &&
            switcherProvidersMatch &&
            switcherUsageBarsShowUsedMatch &&
            switcherOverviewAvailabilityMatches &&
            menuLocalizationMatches &&
            providerSwitcherWidthMatches &&
            !menu.items.isEmpty &&
            menu.items.first?.view is ProviderSwitcherView
        return MenuPopulateReusePlan(
            canSmartUpdate: canSmartUpdate,
            canPreserveProviderSwitcher: canPreserveProviderSwitcher,
            providerSwitcherWidthMatches: providerSwitcherWidthMatches)
    }
}
