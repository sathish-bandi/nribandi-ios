import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

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

                if AppEnvironment.allowsEnvironmentSelection {
                    Section("API environment") {
                        Picker("Environment", selection: Binding(
                            get: { appState.environment },
                            set: { newValue in Task { await appState.switchEnvironment(newValue) } }
                        )) {
                            ForEach(AppEnvironment.allCases) { env in
                                Text(env.displayName).tag(env)
                            }
                        }
                        LabeledContent("Backend profile", value: appState.environment.backendProfile)
                        Text(appState.environment.apiBaseURL.absoluteString)
                            .font(.caption.monospaced())
                            .foregroundStyle(NriTheme.slate)
                    }
                }
            }
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
        }
    }
}
