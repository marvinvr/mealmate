import SwiftUI
import UIKit

/// The app icons. The default is free; the alternates are a thank-you for supporters, and two
/// are Head Chef exclusives that only stay on while that subscription is active.
///
/// `alternateIconName` must match an `AppIcon<Name>.appiconset` in `AppIcons.xcassets` listed
/// in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` (`project.yml`). The artwork and the
/// `IconPreview<Name>` images come from `Design/make-icon.swift`.
enum MealMateAppIcon: String, CaseIterable, Identifiable, Sendable {
    case `default`
    case mono
    case dark
    case herb
    case tomato
    case pastel
    case wood
    case copperPot
    case midnightKitchen

    enum Requirement: Sendable {
        case free, supporter, headChef
    }

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .default: "MealMate"
        case .mono: "Mono"
        case .dark: "Dark"
        case .herb: "Herb"
        case .tomato: "Tomato"
        case .pastel: "Pastel"
        case .wood: "Wood"
        case .copperPot: "Copper Pot"
        case .midnightKitchen: "Midnight Kitchen"
        }
    }

    /// Name passed to `setAlternateIconName`; nil is the primary icon.
    var alternateIconName: String? {
        switch self {
        case .default: nil
        case .mono: "AppIconMono"
        case .dark: "AppIconDark"
        case .herb: "AppIconHerb"
        case .tomato: "AppIconTomato"
        case .pastel: "AppIconPastel"
        case .wood: "AppIconWood"
        case .copperPot: "AppIconCopperPot"
        case .midnightKitchen: "AppIconMidnightKitchen"
        }
    }

    /// Bundled preview (light and dark appearance) for the picker and the supporter sheet.
    var previewImageName: String {
        "IconPreview" + (alternateIconName?.replacing("AppIcon", with: "") ?? "Default")
    }

    var requirement: Requirement {
        switch self {
        case .default: .free
        case .copperPot, .midnightKitchen: .headChef
        default: .supporter
        }
    }

    static var supporterIcons: [MealMateAppIcon] { allCases.filter { $0.requirement != .headChef } }
    static var headChefIcons: [MealMateAppIcon] { allCases.filter { $0.requirement == .headChef } }

    func isAvailable(isSupporter: Bool, tier: SupporterTier) -> Bool {
        switch requirement {
        case .free: true
        case .supporter: isSupporter
        case .headChef: tier == .headChef
        }
    }

    /// The icon to switch to because `current` is no longer included, or nil to keep it.
    /// Supporter status never goes away, so in practice this only falls back from a Head Chef
    /// icon after that subscription lapsed.
    static func fallback(for current: MealMateAppIcon, isSupporter: Bool, tier: SupporterTier) -> MealMateAppIcon? {
        current.isAvailable(isSupporter: isSupporter, tier: tier) ? nil : .default
    }

    // MARK: - Applying

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

/// Puts the default icon back when the current one is no longer included (Head Chef lapsed or
/// was refunded). Supporter status and other icons are untouched. Runs once StoreKit has
/// confirmed the entitlements this launch, and again whenever the level changes or the app
/// becomes active (`setAlternateIconName` only works while active).
private struct AppIconEntitlementGuard: ViewModifier {
    @Environment(SupporterStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: store.activeTier) { enforce() }
            .onChange(of: store.hasResolvedEntitlements) { enforce() }
            .onChange(of: scenePhase) { enforce() }
    }

    private func enforce() {
        guard store.hasResolvedEntitlements, scenePhase == .active,
              let fallback = MealMateAppIcon.fallback(for: .current, isSupporter: store.isSupporter,
                                                      tier: store.activeTier) else { return }
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
