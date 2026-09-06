import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var email = "admin@nribandi.local"
    @State private var password = "Nribandi@123"
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NRIBANDI")
                            .font(.system(size: 34, weight: .bold, design: .serif))
                            .foregroundStyle(NriTheme.ink)
                        Text("Property operations for Hyderabad rentals.")
                            .font(.body)
                            .foregroundStyle(NriTheme.slate)
                    }
                    .padding(.top, 24)

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

                    Text("Local talks to Docker on this Mac at 127.0.0.1:8082. Set TEST/PROD URLs in Info.plist when AWS is ready.")
                        .font(.caption)
                        .foregroundStyle(NriTheme.slate)
                }
                .padding(24)
            }
            .background(
                LinearGradient(colors: [NriTheme.sand, NriTheme.mist], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
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
