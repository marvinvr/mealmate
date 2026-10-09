import SwiftUI

// MARK: - Ingredients

struct IngredientsSection: View {
    let model: RecipeDetailModel
    let recipe: Recipe
    let onAddToList: () -> Void

    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ingredients")
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.checkedCount > 0 {
                    Button("Uncheck All") {
                        withAnimation(.smooth) { model.resetCooking() }
                    }
                    .font(.subheadline.weight(.medium))
                    .accessibilityHint("Clears the check marks.")
                }
            }

            ServingsStepper(model: model)

            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ForEach(RecipeSections.ingredients(recipe.ingredients)) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if let title = section.title {
                            Text(title)
                                .font(.headline)
                                .padding(.bottom, Theme.Spacing.xxs)
                                .accessibilityAddTraits(.isHeader)
                        }
                        ForEach(section.items) { entry in
                            IngredientRow(
                                ingredient: entry.item,
                                scale: model.scale,
                                isChecked: model.isChecked(entry.index),
                                isOnHand: entry.item.food?.isOnHand(householdSlug: session.currentUser?.householdSlug) ?? false,
                                onOpenRecipe: { router.push(.recipe(slug: $0.slug)) },
                                toggle: { withAnimation(.smooth) { model.toggleIngredient(entry.index) } }
                            )
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: model.checkedCount)

            Button(action: onAddToList) {
                Label("Add to Shopping List", systemImage: "cart.badge.plus")
            }
            .buttonStyle(.bordered)
            .tint(.primary)
            .padding(.top, Theme.Spacing.xxs)
        }
    }
}

/// "4 servings  [− +]", with a way back to the original amount when scaled.
struct ServingsStepper: View {
    let model: RecipeDetailModel

    var body: some View {
        let base = model.baseServings
        let servings = model.servings
        HStack(spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(base == nil ? multiplierText(servings) : RecipeFormatting.servings(servings) ?? "")
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: servings))
                if model.isScaled {
                    Button {
                        withAnimation(.smooth) { model.setServings(base ?? 1) }
                    } label: {
                        if let base {
                            Text("Recipe makes \(RecipeFormatting.servings(base) ?? "") · \(Text("Reset").foregroundStyle(.tint))")
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Reset to original").foregroundStyle(.tint)
                        }
                    }
                    .font(.footnote)
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Stepper {
                Text("Servings")
            } onIncrement: {
                withAnimation(.snappy) { model.setServings(step(servings, up: true, base: base)) }
            } onDecrement: {
                withAnimation(.snappy) { model.setServings(step(servings, up: false, base: base)) }
            }
            .labelsHidden() // The hidden "Servings" label still names it for VoiceOver.
            .accessibilityValue(base == nil ? multiplierText(servings) : RecipeFormatting.servings(servings) ?? "")
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.s)
        .background(.mealMateSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    private func multiplierText(_ value: Double) -> String {
        "×" + IngredientFormatting.quantity(value, useFractions: true)
    }

    /// Whole servings; ½ steps below 1 (and for multipliers).
    private func step(_ value: Double, up: Bool, base: Double?) -> Double {
        if value < 1 || (!up && value <= 1) {
            return up ? min(value + 0.5, 1) : max(value - 0.5, 0.5)
        }
        let next = up ? (value + 1).rounded(.down) : (value - 1).rounded(.up)
        return min(max(next, 1), 99)
    }
}

struct IngredientRow: View {
    let ingredient: RecipeIngredient
    let scale: Double
    let isChecked: Bool
    var isOnHand = false
    var font: Font = .body
    /// Opens the sub-recipe a line links to; `nil` hides the button (cook mode).
    var onOpenRecipe: ((RecipeSummary) -> Void)?
    let toggle: () -> Void

    var body: some View {
        let parts = IngredientFormatting.parts(for: ingredient, scale: scale)
        let substitutes = ingredient.substitutes.map(IngredientFormatting.substituteText)
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
            Button(action: toggle) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChecked ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        IngredientText(parts: parts, isChecked: isChecked, isOnHand: isOnHand)
                            .font(font)
                        ForEach(substitutes, id: \.self) { line in
                            Text(line)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 6)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(([parts.text + (isOnHand ? ", on hand" : "")] + substitutes).joined(separator: ", "))
            .accessibilityAddTraits(isChecked ? [.isSelected] : [])
            .accessibilityHint(isChecked ? "Marks as not done." : "Checks off this ingredient.")

            if let linked = ingredient.linkedRecipe, let onOpenRecipe {
                Button {
                    onOpenRecipe(linked)
                } label: {
                    Image(systemName: "arrow.forward.circle")
                        .font(font)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open \(linked.displayName)")
            }
        }
    }
}

/// **amount** food note, struck through and faded when checked.
struct IngredientText: View {
    let parts: IngredientDisplay
    var isChecked = false
    /// Appends a quiet "on hand" marker (the household has this food).
    var isOnHand = false

    var body: some View {
        text
            .strikethrough(isChecked, color: .secondary)
            .foregroundStyle(isChecked ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.leading)
    }

    private var text: Text {
        let amount = parts.amount.map { Text($0).fontWeight(.semibold) }
        let food = parts.food.map { Text($0) }
        let note = parts.note.map { Text($0).foregroundStyle(.secondary) }
        let pieces = [amount, food, note].compactMap { $0 }
        guard var result = pieces.first else { return Text(" ") }
        for piece in pieces.dropFirst() {
            result = Text("\(result) \(piece)")
        }
        if isOnHand {
            let marker = Text("\(Image(systemName: "house")) on hand")
                .font(.footnote)
                .foregroundStyle(.secondary)
            result = Text("\(result)  \(marker)")
        }
        return result
    }
}

// MARK: - Steps

struct StepsSection: View {
    let model: RecipeDetailModel
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Steps")
                .font(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            ForEach(RecipeSections.steps(recipe.instructions)) { section in
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let title = section.title {
                        Text(title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(section.items) { entry in
                        StepView(number: entry.index + 1, step: entry.item,
                                 ingredients: model.referencedIngredients(for: entry.item), scale: model.scale)
                    }
                }
            }
        }
    }
}

private struct StepView: View {
    let number: Int
    let step: RecipeStep
    let ingredients: [(index: Int, ingredient: RecipeIngredient)]
    let scale: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Step \(number)")
                    .font(.stepLabel)
                    .foregroundStyle(.secondary)
                if let summary = step.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                    Text("· \(summary)")
                        .font(.stepLabel)
                        .foregroundStyle(.secondary)
                }
            }
            Text(LocalizedStringKey(step.text.trimmingCharacters(in: .whitespacesAndNewlines)))
                .font(.body)
                .lineSpacing(Theme.LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !ingredients.isEmpty {
                ReferencedIngredients(ingredients: ingredients.map(\.ingredient), scale: scale)
                    .padding(.top, Theme.Spacing.xxs)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The ingredients a step uses, as a quiet list under the step text.
struct ReferencedIngredients: View {
    let ingredients: [RecipeIngredient]
    let scale: Double
    var font: Font = .subheadline

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            ForEach(Array(ingredients.enumerated()), id: \.offset) { _, ingredient in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(.tertiary)
                        .frame(width: 4, height: 4)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
                    IngredientText(parts: IngredientFormatting.parts(for: ingredient, scale: scale))
                        .font(font)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.mealMateSurfaceSecondary.opacity(0.6), in: .rect(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Uses: " + ingredients.map { IngredientFormatting.text(for: $0, scale: scale) }.joined(separator: ", "))
    }
}

// MARK: - Notes, nutrition, organizers, source

struct NotesSection: View {
    let notes: [RecipeNote]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Notes")
                .font(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    if !note.title.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(note.title).font(.headline)
                    }
                    Text(LocalizedStringKey(note.text))
                        .font(.body)
                        .lineSpacing(Theme.LineSpacing.body)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .surfaceCard()
            }
        }
    }
}

struct NutritionSection: View {
    let nutrition: Nutrition

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Nutrition")
                .font(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                let entries = nutrition.entries
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        Text(entry.label)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.value)
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, Theme.Spacing.xs)
                    .accessibilityElement(children: .combine)
                    if index < entries.count - 1 {
                        Divider()
                    }
                }
            }
            .surfaceCard(padding: Theme.Spacing.m)
            Text("Per serving, as entered in the recipe.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Files attached to the recipe (Mealie "assets": PDFs, photos, scans). Opened in the browser.
struct AttachmentsSection: View {
    let recipe: Recipe

    @Environment(\.mealie) private var mealie
    @Environment(\.openURL) private var openURL

    var body: some View {
        let assets = (recipe.assets ?? []).filter { $0.fileName?.isEmpty == false }
        if !assets.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Attachments")
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(assets.enumerated()), id: \.offset) { index, asset in
                        if let fileName = asset.fileName, let url = mealie.recipeAssetURL(recipeID: recipe.id, fileName: fileName) {
                            Button {
                                openURL(url)
                            } label: {
                                HStack(spacing: Theme.Spacing.s) {
                                    Image(systemName: asset.systemImage)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 24)
                                        .accessibilityHidden(true)
                                    Text(asset.name.isEmpty ? fileName : asset.name)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "arrow.up.right")
                                        .font(.footnote)
                                        .foregroundStyle(.tertiary)
                                        .accessibilityHidden(true)
                                }
                                .font(.subheadline)
                                .padding(.vertical, Theme.Spacing.s)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens the file in your browser.")
                            if index < assets.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
                .surfaceCard(padding: Theme.Spacing.m)
            }
        }
    }
}

struct OrganizersSection: View {
    let recipe: Recipe

    var body: some View {
        let groups: [(OrganizerKind, [Organizer])] = [
            (.category, recipe.categories), (.tag, recipe.tagList), (.tool, recipe.toolList),
        ].filter { !$0.1.isEmpty }
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text(title(groups.map(\.0)))
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                ChipFlowLayout(spacing: Theme.Spacing.xs) {
                    ForEach(groups, id: \.0) { kind, organizers in
                        ForEach(organizers, id: \.slug) { organizer in
                            NavigationLink(value: AppDestination.organizer(kind: kind, slug: organizer.slug)) {
                                TagChip(title: organizer.name, systemImage: kind.systemImage)
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(organizer.name), \(kind.singularTitle)")
                            .accessibilityHint("Shows recipes with this \(kind.singularTitle.lowercased()).")
                        }
                    }
                }
            }
        }
    }

    private func title(_ kinds: [OrganizerKind]) -> String {
        let names = kinds.map(\.title)
        switch names.count {
        case 1: return names[0]
        case 2: return "\(names[0]) & \(names[1])"
        default: return "Categories, Tags & Tools"
        }
    }
}

extension OrganizerKind {
    var singularTitle: String {
        switch self {
        case .category: "Category"
        case .tag: "Tag"
        case .tool: "Tool"
        }
    }
}

struct SourceLink: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "safari")
                Text("Original recipe on \(url.host(percentEncoded: false)?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString)")
                    .lineLimit(1)
                Image(systemName: "arrow.up.right")
                    .font(.footnote)
            }
            .font(.subheadline.weight(.medium))
        }
    }
}
