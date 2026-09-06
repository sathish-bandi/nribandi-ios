import SwiftUI

struct ServiceRequestsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var items: [ServiceRequestItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false

    private var canRaise: Bool {
        let role = session.user?.role
        return role == .OWNER || role == .TENANT
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading requests…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView(
                        "Could not load",
                        systemImage: "wrench.and.screwdriver",
                        description: Text(errorMessage)
                    )
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("No service requests", systemImage: "checkmark.seal")
                    } description: {
                        Text(
                            canRaise
                                ? "Raise a repair or maintenance ticket for your property or unit."
                                : "Open repairs and tickets will show here."
                        )
                    } actions: {
                        if canRaise {
                            Button("Raise request") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    List(items) { item in
                        NavigationLink(value: item) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(NriTheme.slate)
                                        .lineLimit(2)
                                }
                                HStack {
                                    StatusChip(text: item.category)
                                    StatusChip(text: item.priority)
                                    StatusChip(text: item.status)
                                }
                                if let name = item.assignedEmployeeName {
                                    Text("Assigned: \(name)")
                                        .font(.caption)
                                        .foregroundStyle(NriTheme.slate)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Service requests")
            .navigationDestination(for: ServiceRequestItem.self) { item in
                ServiceRequestDetailView(requestId: item.id)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if canRaise {
                            Button {
                                showCreate = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .accessibilityLabel("Raise request")
                        }
                        EnvBadge(env: appState.environment)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateServiceRequestView {
                    showCreate = false
                    await load()
                }
                .environmentObject(appState)
                .environmentObject(session)
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await appState.api.serviceRequests().content
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateServiceRequestView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () async -> Void

    @State private var properties: [PropertyItem] = []
    @State private var units: [UnitItem] = []
    @State private var tenancies: [TenancyItem] = []
    @State private var selectedPropertyId: UUID?
    @State private var selectedUnitId: UUID?
    @State private var selectedTenancyId: UUID?
    @State private var category = "PLUMBING"
    @State private var priority = "MEDIUM"
    @State private var titleText = ""
    @State private var descriptionText = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isBootstrapping = true

    private let categories = ["PLUMBING", "ELECTRICAL", "CARPENTRY", "CLEANING", "AC", "PAINTING", "WATER", "OTHER"]
    private let priorities = ["LOW", "MEDIUM", "HIGH", "URGENT"]

    private var isTenant: Bool { session.user?.role == .TENANT }

    var body: some View {
        NavigationStack {
            Form {
                if isBootstrapping {
                    ProgressView("Loading…")
                } else if isTenant {
                    Section("Your unit") {
                        if tenancies.isEmpty {
                            Text("No active tenancy found. Ask your owner/admin to assign a unit.")
                                .foregroundStyle(NriTheme.terracotta)
                        } else {
                            Picker("Tenancy", selection: $selectedTenancyId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(tenancies) { tenancy in
                                    Text(tenancy.label).tag(Optional(tenancy.id))
                                }
                            }
                        }
                    }
                } else {
                    Section("Property") {
                        Picker("Property", selection: $selectedPropertyId) {
                            Text("Select").tag(Optional<UUID>.none)
                            ForEach(properties) { property in
                                Text(property.name).tag(Optional(property.id))
                            }
                        }
                        .onChange(of: selectedPropertyId) { _, newValue in
                            Task { await loadUnits(for: newValue) }
                        }
                        Picker("Unit (optional)", selection: $selectedUnitId) {
                            Text("Whole property / not specific").tag(Optional<UUID>.none)
                            ForEach(units) { unit in
                                Text(unit.title).tag(Optional(unit.id))
                            }
                        }
                    }
                }

                Section("Request") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(value.replacingOccurrences(of: "_", with: " ")).tag(value)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Title", text: $titleText)
                    TextField("Describe the issue", text: $descriptionText, axis: .vertical)
                        .lineLimit(4...8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                    }
                }
            }
            .navigationTitle("Raise request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(isSaving || !canSubmit)
                }
            }
            .task { await bootstrap() }
        }
    }

    private var canSubmit: Bool {
        guard !titleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        if isTenant { return selectedTenancyId != nil }
        return selectedPropertyId != nil
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            if isTenant {
                tenancies = try await appState.api.myTenancies().filter(\.active)
                selectedTenancyId = tenancies.first?.id
            } else {
                properties = try await appState.api.properties().content
                selectedPropertyId = properties.first?.id
                await loadUnits(for: selectedPropertyId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadUnits(for propertyId: UUID?) async {
        selectedUnitId = nil
        units = []
        guard let propertyId else { return }
        do {
            units = try await appState.api.units(propertyId: propertyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let propertyId: UUID
        let unitId: UUID?
        if isTenant {
            guard let tenancy = tenancies.first(where: { $0.id == selectedTenancyId }) else {
                errorMessage = "Select your unit."
                return
            }
            propertyId = tenancy.propertyId
            unitId = tenancy.unitId
        } else {
            guard let selectedPropertyId else {
                errorMessage = "Select a property."
                return
            }
            propertyId = selectedPropertyId
            unitId = selectedUnitId
        }

        let body = CreateServiceRequestBody(
            propertyId: propertyId,
            unitId: unitId,
            category: category,
            title: titleText.trimmingCharacters(in: .whitespacesAndNewlines),
            description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
            priority: priority
        )

        do {
            _ = try await appState.api.createServiceRequest(body)
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ServiceRequestDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    let requestId: UUID

    @State private var item: ServiceRequestItem?
    @State private var history: [ServiceRequestHistoryItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isCancelling = false
    @State private var showCancelConfirm = false

    private var canCancel: Bool {
        guard let item, item.canCancel else { return false }
        let role = session.user?.role
        return role == .OWNER || role == .TENANT
    }

    var body: some View {
        Group {
            if isLoading && item == nil {
                ProgressView("Loading…")
            } else if let errorMessage, item == nil {
                ContentUnavailableView(
                    "Could not load",
                    systemImage: "wrench.and.screwdriver",
                    description: Text(errorMessage)
                )
            } else if let item {
                List {
                    Section("Request") {
                        LabeledContent("Title", value: item.title)
                        if let description = item.description, !description.isEmpty {
                            Text(description)
                        }
                        LabeledContent("Category", value: item.category)
                        LabeledContent("Priority", value: item.priority)
                        LabeledContent("Status", value: item.status)
                        if let name = item.assignedEmployeeName {
                            LabeledContent("Assigned", value: name)
                        }
                        if let raised = item.raisedByName {
                            LabeledContent("Raised by", value: raised)
                        }
                    }

                    if !history.isEmpty {
                        Section("Status history") {
                            ForEach(history) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(event.oldStatus ?? "—") → \(event.newStatus)")
                                        .font(.subheadline.weight(.semibold))
                                    if let comments = event.comments, !comments.isEmpty {
                                        Text(comments).font(.footnote).foregroundStyle(NriTheme.slate)
                                    }
                                    HStack {
                                        if let name = event.changedByName {
                                            Text(name)
                                        }
                                        Spacer()
                                        if let timestamp = event.timestamp {
                                            Text(timestamp).font(.caption2)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(NriTheme.slate)
                                }
                            }
                        }
                    }

                    if canCancel {
                        Section {
                            Button("Cancel request", role: .destructive) {
                                showCancelConfirm = true
                            }
                            .disabled(isCancelling)
                        } footer: {
                            Text("You can cancel while the request is still open or in progress.")
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                        }
                    }
                }
            }
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Cancel this service request?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel request", role: .destructive) {
                Task { await cancel() }
            }
            Button("Keep request", role: .cancel) {}
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let detail = appState.api.serviceRequest(id: requestId)
            async let events = appState.api.serviceRequestHistory(id: requestId)
            item = try await detail
            history = try await events
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() async {
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }
        do {
            item = try await appState.api.cancelServiceRequest(id: requestId)
            history = try await appState.api.serviceRequestHistory(id: requestId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
