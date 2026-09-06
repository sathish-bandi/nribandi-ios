import SwiftUI

struct InspectionsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var items: [InspectionItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false
    var embedsInParentNavigation = false

    private var canManage: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading inspections…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView("Could not load", systemImage: "checklist", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("No inspections", systemImage: "checklist")
                } description: {
                    Text("Schedule move-in, periodic, or vacancy inspections.")
                } actions: {
                    if canManage {
                        Button("Schedule inspection") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List(items) { item in
                    NavigationLink {
                        InspectionDetailView(inspection: item) { await load() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.propertyName ?? "Property").font(.headline)
                            if let unit = item.unitNumber {
                                Text("Unit \(unit)").font(.subheadline).foregroundStyle(NriTheme.slate)
                            }
                            HStack {
                                StatusChip(text: item.inspectionType)
                                StatusChip(text: item.status)
                                if let date = item.inspectionDate { StatusChip(text: date) }
                            }
                            if let inspector = item.inspectorEmployeeName {
                                Text("Inspector: \(inspector)")
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
        .navigationTitle("Inspections")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if canManage {
                        Button { showCreate = true } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Schedule inspection")
                    }
                    if !embedsInParentNavigation {
                        EnvBadge(env: appState.environment)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateInspectionView {
                showCreate = false
                await load()
            }
        }
        .task { await load() }
        .modifier(OpsOptionalNavigationStack(enabled: !embedsInParentNavigation))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await appState.api.inspections(size: 100).content
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InspectionDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var inspection: InspectionItem
    var onChanged: () async -> Void

    @State private var showStatus = false
    @State private var errorMessage: String?

    init(inspection: InspectionItem, onChanged: @escaping () async -> Void) {
        _inspection = State(initialValue: inspection)
        self.onChanged = onChanged
    }

    private var canUpdate: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    var body: some View {
        List {
            Section("Inspection") {
                LabeledContent("Property", value: inspection.propertyName ?? "—")
                if let unit = inspection.unitNumber {
                    LabeledContent("Unit", value: unit)
                }
                LabeledContent("Type", value: inspection.inspectionType)
                LabeledContent("Date", value: inspection.inspectionDate ?? "—")
                LabeledContent("Status", value: inspection.status)
                if let inspector = inspection.inspectorEmployeeName {
                    LabeledContent("Inspector", value: inspector)
                }
                if let notes = inspection.notes, !notes.isEmpty {
                    Text(notes)
                }
            }
            if canUpdate {
                Section {
                    Button("Update status") { showStatus = true }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
            }
        }
        .navigationTitle("Inspection")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStatus) {
            UpdateInspectionStatusSheet(current: inspection.status) { status in
                inspection = try await appState.api.updateInspectionStatus(id: inspection.id, status: status)
                await onChanged()
            }
        }
    }
}

private struct UpdateInspectionStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let current: String
    var onSave: (String) async throws -> Void

    @State private var status: InspectionStatusOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(current: String, onSave: @escaping (String) async throws -> Void) {
        self.current = current
        self.onSave = onSave
        _status = State(initialValue: InspectionStatusOption(rawValue: current) ?? .SCHEDULED)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(InspectionStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Update status")
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
            try await onSave(status.rawValue)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateInspectionView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var onCreated: () async -> Void

    @State private var properties: [PropertyItem] = []
    @State private var units: [UnitItem] = []
    @State private var employees: [ManagedUserItem] = []
    @State private var selectedPropertyId: UUID?
    @State private var selectedUnitId: UUID?
    @State private var selectedEmployeeId: UUID?
    @State private var inspectionType: InspectionTypeOption = .PERIODIC
    @State private var inspectionDate = Date()
    @State private var notes = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isBootstrapping = true

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
                if isBootstrapping {
                    ProgressView("Loading…")
                } else {
                    Section("Where") {
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
                            Text("Whole property").tag(Optional<UUID>.none)
                            ForEach(units) { unit in
                                Text(unit.title).tag(Optional(unit.id))
                            }
                        }
                    }
                    Section("Schedule") {
                        Picker("Type", selection: $inspectionType) {
                            ForEach(InspectionTypeOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                        DatePicker("Date", selection: $inspectionDate, displayedComponents: .date)
                        Picker("Inspector", selection: $selectedEmployeeId) {
                            Text("Select").tag(Optional<UUID>.none)
                            ForEach(employees) { employee in
                                Text(employee.fullName).tag(Optional(employee.id))
                            }
                        }
                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Schedule inspection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .disabled(isSaving || selectedPropertyId == nil || selectedEmployeeId == nil)
                }
            }
            .task { await bootstrap() }
        }
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            async let props = appState.api.properties(size: 100).content
            async let emps = appState.api.users(role: "EMPLOYEE", size: 100).content
            properties = try await props
            employees = try await emps.filter { $0.active }
            selectedPropertyId = properties.first?.id
            selectedEmployeeId = employees.first?.id
            await loadUnits(for: selectedPropertyId)
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
        guard let selectedPropertyId, let selectedEmployeeId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await appState.api.createInspection(
                CreateInspectionBody(
                    propertyId: selectedPropertyId,
                    unitId: selectedUnitId,
                    inspectorEmployeeId: selectedEmployeeId,
                    inspectionType: inspectionType.rawValue,
                    inspectionDate: Self.dayFormatter.string(from: inspectionDate),
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes
                )
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
