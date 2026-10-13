import SwiftUI
import UIKit

/// The app icons. The default (a salad) is free; five food icons are a thank-you for the
/// subscription or a tip from Brunch up, for good; three are subscription icons that only stay on while it is active.
///
/// `alternateIconName` must match an `AppIcon<Name>.appiconset` in `AppIcons.xcassets` listed
/// in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (`project.yml`). The artwork and the
/// `IconPreview<Name>` images come from `Design/make-icon-variants.swift` (default and food
/// icons) and `Design/make-icon-subscriber.swift` (subscription icons).
enum MealMateAppIcon: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case grainBowl
    case spaghetti
    case shakshuka
    case ramen
    case margherita
    case enamelCocotte
    case candlelight
    case sundayBrunch

    enum Requirement: Sendable {
        /// Free for everyone.
        case free
        /// A subscription or a tip from Brunch up, ever (`SupporterStore.hasFoodIcons`).
        case supporter
        /// Only while a subscription is active.
        case subscription
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "MealMate"
        case .grainBowl: "Grain Bowl"
        case .spaghetti: "Spaghetti"
        case .shakshuka: "Shakshuka"
        case .ramen: "Ramen"
        case .margherita: "Margherita"
        case .enamelCocotte: "Enamel Cocotte"
        case .candlelight: "Candlelight"
        case .sundayBrunch: "Sunday Brunch"
        }
    }

    /// Name passed to `setAlternateIconName`; nil is the primary icon.
    var alternateIconName: String? {
        switch self {
        case .default: nil
        case .grainBowl: "AppIconGrainBowl"
        case .spaghetti: "AppIconSpaghetti"
        case .shakshuka: "AppIconShakshuka"
        case .ramen: "AppIconRamen"
        case .margherita: "AppIconMargherita"
        case .enamelCocotte: "AppIconEnamelCocotte"
        case .candlelight: "AppIconCandlelight"
        case .sundayBrunch: "AppIconSundayBrunch"
        }
    }

    /// Bundled preview (light and dark appearance) for the picker and the supporter sheet.
    var previewImageName: String {
        "IconPreview" + (alternateIconName?.replacing("AppIcon", with: "") ?? "Default")
    }

    var requirement: Requirement {
        switch self {
        case .default: .free
        case .enamelCocotte, .candlelight, .sundayBrunch: .subscription
        case .grainBowl, .spaghetti, .shakshuka, .ramen, .margherita: .supporter
        }
    }

    static var foodIcons: [MealMateAppIcon] { allCases.filter { $0.requirement == .supporter } }
    static var subscriptionIcons: [MealMateAppIcon] { allCases.filter { $0.requirement == .subscription } }

    func isAvailable(hasFoodIcons: Bool, isSubscribed: Bool) -> Bool {
        switch requirement {
        case .free: true
        case .supporter: hasFoodIcons || isSubscribed
        case .subscription: isSubscribed
        }
    }

    /// The icon to switch to because `current` is no longer included, or nil to keep it.
    /// The food icons never go away once unlocked, so in practice this falls back from a
    /// subscription icon after the subscription lapsed, or from a food icon set without them.
    static func fallback(for current: MealMateAppIcon, hasFoodIcons: Bool, isSubscribed: Bool) -> MealMateAppIcon? {
        current.isAvailable(hasFoodIcons: hasFoodIcons, isSubscribed: isSubscribed) ? nil : .default
    }

    // MARK: - Applying

    /// The home screen shows an icon this version no longer ships (Mono, Dark, Herb, Tomato,
    /// Pastel, Wood before the food icons replaced them; Copper Pot and Midnight Kitchen before the
    /// current subscription icons).
    @MainActor
    static var currentIsRetired: Bool {
        guard let name = UIApplication.shared.alternateIconName else { return false }
        return !allCases.contains { $0.alternateIconName == name }
    }

    @MainActor
    static var current: MealMateAppIcon {
        guard let name = UIApplication.shared.alternateIconName else { return .default }
        return allCases.first { $0.alternateIconName == name } ?? .default
    }

    /// Posted after the icon changed, also when the entitlement guard put the default back.
    static let didChangeNotification = Notification.Name("MealMateAppIconDidChange")

    /// Switches the home screen icon. The system confirms the change with its own alert.
    @MainActor
    static func select(_ icon: MealMateAppIcon) async throws {
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != icon.alternateIconName else { return }
        try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

/// Puts the default icon back when the current one is no longer included (the subscription
/// lapsed or was refunded) or no longer exists (a retired icon). Supporter status and unlocked food
/// icons are untouched. Runs once StoreKit
/// has confirmed the entitlements this launch, and again whenever the subscription state changes
/// or the app becomes active (`setAlternateIconName` only works while active).
private struct AppIconEntitlementGuard: ViewModifier {
    @Environment(SupporterStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: store.isSubscribed) { enforce() }
            .onChange(of: store.hasResolvedEntitlements) { enforce() }
            .onChange(of: scenePhase) { enforce() }
    }

    private func enforce() {
        guard scenePhase == .active else { return }
        if MealMateAppIcon.currentIsRetired {
            Task { try? await MealMateAppIcon.select(.default) }
            return
        }
        guard store.hasResolvedEntitlements,
              let fallback = MealMateAppIcon.fallback(for: .current, hasFoodIcons: store.hasFoodIcons,
                                                      isSubscribed: store.isSubscribed) else { return }
        Task { try? await MealMateAppIcon.select(fallback) }
    }
}

extension View {
    func appIconEntitlementGuard() -> some View {
        modifier(AppIconEntitlementGuard())
    }

    /// Keeps `current` in step with the home screen icon (picker, showcase, Settings row).
    func trackingAppIcon(_ current: Binding<MealMateAppIcon>) -> some View {
        task {
            current.wrappedValue = .current
            for await _ in NotificationCenter.default.notifications(named: MealMateAppIcon.didChangeNotification) {
                current.wrappedValue = .current
            }
        }
    }
}
