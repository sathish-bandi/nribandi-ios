import SwiftUI

struct PeopleView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    private var isAdmin: Bool { session.user?.role == .ADMIN }

    var body: some View {
        NavigationStack {
            Group {
                if isAdmin {
                    List {
                        NavigationLink("Owners") {
                            UserListView(role: .OWNER, title: "Owners")
                        }
                        NavigationLink("Tenants") {
                            UserListView(role: .TENANT, title: "Tenants")
                        }
                        NavigationLink("Employees") {
                            UserListView(role: .EMPLOYEE, title: "Employees")
                        }
                    }
                } else {
                    UserListView(role: .TENANT, title: "Tenants")
                }
            }
            .navigationTitle(isAdmin ? "People" : "Tenants")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EnvBadge(env: appState.environment)
                }
            }
        }
    }
}

struct UserListView: View {
    @EnvironmentObject private var appState: AppState

    let role: UserRole
    let title: String

    @State private var items: [ManagedUserItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading \(title.lowercased())…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView("Could not load", systemImage: "person.2", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No \(title.lowercased())",
                    systemImage: "person.2",
                    description: Text("Tap + to add one.")
                )
            } else {
                List(items) { user in
                    NavigationLink(value: user) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(user.fullName).font(.headline)
                                if !user.active {
                                    StatusChip(text: "INACTIVE")
                                }
                            }
                            Text(user.email).font(.subheadline).foregroundStyle(NriTheme.slate)
                            if let phone = user.phone, !phone.isEmpty {
                                Text(phone).font(.footnote.monospaced()).foregroundStyle(NriTheme.slate)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
                    .nriScrollable()
                    .nriPhoneScrollInsets()
                .navigationDestination(for: ManagedUserItem.self) { user in
                    UserDetailView(user: user, onChanged: { await load() })
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            UserFormView(mode: .create(role: role)) { await load() }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await appState.api.users(role: role.rawValue).content
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct UserDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    let user: ManagedUserItem
    let onChanged: () async -> Void

    @State private var current: ManagedUserItem
    @State private var showEdit = false
    @State private var errorMessage: String?
    @State private var isWorking = false

    init(user: ManagedUserItem, onChanged: @escaping () async -> Void) {
        self.user = user
        self.onChanged = onChanged
        _current = State(initialValue: user)
    }

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Name", value: current.fullName)
                LabeledContent("Email", value: current.email)
                LabeledContent("Phone", value: current.phone ?? "—")
                LabeledContent("Role", value: current.role.title)
                LabeledContent("Status", value: current.active ? "Active" : "Inactive")
            }
            if current.role == .TENANT {
                Section("KYC") {
                    NavigationLink("Open tenant verification") {
                        TenantVerificationView(
                            tenantUserId: current.id,
                            tenantName: current.fullName,
                            reviewMode: session.user?.role == .ADMIN || session.user?.role == .EMPLOYEE
                        )
                    }
                    Text("Tenants complete KYC (ID + permanent address) from Profile → My KYC. Staff can review from here or Ops.")
                        .font(.footnote)
                        .foregroundStyle(NriTheme.slate)
                }
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                }
            }
            Section {
                Button("Edit details") { showEdit = true }
                if current.active {
                    Button("Deactivate account", role: .destructive) {
                        Task { await deactivate() }
                    }
                    .disabled(isWorking)
                } else {
                    Button("Reactivate account") {
                        Task { await reactivate() }
                    }
                    .disabled(isWorking)
                }
            }
        }
        .navigationTitle(current.fullName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showEdit) {
            UserFormView(mode: .edit(current)) {
                await reload()
                await onChanged()
            }
        }
    }

    private func deactivate() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            current = try await appState.api.deactivateUser(id: current.id)
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reactivate() async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            current = try await appState.api.updateUser(id: current.id, UpdateUserBody(active: true))
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reload() async {
        do {
            let page = try await appState.api.users(role: current.role.rawValue, size: 100)
            if let refreshed = page.content.first(where: { $0.id == current.id }) {
                current = refreshed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

enum UserFormMode {
    case create(role: UserRole)
    case edit(ManagedUserItem)

    var title: String {
        switch self {
        case .create(let role): return "Add \(role.title)"
        case .edit: return "Edit person"
        }
    }
}

struct UserFormView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: UserFormMode
    let onSaved: () async -> Void

    @State private var fullName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Full name", text: $fullName)
                        .textContentType(.name)
                    if case .create = mode {
                        TextField("Email", text: $email)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                        SecureField("Temporary password (min 8 characters)", text: $password)
                            .textContentType(.newPassword)
                    }
                    TextField("Phone (10–15 digits)", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                } header: {
                    Text("Details")
                } footer: {
                    Text(footerHelp)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(NriTheme.terracotta)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear(perform: prefill)
        }
    }

    private var footerHelp: String {
        switch mode {
        case .create(let role):
            if role == .TENANT {
                return "Creates a tenant login. After signup, the tenant completes KYC (identity docs + permanent address) from Profile → My KYC. Phone is optional but must be 10–15 digits if provided."
            }
            return "Creates a \(role.title.lowercased()) login. Phone is optional but must be 10–15 digits if provided. Share the temporary password securely."
        case .edit(let user):
            if user.role == .TENANT {
                return "Phone is optional. Tenant KYC (Aadhaar / ID proofs) is managed from Profile → My KYC or tenant verification, not this form."
            }
            return "Phone is optional. If entered, use 10–15 digits (optional + country code)."
        }
    }

    private func prefill() {
        if case .edit(let user) = mode {
            fullName = user.fullName
            email = user.email
            phone = user.phone ?? ""
        }
    }

    private func validate() -> String? {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Full name is required." }
        if name.count > 150 { return "Full name must be at most 150 characters." }

        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPhone.isEmpty {
            let phonePattern = #"^\+?[0-9]{10,15}$"#
            if trimmedPhone.range(of: phonePattern, options: .regularExpression) == nil {
                return "Phone must be 10–15 digits (optional + country code). Example: 9876543210"
            }
        }

        if case .create = mode {
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedEmail.isEmpty { return "Email is required." }
            if trimmedEmail.count > 255 { return "Email must be at most 255 characters." }
            if !trimmedEmail.contains("@") || !trimmedEmail.contains(".") {
                return "Enter a valid email address (example: owner@example.com)."
            }
            if password.count < 8 {
                return "Password must be at least 8 characters."
            }
            if password.count > 100 {
                return "Password must be at most 100 characters."
            }
        }
        return nil
    }

    private func save() async {
        if let validation = validate() {
            errorMessage = validation
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            switch mode {
            case .create(let role):
                _ = try await appState.api.createUser(
                    CreateUserBody(
                        email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                        phone: trimmedPhone.isEmpty ? nil : trimmedPhone,
                        fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                        password: password,
                        role: role.rawValue
                    )
                )
            case .edit(let user):
                _ = try await appState.api.updateUser(
                    id: user.id,
                    UpdateUserBody(
                        fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                        phone: trimmedPhone.isEmpty ? nil : trimmedPhone
                    )
                )
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}