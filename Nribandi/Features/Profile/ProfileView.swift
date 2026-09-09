import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var showChangePassword = false
    @State private var passwordMessage: String?

    private var role: UserRole? { session.user?.role }

    var body: some View {
        NavigationStack {
            List {
                if let user = session.user {
                    Section("Signed in") {
                        LabeledContent("Name", value: user.fullName)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.title)
                        if let phone = user.phone { LabeledContent("Phone", value: phone) }
                    }
                }

                Section("Security") {
                    Button("Change password") {
                        passwordMessage = nil
                        showChangePassword = true
                    }
                    if let passwordMessage {
                        Text(passwordMessage)
                            .font(.footnote)
                            .foregroundStyle(NriTheme.leaf)
                    }
                }

                // Keep Sign out above optional/long sections so it stays on-screen
                // on Mac and iPhone without scrolling past Ops + environment controls.
                Section {
                    Button(role: .destructive) {
                        Task { await session.logout() }
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityIdentifier("profile.signOut")
                }

                if role == .TENANT {
                    Section("Verification") {
                        NavigationLink("My KYC") {
                            TenantVerificationView()
                        }
                    }
                }

                if role == .ADMIN || role == .EMPLOYEE {
                    Section("Ops shortcuts") {
                        NavigationLink("KYC review") {
                            KycReviewListView(embedsInParentNavigation: true)
                        }
                        NavigationLink("Inspections") {
                            InspectionsView(embedsInParentNavigation: true)
                        }
                        NavigationLink("Invoices") {
                            InvoicesView(embedsInParentNavigation: true)
                        }
                    }
                }

                if role == .ADMIN {
                    Section("Company settings") {
                        NavigationLink("Payment IDs (UPI / GPay / PhonePe)") {
                            CompanyPaymentAccountsAdminView()
                        }
                    }
                }

                // Visible to every signed-in role so payers know where to send money.
                Section {
                    NavigationLink("How to pay (company UPI)") {
                        List {
                            CompanyPaymentInstructionsSection()
                        }
                        .listStyle(.insetGrouped)
                        .navigationTitle("How to pay")
                        .navigationBarTitleDisplayMode(.inline)
                    }
                } header: {
                    Text("Payments")
                } footer: {
                    Text("No payment gateway — use the company UPI / GPay / PhonePe IDs shown here.")
                }

                if AppEnvironment.allowsEnvironmentSelection {
                    Section("API") {
                        Picker("Environment", selection: Binding(
                            get: { appState.environment == .test ? .prod : appState.environment },
                            set: { newValue in Task { await appState.switchEnvironment(newValue) } }
                        )) {
                            ForEach(AppEnvironment.selectableCases) { env in
                                Text(env.displayName).tag(env)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Section("App") {
                    LabeledContent("Version", value: AppBuildInfo.versionAndBuild)
                    if !AppEnvironment.allowsEnvironmentSelection {
                        LabeledContent("Environment", value: "Prod")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .nriScrollable()
            .nriPhoneScrollInsets()
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if AppEnvironment.allowsEnvironmentSelection {
                            EnvBadge(env: appState.environment)
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await session.logout() }
                        }
                        .accessibilityIdentifier("profile.toolbar.signOut")
                    }
                }
            }
            .sheet(isPresented: $showChangePassword) {
                ChangePasswordSheet { message in
                    passwordMessage = message
                }
                .environmentObject(appState)
            }
        }
    }
}

private struct ChangePasswordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var onSuccess: (String) -> Void

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current password", text: $currentPassword)
                        .textContentType(.password)
                    SecureField("New password (min 8)", text: $newPassword)
                        .textContentType(.newPassword)
                    SecureField("Confirm new password", text: $confirmPassword)
                        .textContentType(.newPassword)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Change password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") { Task { await submit() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func submit() async {
        guard !currentPassword.isEmpty else {
            errorMessage = "Current password is required."
            return
        }
        guard newPassword.count >= 8 else {
            errorMessage = "New password must be at least 8 characters."
            return
        }
        guard newPassword == confirmPassword else {
            errorMessage = "New passwords do not match."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let message = try await appState.api.changePassword(
                currentPassword: currentPassword,
                newPassword: newPassword
            )
            onSuccess(message.isEmpty ? "Password updated." : message)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
