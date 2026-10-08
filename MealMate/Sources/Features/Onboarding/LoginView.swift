import SwiftUI

/// Step 2: choose how to sign in. OIDC is primary when the server offers it.
struct LoginView: View {
    @Environment(AppSession.self) private var session
    @Environment(AppRouter.self) private var router
    @State private var model: LoginViewModel
    @State private var showsPasswordForm: Bool
    @State private var showsTokenSheet = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    init(server: ResolvedServer) {
        _model = State(initialValue: LoginViewModel(server: server))
        // Without OIDC, the password form is the primary method and starts open.
        _showsPasswordForm = State(initialValue: !server.info.isOIDCEnabled && server.info.isPasswordLoginAllowed)
    }

    private var info: AppInfo { model.server.info }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                VStack(spacing: 12) {
                    if info.isOIDCEnabled {
                        oidcButton
                    }
                    if info.isPasswordLoginAllowed {
                        if showsPasswordForm {
                            passwordForm
                        } else {
                            secondaryButton("Sign in with Password", systemImage: "person.badge.key") {
                                withAnimation(.smooth) { showsPasswordForm = true }
                                focusedField = .username
                            }
                        }
                    }
                    secondaryButton("Sign in with API Token", systemImage: "key") {
                        showsTokenSheet = true
                    }
                }
                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.server.isInsecure {
                    Label("This server uses an unencrypted connection (http). That’s fine on your home network or a VPN.", systemImage: "lock.open")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsTokenSheet) {
            APITokenSheet(model: model)
        }
        .task {
            guard router.autoStartOIDC, info.isOIDCEnabled else { return }
            router.autoStartOIDC = false
            try? await Task.sleep(for: .seconds(0.5))
            await model.signInWithOIDC(session: session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign In")
                .font(.largeTitle.bold())
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.tint)
                Text(model.server.displayAddress)
                    .fontWeight(.medium)
                Text("· Mealie \(info.displayVersion)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }

    private var oidcButton: some View {
        Button {
            Task { await model.signInWithOIDC(session: session) }
        } label: {
            HStack(spacing: 8) {
                if model.inProgress == .oidc {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                }
                Text(info.oidcButtonTitle)
            }
            .frame(maxWidth: .infinity)
        }
        .primaryActionStyle()
        .controlSize(.large)
        .disabled(model.isBusy)
    }

    private var passwordForm: some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                TextField("Username or email", text: $model.username)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .password }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                Divider().padding(.leading, 16)
                SecureField("Password", text: $model.password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit(submitPassword)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
            .background(.mealMateSurface, in: .rect(cornerRadius: Theme.Radius.card, style: .continuous))

            let isPrimary = !info.isOIDCEnabled
            Button(action: submitPassword) {
                HStack(spacing: 8) {
                    if model.inProgress == .password { ProgressView().controlSize(.small) }
                    Text("Sign In")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(isPrimary ? AnyPrimitiveButtonStyle(.glassProminent) : AnyPrimitiveButtonStyle(.glass))
            .tint(isPrimary ? Color.mealMateProminent : nil)
            .controlSize(.large)
            .disabled(!model.canSubmitPassword)
        }
    }

    private func secondaryButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .disabled(model.isBusy)
    }

    private func submitPassword() {
        guard model.canSubmitPassword else { return }
        focusedField = nil
        Task { await model.signInWithPassword(session: session) }
    }
}

/// Type-erased primitive button style so the form can switch between glass styles.
private struct AnyPrimitiveButtonStyle: PrimitiveButtonStyle {
    private let make: (Configuration) -> AnyView

    init(_ style: some PrimitiveButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

/// Paste an API token created in Mealie (Profile → API Tokens).
private struct APITokenSheet: View {
    @Bindable var model: LoginViewModel
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Paste token", text: $model.apiToken, axis: .vertical)
                        .lineLimit(3...6)
                        .font(.body.monospaced())
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isFocused)
                } footer: {
                    Text("In Mealie, open your profile, choose **API Tokens** and create a token for MealMate. The token is stored in your device’s Keychain.")
                }
                if let error = model.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .screenBackground()
            .navigationTitle("API Token")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if model.inProgress == .token {
                        ProgressView()
                    } else {
                        Button("Sign In", systemImage: "checkmark") {
                            Task { await model.signInWithToken(session: session) }
                        }
                        .disabled(!model.canSubmitToken)
                    }
                }
            }
            .onAppear {
                model.errorMessage = nil
                isFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }
}
