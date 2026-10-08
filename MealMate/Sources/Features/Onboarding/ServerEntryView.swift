import SwiftUI

/// Step 1: "Where is your Mealie?"
struct ServerEntryView: View {
    @Bindable var model: ServerEntryViewModel
    @Environment(AppSession.self) private var session
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header
                VStack(alignment: .leading, spacing: 12) {
                    addressField
                    if let message = session.signedOutReason, model.errorMessage == nil {
                        Label(message, systemImage: "info.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                continueButton
                Text("MealMate connects to your own Mealie server. Enter the address you use in the browser, for example **mealie.example.com** or **192.168.1.20:9000**.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 48)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome to MealMate")
                .font(.largeTitle.bold())
            Text("Your recipes, meal plan and shopping list from Mealie, right on your iPhone.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server address")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            TextField("mealie.example.com", text: $model.address)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .focused($isFieldFocused)
                .onSubmit(submit)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(.mealMateSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel("Server address")
        }
    }

    private var continueButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if model.isChecking {
                    ProgressView().controlSize(.small)
                }
                Text(model.isChecking ? "Connecting…" : "Continue")
            }
            .frame(maxWidth: .infinity)
        }
        .primaryActionStyle()
        .controlSize(.large)
        .disabled(!model.canContinue)
    }

    private func submit() {
        guard model.canContinue else { return }
        isFieldFocused = false
        Task { await model.resolve() }
    }
}
