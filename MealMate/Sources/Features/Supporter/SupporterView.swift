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

/// The supporter sheet: the pitch, the icons, the subscription (monthly or yearly) with what it
/// includes, one-time tips, and a thank-you once someone has chipped in. Purchases happen right
/// here; the header turns into the thank-you on success.
struct SupporterView: View {
    let context: SupporterViewContext

    @Environment(SupporterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showsManageSubscriptions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: SupporterLayout.sectionSpacing) {
                    header
                    SupporterIconShowcase()
                    purchaseSections
                    if context.isPrompt {
                        Button("Maybe Later") { dismiss() }
                            .buttonStyle(.glass)
                            .tint(.primary)
                            .controlSize(.large)
                    }
                    footer
                }
                .padding(.horizontal, SupporterLayout.pageInset)
                .padding(.top, Theme.Spacing.xxs)
                .padding(.bottom, 36)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .screenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A toolbar button, so scrolled content passes under the bar.
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationSizing(.page)
        .presentationDragIndicator(.visible)
        .manageSubscriptionsSheet(isPresented: $showsManageSubscriptions)
        .sensoryFeedback(.success, trigger: store.completedPurchaseCount)
        .task {
            if !store.hasProducts { await store.loadProducts() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            Image(systemName: "heart.fill")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(Color.accentColor.opacity(0.14), in: .circle)
                .padding(.bottom, Theme.Spacing.m)
                .accessibilityHidden(true)
            Text(headline)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .padding(.bottom, Theme.Spacing.xs)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if let supporterDetail {
                Text(supporterDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            }
        }
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
        if store.isSubscribed {
            return "You’re subscribed. Thank you for keeping MealMate free, independent and well looked after."
        }
        if store.isSupporter {
            return "You’re a supporter. Thank you for helping keep MealMate free and independent."
        }
        return "MealMate is free and independent: no ads, no tracking, made by one person. If it has earned a spot in your kitchen, you can chip in. Everything stays free either way."
    }

    private var supporterDetail: String? {
        guard store.isSupporter, let since = store.status.supporterSince else { return nil }
        var text = "Supporter since \(since.formatted(.dateTime.month(.wide).year()))"
        let tips = store.status.tipCount
        if tips > 0 { text += tips == 1 ? " · 1 tip" : " · \(tips) tips" }
        return text
    }

    // MARK: - Purchases

    @ViewBuilder
    private var purchaseSections: some View {
        if !store.hasProducts && !store.isSubscribed {
            productsPlaceholder
        } else {
            VStack(alignment: .leading, spacing: SupporterLayout.sectionSpacing) {
                VStack(alignment: .leading, spacing: SupporterLayout.labelSpacing) {
                    SupporterSectionLabel(title: "Recurring")
                    SupporterSubscriptionCard(showsManage: $showsManageSubscriptions)
                    // App Review wants the terms right at the subscription options: period and
                    // price on every button, renewal terms, Privacy Policy and Terms of Use (EULA).
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        SupporterFootnote(text: "Payment is charged to your Apple Account. The subscription renews automatically at the price shown unless cancelled at least 24 hours before the end of the current period; manage or cancel it in your Apple Account settings. Copper Pot and Midnight Kitchen are included while the subscription is active. Family Sharing included.")
                        SupporterLegalLinks()
                    }
                    .padding(.top, 2)
                }
                tips
                if let error = store.lastErrorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, SupporterLayout.cardInset)
                }
            }
        }
    }

    @ViewBuilder
    private var productsPlaceholder: some View {
        if store.productsUnavailable {
            VStack(spacing: Theme.Spacing.s) {
                Text("The App Store options couldn’t be loaded right now.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") { Task { await store.loadProducts() } }
                    .font(.subheadline.weight(.medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            .padding(.vertical, Theme.Spacing.s)
        } else {
            ProgressView()
                .padding(.vertical, Theme.Spacing.xl)
        }
    }

    @ViewBuilder
    private var tips: some View {
        if !store.tipProducts.isEmpty {
            VStack(alignment: .leading, spacing: SupporterLayout.labelSpacing) {
                SupporterSectionLabel(title: store.isSupporter ? "Support Again" : "One-Time")
                VStack(spacing: SupporterLayout.rowSpacing) {
                    ForEach(store.tipProducts, id: \.id) { product in
                        SupporterTipRow(product: product)
                    }
                }
                SupporterFootnote(text: "A tip is a one-time thank-you and can be given again anytime. From Brunch up it includes the five food icons, yours to keep.")
                    .padding(.top, 2)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Theme.Spacing.m) {
            Text("Everything in MealMate stays free either way: supporting unlocks app icons and keeps development going.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            // The subscription card carries Manage Subscription; this is the fallback while the
            // products can't load.
            if store.isSubscribed && store.subscriptionProducts.isEmpty {
                Button("Manage Subscription") { showsManageSubscriptions = true }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            Button {
                Task { await store.restorePurchases() }
            } label: {
                Text("Restore Purchases")
                    .busyOverlay(store.isRestoring)
            }
            .font(.subheadline)
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .disabled(store.isRestoring)
        }
        .padding(.horizontal, SupporterLayout.cardInset)
    }
}

enum SupporterLinks {
    static let privacyPolicy = URL(string: "https://github.com/marvinvr/mealmate/blob/main/PRIVACY.md")!
    /// Apple's standard EULA (App Review requires a terms link for subscriptions).
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

// MARK: - Layout

/// One spacing scale for the sheet, so every section, card and footnote keeps the same rhythm.
/// All text in a section (label, card content, footnote, the icon strip's first tile) starts on
/// one column, `pageInset + cardInset` from the edge, like an inset grouped list.
enum SupporterLayout {
    /// Between the sheet's sections (header, icons, subscription, tips, footer).
    static let sectionSpacing = Theme.Spacing.xxl
    /// Between a section label and its first card.
    static let labelSpacing: CGFloat = 10
    /// Between stacked cards in one section.
    static let rowSpacing: CGFloat = 10
    /// Horizontal page margin; the icon strip bleeds past it to the edge.
    static let pageInset = Theme.Spacing.screen
    /// Text inset inside every card, shared by section labels and footnotes.
    static let cardInset = Theme.Spacing.m
    static let cornerRadius = Theme.Radius.card
    /// The subscription card.
    static let featureCornerRadius: CGFloat = 22
}

private extension View {
    /// Surface fill and hairline shared by every card on the sheet.
    func supporterCard(cornerRadius: CGFloat = SupporterLayout.cornerRadius, stroke: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(.mealMateSurface, in: shape)
            .overlay { shape.strokeBorder(stroke ?? Color.primary.opacity(0.05), lineWidth: 1) }
            .contentShape(shape)
    }
}

// MARK: - Section label and footnote

/// Small uppercase label above a section's cards, on the cards' text column.
private struct SupporterSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, SupporterLayout.cardInset)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct SupporterFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineSpacing(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, SupporterLayout.cardInset)
    }
}

private struct SupporterLegalLinks: View {
    var body: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: SupporterLinks.privacyPolicy)
            Text("·").accessibilityHidden(true)
            Link("Terms of Use (EULA)", destination: SupporterLinks.termsOfUse)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.tint)
        .padding(.horizontal, SupporterLayout.cardInset)
    }
}

// MARK: - Subscription card

/// The one subscription: what it includes, then its two billing periods side by side, each with a
/// short line under it. While subscribed (a retired Sous Chef plan included) it shows the billing
/// period and Manage Subscription instead; switching periods goes through Manage Subscription.
private struct SupporterSubscriptionCard: View {
    @Binding var showsManage: Bool

    @Environment(SupporterStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MealMate Supporter")
                        .font(.headline.bold())
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Theme.Spacing.xs)
                if store.isSubscribed {
                    Text("Active")
                        .font(.caption2.bold())
                        .textCase(.uppercase)
                        .tracking(0.5)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.14), in: .capsule)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                perk("The five food icons, yours to keep")
                subscriptionIconsPerk
                perk("Keeps MealMate free, ad-free and independent")
            }

            actions
                .padding(.top, 2)
        }
        .padding(.horizontal, SupporterLayout.cardInset)
        .padding(.vertical, 18)
        .supporterCard(cornerRadius: SupporterLayout.featureCornerRadius,
                       stroke: store.isSubscribed ? Color.accentColor.opacity(0.45) : nil)
    }

    private var subtitle: String {
        guard store.isSubscribed else { return "Monthly or yearly. Cancel anytime." }
        guard let current = store.activeSubscription else { return "Thank you for subscribing." }
        return current.isYearly ? "Billed yearly" : "Billed monthly"
    }

    private func perk(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            SupporterCheckmark()
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subscriptionIconsPerk: some View {
        HStack(alignment: .center, spacing: 10) {
            SupporterCheckmark()
            Text("Two subscriber exclusives")
                .font(.footnote)
            HStack(spacing: 6) {
                ForEach(MealMateAppIcon.subscriptionIcons) { icon in
                    AppIconImage(icon: icon, size: 28)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two subscriber exclusives: "
            + MealMateAppIcon.subscriptionIcons.map(\.displayName).formatted(.list(type: .and)))
    }

    @ViewBuilder
    private var actions: some View {
        if store.isSubscribed {
            Button("Manage Subscription") { showsManage = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        } else if !store.subscriptionProducts.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) { priceOptions }
                VStack(spacing: Theme.Spacing.s) { priceOptions }
            }
        }
    }

    /// Each period's button with a short line under it, so both columns keep the same height and
    /// the savings sit under the yearly price.
    @ViewBuilder
    private var priceOptions: some View {
        ForEach(store.subscriptionProducts, id: \.id) { product in
            let isYearly = SupporterProduct(rawValue: product.id)?.isYearly == true
            VStack(spacing: 6) {
                SupporterPriceButton(product: product)
                Text(isYearly ? (savings ?? "Billed yearly") : "Billed monthly")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Saves 30%" from the monthly and yearly prices.
    private var savings: String? {
        let products = store.subscriptionProducts
        guard let monthly = products.first(where: { $0.id == SupporterProduct.monthly.rawValue }),
              let yearly = products.first(where: { $0.id == SupporterProduct.yearly.rawValue }),
              monthly.price > 0 else { return nil }
        let ratio = (yearly.price / (monthly.price * 12) as NSDecimalNumber).doubleValue
        let percent = Int(((1 - ratio) * 100).rounded())
        return percent > 0 ? "Saves \(percent)%" : nil
    }
}

private struct SupporterCheckmark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tint)
            .frame(width: 14)
            .accessibilityHidden(true)
    }
}

/// "$2.99 / month" as an equal-width capsule; a spinner while this product is being bought.
private struct SupporterPriceButton: View {
    let product: Product
    @Environment(SupporterStore.self) private var store

    var body: some View {
        let kind = SupporterProduct(rawValue: product.id)
        Button {
            Task { await store.purchase(product) }
        } label: {
            Text("\(product.displayPrice) / \(kind?.isYearly == true ? "year" : "month")")
                .monospacedDigit()
                .busyOverlay(store.purchasingProductID == product.id)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .tint(.accentColor)
        .disabled(store.purchasingProductID != nil)
        .accessibilityLabel("MealMate Supporter \(kind?.displayName ?? product.displayName), \(product.displayPrice) per \(kind?.isYearly == true ? "year" : "month")")
    }
}

// MARK: - Busy state

extension View {
    /// Swaps the view for a small spinner without changing its size: the view stays in the layout
    /// (hidden) and the spinner is an overlay, so a button keeps exactly its frame while busy.
    func busyOverlay(_ isBusy: Bool, alignment: Alignment = .center) -> some View {
        opacity(isBusy ? 0 : 1)
            .overlay(alignment: alignment) {
                if isBusy {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.small)
                }
            }
    }
}

// MARK: - Tip row

/// One tip: name, description and, from Brunch up, the food icons; the price on the right. The
/// spinner overlays the price, so the row never shifts while buying.
private struct SupporterTipRow: View {
    let product: Product
    @Environment(SupporterStore.self) private var store

    private var kind: SupporterProduct? { SupporterProduct(rawValue: product.id) }
    private var name: String { kind?.displayName ?? product.displayName }

    var body: some View {
        Button {
            Task { await store.purchase(product) }
        } label: {
            HStack(alignment: .center, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    if let description = kind?.tipDescription {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    if kind?.unlocksFoodIcons == true {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "checkmark")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.tint)
                            Text("Includes the five food icons")
                                .font(.caption)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, Theme.Spacing.xxs)
                    }
                }
                Spacer(minLength: 0)
                Text(product.displayPrice)
                    .font(.callout.weight(.semibold))
                    .monospacedDigit()
                    .busyOverlay(store.purchasingProductID == product.id, alignment: .trailing)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, SupporterLayout.cardInset)
            .padding(.vertical, 14)
            .supporterCard()
        }
        .buttonStyle(.plain)
        .disabled(store.purchasingProductID != nil)
        .accessibilityLabel("\(name) tip, \(product.displayPrice)"
            + (kind?.unlocksFoodIcons == true ? ", includes the five food icons" : ""))
    }
}

// MARK: - Icon showcase

/// Every app icon in one strip: the default and the food icons, then the subscription icons after
/// a hairline. Before a purchase it shows what supporting includes (locked tiles); unlocked tiles
/// apply on tap.
struct SupporterIconShowcase: View {
    @Environment(SupporterStore.self) private var store
    @State private var current: MealMateAppIcon = .default
    @State private var stripWidth: CGFloat = 0

    private static let tileSpacing: CGFloat = 14
    /// The strip bleeds this far past the content column, so tiles scroll out under the edge.
    private static let edgeInset = SupporterLayout.pageInset
    /// Where the label, caption and first tile start: the text column of the cards below.
    private static let textInset = SupporterLayout.cardInset

    /// Five tiles fit and a sixth is cut in half at the trailing edge: the cut tile shows the
    /// strip scrolls. A fixed size can land exactly on the edge on some devices and look complete.
    private var tileSize: CGFloat {
        guard stripWidth > 0 else { return 60 }
        return max(52, (stripWidth - Self.edgeInset - Self.textInset - 5 * Self.tileSpacing) / 5.5)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SupporterLayout.labelSpacing) {
            SupporterSectionLabel(title: store.hasFoodIcons ? "Your App Icons" : "Supporter Perk — App Icons")
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: Self.tileSpacing) {
                    ForEach(MealMateAppIcon.allCases.filter { $0.requirement != .subscription }) { icon in
                        tile(icon)
                    }
                    Rectangle()
                        .fill(Color.secondary.opacity(0.25))
                        .frame(width: 1, height: tileSize * 0.8)
                        .padding(.top, tileSize * 0.1)
                        .accessibilityHidden(true)
                    ForEach(MealMateAppIcon.subscriptionIcons) { icon in
                        tile(icon)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .contentMargins(.leading, Self.edgeInset + Self.textInset, for: .scrollContent)
            .contentMargins(.trailing, Self.edgeInset, for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { stripWidth = $0 }
            .padding(.horizontal, -Self.edgeInset)
            SupporterFootnote(text: caption)
        }
        .trackingAppIcon($current)
    }

    private func tile(_ icon: MealMateAppIcon) -> some View {
        let available = icon.isAvailable(hasFoodIcons: store.hasFoodIcons, isSubscribed: store.isSubscribed)
        return Button {
            guard available else { return }
            Task {
                try? await MealMateAppIcon.select(icon)
                current = .current
            }
        } label: {
            VStack(spacing: 6) {
                AppIconImage(icon: icon, size: tileSize, isSelected: current == icon, isLocked: !available)
                Text(icon.displayName)
                    .font(.caption2)
                    .foregroundStyle(icon.requirement == .subscription ? .primary : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: tileSize + Self.tileSpacing - 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(icon.displayName)
        .accessibilityValue(available ? (current == icon ? "Selected" : "") : "Locked")
    }

    private var caption: String {
        let exclusives = "Copper Pot and Midnight Kitchen come with the subscription"
        if store.isSubscribed { return "Tap an icon to use it." }
        if store.hasFoodIcons { return "Tap an icon to use it. \(exclusives)." }
        return "The subscription unlocks all seven icons, a tip from Brunch up the five food icons."
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
                shape.strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.08),
                                   lineWidth: isSelected ? 2 : 0.5)
            }
            .overlay(alignment: .bottomTrailing) {
                if isLocked {
                    // White on a dark disc reads on light and dark artwork, in either appearance.
                    Image(systemName: "lock.fill")
                        .font(.system(size: max(size * 0.14, 8), weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(size * 0.08)
                        .background(Color.black.opacity(0.55), in: .circle)
                        .padding(3)
                }
            }
            .accessibilityHidden(true)
    }
}
