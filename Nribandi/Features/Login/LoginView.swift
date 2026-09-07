import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    #if DEBUG
    @State private var email = "admin@nribandi.local"
    @State private var password = "Nribandi@123"
    #else
    @State private var email = ""
    @State private var password = ""
    #endif
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showForgotPassword = false
    @State private var showResetPassword = false
    @State private var heroVisible = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        LogoView(style: .hero, animate: true)
                        Text("Property operations for Hyderabad rentals.")
                            .font(.body)
                            .foregroundStyle(NriTheme.slate)
                            .opacity(heroVisible ? 1 : 0)
                            .offset(y: heroVisible ? 0 : 8)
                    }
                    .padding(.top, 24)

                    if AppEnvironment.allowsEnvironmentSelection {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Environment").font(.subheadline.weight(.semibold))
                            Picker("Environment", selection: Binding(
                                get: { appState.environment },
                                set: { newValue in Task { await appState.switchEnvironment(newValue) } }
                            )) {
                                ForEach(AppEnvironment.allCases) { env in
                                    Text(env.displayName).tag(env)
                                }
                            }
                            .pickerStyle(.segmented)

                            HStack(spacing: 8) {
                                EnvBadge(env: appState.environment)
                                Text(appState.environment.apiBaseURL.absoluteString)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(NriTheme.slate)
                                    .lineLimit(1)
                            }
                        }
                    }

                    VStack(spacing: 14) {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.username)
                            .padding(14)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .padding(14)
                            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if let successMessage {
                        Text(successMessage).font(.footnote).foregroundStyle(NriTheme.leaf)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(NriTheme.terracotta)
                    }

                    Button(action: signIn) {
                        HStack {
                            if isLoading { ProgressView().tint(.white) }
                            Text(isLoading ? "Signing in…" : "Sign in").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(NriTheme.teal, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .disabled(isLoading)

                    HStack {
                        Button("Forgot password?") {
                            successMessage = nil
                            errorMessage = nil
                            showForgotPassword = true
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NriTheme.teal)

                        Spacer()

                        Button("Have a reset token?") {
                            successMessage = nil
                            errorMessage = nil
                            showResetPassword = true
                        }
                        .font(.subheadline)
                        .foregroundStyle(NriTheme.slate)
                    }

                    if AppEnvironment.allowsEnvironmentSelection {
                        Text("Local talks to Docker on this Mac at 127.0.0.1:8082. Set TEST/PROD URLs in Info.plist when AWS is ready.")
                            .font(.caption)
                            .foregroundStyle(NriTheme.slate)
                    }
                }
                .padding(24)
            }
            .nriScrollable()
            .background(NriTheme.pageBackground.ignoresSafeArea())
            .onAppear {
                withAnimation(.easeOut(duration: 0.65).delay(0.15)) {
                    heroVisible = true
                }
            }
            .sheet(isPresented: $showForgotPassword) {
                ForgotPasswordSheet { message in
                    successMessage = message
                    errorMessage = nil
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $showResetPassword) {
                ResetPasswordSheet { message in
                    successMessage = message
                    errorMessage = nil
                }
                .environmentObject(appState)
            }
        }
    }

    private func signIn() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedEmail.isEmpty {
            errorMessage = "Email is required."
            return
        }
        if !trimmedEmail.contains("@") {
            errorMessage = "Enter a valid email address."
            return
        }
        if password.isEmpty {
            errorMessage = "Password is required."
            return
        }
        errorMessage = nil
        successMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let auth = try await appState.api.login(
                    email: trimmedEmail,
                    password: password
                )
                session.apply(auth)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ForgotPasswordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var onSuccess: (String) -> Void

    @State private var email = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                } footer: {
                    Text("We'll email reset instructions if an account exists for that address.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Forgot password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Sending…" : "Send") { Task { await submit() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func submit() async {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@") else {
            errorMessage = "Enter a valid email address."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let message = try await appState.api.forgotPassword(email: trimmed)
            onSuccess(message)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ResetPasswordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var onSuccess: (String) -> Void

    @State private var token = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Reset token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("New password (min 8)", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                } footer: {
                    Text("Paste the one-time token from your reset email, then choose a new password.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Reset") { Task { await submit() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func submit() async {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            errorMessage = "Reset token is required."
            return
        }
        guard newPassword.count >= 8 else {
            errorMessage = "Password must be at least 8 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "Passwords do not match."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let message = try await appState.api.resetPassword(token: trimmedToken, newPassword: newPassword)
            onSuccess(message)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
