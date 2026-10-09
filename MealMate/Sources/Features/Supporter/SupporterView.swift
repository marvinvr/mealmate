import StoreKit
import SwiftUI

/// Where the supporter sheet was opened from. A prompt changes the headline and adds a
/// "Maybe Later" button; everything else is identical so the two never drift apart.
enum SupporterViewContext: Equatable {
    case settings
    /// 1-based position in this device's prompt sequence.
    case prompt(number: Int)

    var isPrompt: Bool {
        if case .prompt = self { return true }
        return false
    }
}

/// The supporter sheet: the pitch, the two subscription levels side by side with what each
/// includes, one-time tips, the icons, and a thank-you once someone has chipped in. Purchases
/// happen right here; the header turns into the thank-you on success.
struct SupporterView: View {
    let context: SupporterViewContext

    @Environment(SupporterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showsManageSubscriptions = false

    private var isRegular: Bool { horizontalSizeClass == .regular }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xxl) {
                    header
                    SupporterIconShowcase()
                    plans
                    tips
                    if context.isPrompt {
                        Button("Maybe Later") { dismiss() }
                            .buttonStyle(.glass)
                            .tint(.primary)
                            .controlSize(.large)
                    }
                    footer
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: isRegular ? 820 : 560)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationSizing(.page)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .sensoryFeedback(.success, trigger: store.completedPurchaseCount)
        .task {
            if !store.hasProducts { await store.loadProducts() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Theme.Spacing.s) {
            Image(systemName: store.isSupporter ? "heart.fill" : "heart")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.opacity(0.16), in: .circle)
                .accessibilityHidden(true)
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            if let supporterDetail {
                Text(supporterDetail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, Theme.Spacing.s)
        .animation(.smooth, value: store.isSupporter)
    }

    private var headline: String {
        if store.isSupporter { return "Thank You" }
        switch context {
        case .settings: return "Support MealMate"
        case .prompt(let number): return number <= 1 ? "Enjoying MealMate?" : "Still Cooking with MealMate?"
        }
    }

    private var message: String {
        switch store.activeTier {
        case .headChef:
            return "You’re a Head Chef. Thank you for keeping MealMate free, independent and well looked after."
        case .sousChef:
            return "You’re a Sous Chef. Thank you for keeping MealMate free, independent and well looked after."
        case .none where store.isSupporter:
            return "You’re a supporter. Thank you for helping keep MealMate free and independent."
        case .none:
            return "MealMate is free and independent: no ads, no tracking, made by one person. If it has earned a spot in your kitchen, you can chip in. Everything stays free either way."
        }
    }

    private var supporterDetail: String? {
        guard store.isSupporter, let since = store.status.supporterSince else { return nil }
        var text = "Supporter since \(since.formatted(.dateTime.month(.wide).year()))"
        let tips = store.status.tipCount
        if tips > 0 { text += tips == 1 ? " · 1 tip" : " · \(tips) tips" }
        return text
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        let layout = isRegular
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.m))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.m))
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SupporterSectionHeader(title: store.hasActiveSubscription ? "Your Subscription" : "Monthly or Yearly")
            if store.hasProducts {
                layout {
                    // A Head Chef sees their own plan first.
                    ForEach(store.isHeadChef ? [SupporterTier.headChef, .sousChef] : [.sousChef, .headChef],
                            id: \.self) { tier in
                        SupporterPlanCard(tier: tier,
                                          products: tier == .headChef ? store.headChefProducts : store.sousChefProducts,
                                          showsManage: $showsManageSubscriptions)
                    }
                }
                // App Review wants the terms right at the subscription options: period and price
                // on every button, renewal terms, Privacy Policy and Terms of Use (EULA).
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text("Payment is charged to your Apple Account. Subscriptions renew automatically at the price shown unless cancelled at least 24 hours before the end of the current period; manage or cancel them in your Apple Account settings. Family Sharing included.")
                    HStack(spacing: Theme.Spacing.xs) {
                        Link("Privacy Policy", destination: SupporterLinks.privacyPolicy)
                        Text("·").accessibilityHidden(true)
                        Link("Terms of Use (EULA)", destination: SupporterLinks.termsOfUse)
                    }
                    .tint(.accentColor)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                productsPlaceholder
            }
            if let error = store.lastErrorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var productsPlaceholder: some View {
        if store.productsUnavailable {
            VStack(spacing: Theme.Spacing.s) {
                Text("The App Store options couldn’t be loaded right now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await store.loadProducts() } }
                    .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .surfaceCard()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 120)
        }
    }

    // MARK: - Tips

    @ViewBuilder
    private var tips: some View {
        if !store.tipProducts.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SupporterSectionHeader(title: store.isSupporter ? "Leave Another Tip" : "One-Time Tip")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s),
                                         count: isRegular ? 4 : 2),
                          spacing: Theme.Spacing.s) {
                    ForEach(store.tipProducts, id: \.id) { product in
                        SupporterTipButton(product: product)
                    }
                }
                Text("A tip is a one-time thank-you. It makes you a supporter for good, with all six supporter icons.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Supporting changes nothing about what MealMate can do: every feature is free for everyone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: Theme.Spacing.l) {
                if store.hasActiveSubscription {
                    Button("Manage Subscription") { showsManageSubscriptions = true }
                }
                Button {
                    Task { await store.restorePurchases() }
                } label: {
                    if store.isRestoring {
                        ProgressView()
                    } else {
                        Text("Restore Purchases")
                    }
                }
                .disabled(store.isRestoring)
            }
            .font(.subheadline)
        }
    }
}

enum SupporterLinks {
    static let privacyPolicy = URL(string: "https://github.com/marvinvr/mealmate/blob/main/PRIVACY.md")!
    /// Apple's standard EULA (App Review requires a terms link for subscriptions).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

// MARK: - Section header

private struct SupporterSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.sectionTitle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Plan card

/// One subscription level: what it includes, then its monthly and yearly price. Shows "Your
/// Plan" while active; Sous Chef subscribers see Head Chef as an upgrade, Head Chefs see Sous
/// Chef as included (switching down goes through Manage Subscription).
private struct SupporterPlanCard: View {
    let tier: SupporterTier
    let products: [Product]
    @Binding var showsManage: Bool

    @Environment(SupporterStore.self) private var store

    private var isCurrent: Bool { store.activeTier == tier }
    private var isIncluded: Bool { store.activeTier > tier }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(tier.title)
                        .font(.title3.bold())
                    Text(tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if isCurrent {
                    badge("Your Plan")
                } else if isIncluded {
                    badge("Included")
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(perks, id: \.text) { perk in
                    Label {
                        Text(perk.text)
                    } icon: {
                        Image(systemName: perk.symbol)
                            .foregroundStyle(.tint)
                    }
                    .font(.subheadline)
                }
            }

            if tier == .headChef {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(MealMateAppIcon.headChefIcons) { icon in
                        HStack(spacing: Theme.Spacing.xs) {
                            AppIconImage(icon: icon, size: 36)
                            Text(icon.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Spacer(minLength: 0)
            actions
        }
        .surfaceCard()
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isCurrent ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.06),
                              lineWidth: isCurrent ? 1.5 : 0.5)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var tagline: String {
        switch tier {
        case .headChef: "The biggest help, with two exclusive icons."
        default: "Keep MealMate cooking."
        }
    }

    private struct Perk { let symbol: String; let text: String }

    private var perks: [Perk] {
        switch tier {
        case .headChef:
            [Perk(symbol: "checkmark.circle", text: "Everything in Sous Chef"),
             Perk(symbol: "sparkles", text: "Two Head Chef icons, yours while the subscription is active")]
        default:
            [Perk(symbol: "app.badge", text: "Six alternate app icons, yours for good"),
             Perk(symbol: "heart", text: "Helps keep MealMate free, ad-free and independent")]
        }
    }

    @ViewBuilder
    private var actions: some View {
        if isCurrent {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if let current = store.activeSubscriptionID.flatMap(SupporterProduct.init(rawValue:)) {
                    Text(current.isYearly ? "Billed yearly" : "Billed monthly")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button("Manage Subscription") { showsManage = true }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        } else if isIncluded {
            Text("Part of your Head Chef subscription. Switch levels in Manage Subscription.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if !products.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Theme.Spacing.xs) { priceButtons }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) { priceButtons }
                }
                if let savings {
                    Text(store.activeTier == .sousChef && tier == .headChef
                         ? "Upgrading starts right away; App Store prorates what’s left. \(savings)"
                         : savings)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var priceButtons: some View {
        ForEach(products, id: \.id) { product in
            SupporterPriceButton(product: product)
        }
    }

    /// "Yearly saves 37%." from the monthly and yearly prices.
    private var savings: String? {
        guard let monthly = products.first(where: { SupporterProduct(rawValue: $0.id)?.isYearly == false }),
              let yearly = products.first(where: { SupporterProduct(rawValue: $0.id)?.isYearly == true }),
              monthly.price > 0 else { return nil }
        let ratio = (yearly.price / (monthly.price * 12) as NSDecimalNumber).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? "Yearly saves \(percent)%." : nil
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.vertical, Theme.Spacing.xxs)
            .background(Color.accentColor.opacity(0.16), in: .capsule)
    }
}

/// "$1.99 / month" as a capsule; a spinner while this product is being bought.
private struct SupporterPriceButton: View {
    let product: Product
    @Environment(SupporterStore.self) private var store

    var body: some View {
        let kind = SupporterProduct(rawValue: product.id)
        Button {
            Task { await store.purchase(product) }
        } label: {
            ZStack {
                Text("\(product.displayPrice) / \(kind?.isYearly == true ? "year" : "month")")
                    .monospacedDigit()
                    .opacity(store.purchasingProductID == product.id ? 0 : 1)
                if store.purchasingProductID == product.id {
                    ProgressView()
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.xxs)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(.accentColor)
        .disabled(store.purchasingProductID != nil)
        .accessibilityLabel("\(kind?.tier?.title ?? "") \(kind?.isYearly == true ? "yearly" : "monthly"), \(product.displayPrice)")
    }
}

// MARK: - Tip button

private struct SupporterTipButton: View {
    let product: Product
    @Environment(SupporterStore.self) private var store

    private var kind: SupporterProduct? { SupporterProduct(rawValue: product.id) }

    var body: some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(height: 28)
                Text(kind?.displayName ?? product.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                ZStack(alignment: .leading) {
                    Text(product.displayPrice)
                        .monospacedDigit()
                        .opacity(store.purchasingProductID == product.id ? 0 : 1)
                    if store.purchasingProductID == product.id {
                        ProgressView().controlSize(.small)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surfaceCard(padding: Theme.Spacing.m)
            .contentShape(.rect(cornerRadius: Theme.Radius.card))
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingProductID != nil)
        .accessibilityLabel("\(kind?.displayName ?? product.displayName) tip, \(product.displayPrice)")
    }

    private var symbol: String {
        switch kind {
        case .tipEspresso: "cup.and.saucer"
        case .tipBrunch: "frying.pan"
        case .tipDinnerParty: "wineglass"
        case .tipFeast: "fork.knife"
        default: "heart"
        }
    }
}

// MARK: - Icon showcase

/// The supporter icons and the two Head Chef icons in one strip. Before a purchase it shows
/// what supporting includes (locked tiles); afterwards a tap applies an icon.
struct SupporterIconShowcase: View {
    @Environment(SupporterStore.self) private var store
    @State private var current: MealMateAppIcon = .default

    private static let tileSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SupporterSectionHeader(title: "App Icons")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    ForEach(MealMateAppIcon.allCases.filter { $0 != .default }) { icon in
                        tile(icon)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, Theme.Spacing.xxs)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.horizontal, Theme.Spacing.screen, for: .scrollContent)
            .padding(.horizontal, -Theme.Spacing.screen)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .trackingAppIcon($current)
    }

    private func tile(_ icon: MealMateAppIcon) -> some View {
        let available = icon.isAvailable(isSupporter: store.isSupporter, tier: store.activeTier)
        return Button {
            guard available else { return }
            Task {
                try? await MealMateAppIcon.select(icon)
                current = .current
            }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                AppIconImage(icon: icon, size: Self.tileSize, isSelected: current == icon,
                             isLocked: !available)
                Text(icon.displayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: Self.tileSize + 8)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.displayName)
        .accessibilityValue(available ? (current == icon ? "Selected" : "") : "Locked")
    }

    private var caption: String {
        if store.isHeadChef { return "Tap an icon to use it on your Home Screen." }
        if store.isSupporter { return "Tap an icon to use it. Copper Pot and Midnight Kitchen come with Head Chef." }
        return "Any tip or subscription unlocks six icons for good. Copper Pot and Midnight Kitchen come with Head Chef."
    }
}

// MARK: - App icon image

/// An app icon preview in the Home Screen's rounded shape, with the selected ring or a lock.
struct AppIconImage: View {
    let icon: MealMateAppIcon
    var size: CGFloat = 60
    var isSelected = false
    var isLocked = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Image(icon.previewImageName)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: size * 0.225 + 4, style: .continuous)
                        .strokeBorder(.tint, lineWidth: 2)
                        .padding(-4)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(size * 0.16, 9), weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(size * 0.08)
                        .background(.thinMaterial, in: .circle)
                        .offset(x: 3, y: 3)
                }
            }
            .accessibilityHidden(true)
    }
}
