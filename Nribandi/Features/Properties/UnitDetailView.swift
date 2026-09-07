import SwiftUI

struct UnitDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var unit: UnitItem
    let propertyName: String

    @State private var tenancies: [TenancyItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showAssignTenancy = false
    @State private var showUpdateStatus = false
    @State private var showEditDefinition = false
    @State private var endingTenancyId: UUID?
    @State private var moveOutDate = Date()

    init(unit: UnitItem, propertyName: String) {
        _unit = State(initialValue: unit)
        self.propertyName = propertyName
    }

    private var canUpdateStatus: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .OWNER || role == .EMPLOYEE
    }

    private var canManageTenancy: Bool {
        session.user?.role == .ADMIN || session.user?.role == .OWNER
    }

    private var canEditDefinition: Bool {
        session.user?.role == .ADMIN
    }

    private var activeTenancy: TenancyItem? {
        tenancies.first(where: \.active)
    }

    var body: some View {
        List {
            Section("Unit") {
                LabeledContent("Property", value: propertyName)
                LabeledContent("Unit", value: unit.unitNumber)
                if let block = unit.blockNumber {
                    LabeledContent("Block", value: block)
                }
                if let floor = unit.floorNumber {
                    LabeledContent("Floor", value: "\(floor)")
                }
                StatusChip(text: UnitTypeDisplay.title(for: unit.unitType), emphasized: true)
                HStack {
                    StatusChip(text: unit.occupancyStatus)
                    StatusChip(text: unit.toLetBoardStatus)
                }
            }

            Section("Tenancies") {
                if isLoading {
                    ProgressView()
                } else if tenancies.isEmpty {
                    Text("No tenancies yet.")
                        .foregroundStyle(NriTheme.slate)
                } else {
                    ForEach(tenancies) { tenancy in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tenancy.tenantName ?? "Tenant")
                                .font(.subheadline.weight(.semibold))
                            Text("In: \(tenancy.moveInDate ?? "—") · Out: \(tenancy.moveOutDate ?? "—")")
                                .font(.footnote)
                                .foregroundStyle(NriTheme.slate)
                            StatusChip(text: tenancy.active ? "ACTIVE" : "ENDED")
                            if canManageTenancy, tenancy.active {
                                Button("End tenancy") {
                                    endingTenancyId = tenancy.id
                                    moveOutDate = Date()
                                }
                                .foregroundStyle(NriTheme.terracotta)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if canManageTenancy {
                Section {
                    Button("Assign tenant") { showAssignTenancy = true }
                        .disabled(activeTenancy != nil)
                } footer: {
                    if activeTenancy != nil {
                        Text("End the active tenancy before assigning another tenant.")
                    }
                }
            }

            if canEditDefinition {
                Section {
                    Button("Edit unit number / BHK") { showEditDefinition = true }
                } footer: {
                    Text("Admins can correct the unit number or BHK layout.")
                }
            }

            if canUpdateStatus {
                Section {
                    Button("Update occupancy / to-let board") { showUpdateStatus = true }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                }
            }
        }
        .navigationTitle(unit.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssignTenancy) {
            AssignTenancySheet(unitId: unit.id) {
                await load()
            }
        }
        .sheet(isPresented: $showUpdateStatus) {
            UpdateUnitStatusSheet(unit: unit) { updated in
                unit = updated
            }
        }
        .sheet(isPresented: $showEditDefinition) {
            EditUnitDefinitionSheet(unit: unit) { updated in
                unit = updated
            }
        }
        .sheet(isPresented: Binding(
            get: { endingTenancyId != nil },
            set: { if !$0 { endingTenancyId = nil } }
        )) {
            if let endingTenancyId {
                EndTenancySheet(tenancyId: endingTenancyId) {
                    await load()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            tenancies = try await appState.api.tenancies(unitId: unit.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssignTenancySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unitId: UUID
    var onSaved: () async -> Void

    @State private var tenants: [ManagedUserItem] = []
    @State private var selectedTenantId: UUID?
    @State private var moveInDate = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isLoading = true

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Loading tenants…")
                } else {
                    Section("Tenant") {
                        if tenants.isEmpty {
                            Text("No active tenants found. Create a tenant in People first.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            Picker("Tenant", selection: $selectedTenantId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(tenants) { tenant in
                                    Text(tenant.fullName).tag(Optional(tenant.id))
                                }
                            }
                        }
                        DatePicker("Move-in date", selection: $moveInDate, displayedComponents: .date)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Assign tenancy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task { await loadTenants() }
        }
    }

    private func loadTenants() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tenants = try await appState.api.users(role: "TENANT", size: 100).content.filter { $0.active }
            if selectedTenantId == nil {
                selectedTenantId = tenants.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        if tenants.isEmpty {
            errorMessage = "No active tenants found. Create a tenant under People first, then assign tenancy."
            return
        }
        guard let selectedTenantId else {
            errorMessage = "Select a tenant for this unit."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.createTenancy(
                unitId: unitId,
                CreateTenancyBody(
                    tenantUserId: selectedTenantId,
                    moveInDate: Self.dayFormatter.string(from: moveInDate)
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EndTenancySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let tenancyId: UUID
    var onSaved: () async -> Void

    @State private var moveOutDate = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Move-out date", selection: $moveOutDate, displayedComponents: .date)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("End tenancy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.endTenancy(
                id: tenancyId,
                EndTenancyBody(moveOutDate: Self.dayFormatter.string(from: moveOutDate))
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UpdateUnitStatusSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unit: UnitItem
    var onSaved: (UnitItem) -> Void

    @State private var occupancy: OccupancyStatusOption
    @State private var toLet: ToLetBoardStatusOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(unit: UnitItem, onSaved: @escaping (UnitItem) -> Void) {
        self.unit = unit
        self.onSaved = onSaved
        _occupancy = State(initialValue: OccupancyStatusOption(rawValue: unit.occupancyStatus) ?? .VACANT)
        _toLet = State(initialValue: ToLetBoardStatusOption(rawValue: unit.toLetBoardStatus) ?? .NOT_INSTALLED)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Occupancy", selection: $occupancy) {
                        ForEach(OccupancyStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("To-let board", selection: $toLet) {
                        ForEach(ToLetBoardStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Update unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await appState.api.updateUnitStatus(
                unitId: unit.id,
                UpdateUnitStatusBody(
                    occupancyStatus: occupancy.rawValue,
                    toLetBoardStatus: toLet.rawValue
                )
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditUnitDefinitionSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unit: UnitItem
    var onSaved: (UnitItem) -> Void

    @State private var unitNumber: String
    @State private var unitType: UnitTypeOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(unit: UnitItem, onSaved: @escaping (UnitItem) -> Void) {
        self.unit = unit
        self.onSaved = onSaved
        _unitNumber = State(initialValue: unit.unitNumber)
        _unitType = State(initialValue: UnitTypeOption(rawValue: unit.unitType) ?? .TWO_BHK)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit") {
                    TextField("Unit number", text: $unitNumber)
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    ForEach(UnitTypeOption.pickerCases) { option in
                        Button {
                            unitType = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(NriTheme.ink)
                                Spacer()
                                if unitType == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NriTheme.teal)
                                }
                            }
                        }
                    }
                } header: {
                    Text("BHK layout")
                } footer: {
                    Text("Selected: \(unitType.title)")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Edit unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        let trimmed = unitNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Unit number is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await appState.api.updateUnit(
                unitId: unit.id,
                UpdateUnitBody(unitNumber: trimmed, unitType: unitType.rawValue)
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
