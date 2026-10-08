import SwiftUI

// MARK: - Comments (inline preview)

struct CommentsSection: View {
    let model: RecipeDetailModel
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("Comments")
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(model.comments.isEmpty ? "Add" : "Show All", action: onShowAll)
                    .font(.subheadline.weight(.medium))
            }
            if model.comments.isEmpty {
                Text("No comments yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    ForEach(model.comments.prefix(2)) { comment in
                        CommentView(comment: comment)
                    }
                }
                .surfaceCard()
                .onTapGesture(perform: onShowAll)
                if model.comments.count > 2 {
                    Button("Show all \(model.comments.count) comments", action: onShowAll)
                        .font(.subheadline)
                }
            }
        }
    }
}

struct CommentView: View {
    let comment: RecipeComment

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(comment.user?.displayName ?? "Someone")
                    .font(.subheadline.weight(.semibold))
                if let date = comment.createdAt {
                    Text(date, format: .relative(presentation: .named))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Text(comment.text)
                .font(.body)
                .lineSpacing(Theme.LineSpacing.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Comments sheet

struct RecipeCommentsSheet: View {
    let model: RecipeDetailModel

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var sentCount = 0
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if model.comments.isEmpty {
                    ContentUnavailableView("No Comments Yet", systemImage: "text.bubble",
                                           description: Text("Share a tip or how it turned out."))
                } else {
                    List {
                        ForEach(model.comments) { comment in
                            CommentView(comment: comment)
                                .padding(.vertical, Theme.Spacing.xxs)
                                .swipeActions {
                                    if isOwn(comment) {
                                        Button(role: .destructive) {
                                            delete(comment)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                                .contextMenu {
                                    Button {
                                        UIPasteboard.general.string = comment.text
                                    } label: {
                                        Label("Copy", systemImage: "doc.on.doc")
                                    }
                                    if isOwn(comment) {
                                        Button(role: .destructive) {
                                            delete(comment)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await model.loadComments() }
                }
            }
            .screenBackground()
            .safeAreaInset(edge: .bottom) { composer }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
            .task { await model.loadComments() }
            .sensoryFeedback(.success, trigger: sentCount)
            .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        }
        .presentationDragIndicator(.visible)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, Theme.Spacing.xs)
            }
            HStack(alignment: .bottom, spacing: Theme.Spacing.xs) {
                TextField("Add a comment", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($isComposerFocused)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                Button {
                    send()
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.body.weight(.semibold))
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .primaryActionStyle()
                .buttonBorderShape(.circle)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                .accessibilityLabel("Post Comment")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func isOwn(_ comment: RecipeComment) -> Bool {
        guard let userID = session.currentUser?.id else { return false }
        return comment.userId == userID || comment.user?.id == userID
    }

    private func send() {
        let text = draft
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                try await model.addComment(text)
                draft = ""
                sentCount += 1
            } catch {
                errorMessage = "Couldn’t post your comment. \((error as? MealieError)?.errorDescription ?? "")"
            }
        }
    }

    private func delete(_ comment: RecipeComment) {
        Task {
            do {
                try await model.deleteComment(comment)
            } catch {
                errorMessage = "Couldn’t delete the comment."
            }
        }
    }
}

// MARK: - History (timeline)

struct HistorySection: View {
    let model: RecipeDetailModel
    let onMadeIt: () -> Void
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if model.timeline.count > 3 {
                    Button("Show All", action: onShowAll)
                        .font(.subheadline.weight(.medium))
                }
            }

            if let lastMade = model.recipe?.lastMade {
                Label {
                    Text("Last made \(lastMade.formatted(.relative(presentation: .named)))")
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            if !model.timeline.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(model.timeline.prefix(3)) { event in
                        TimelineEventView(event: event, recipeID: model.recipe?.id ?? "")
                    }
                }
                .surfaceCard()
                .onTapGesture(perform: onShowAll)
            } else if model.hasLoadedTimeline, model.recipe?.lastMade == nil {
                Text("You haven’t made this yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button(action: onMadeIt) {
                Label("I Made This", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .tint(.primary)
        }
    }
}

struct TimelineEventView: View {
    let event: TimelineEvent
    let recipeID: String

    @Environment(\.mealie) private var mealie

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.s) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.subject)
                    .font(.subheadline.weight(.medium))
                if let message = event.eventMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let date = event.timestamp {
                    Text(date, format: .dateTime.day().month(.abbreviated).year())
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if event.hasImage, let url = mealie.timelineImageURL(recipeID: recipeID, eventID: event.id, size: .tiny) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    RecipeImagePlaceholder(seed: event.id, showsGlyph: false)
                }
                .frame(width: 48, height: 48)
                .recipeImageShape(cornerRadius: Theme.Radius.thumbnail)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch event.eventType {
        case .system: "gearshape"
        case .comment: "checkmark.seal"
        default: "info.circle"
        }
    }
}

struct RecipeTimelineSheet: View {
    let model: RecipeDetailModel

    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if model.timeline.isEmpty {
                    ContentUnavailableView("No History Yet", systemImage: "clock.arrow.circlepath",
                                           description: Text("Tap “I Made This” after cooking to keep track."))
                } else {
                    List {
                        if let errorMessage {
                            Text(errorMessage).font(.footnote).foregroundStyle(.red)
                        }
                        ForEach(model.timeline) { event in
                            TimelineEventView(event: event, recipeID: model.recipe?.id ?? "")
                                .swipeActions {
                                    if event.userId == session.currentUser?.id, event.eventType != .system {
                                        Button(role: .destructive) {
                                            Task {
                                                do { try await model.deleteTimelineEvent(event) } catch {
                                                    errorMessage = "Couldn’t delete the entry."
                                                }
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await model.loadTimeline() }
                }
            }
            .screenBackground()
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

// MARK: - I made this

/// Confirms "I made this" with a date and an optional note, then saves.
struct MadeItSheet: View {
    let recipeName: String
    let save: (Date, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("How did it turn out? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    } else {
                        Text("Updates “last made” and adds an entry to the recipe’s history.")
                    }
                }
            }
            .screenBackground()
            .navigationTitle("I Made This")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save", systemImage: "checkmark") { submit() }
                            .primaryActionStyle()
                    }
                }
            }
            .sensoryFeedback(.error, trigger: errorMessage) { _, new in new != nil }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSaving)
    }

    private func submit() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await save(date, note)
                dismiss()
            } catch {
                errorMessage = "Couldn’t save. \((error as? MealieError)?.errorDescription ?? "Please try again.")"
                isSaving = false
            }
        }
    }
}
