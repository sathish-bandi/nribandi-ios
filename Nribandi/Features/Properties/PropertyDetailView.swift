import SwiftUI

struct PropertyDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var property: PropertyItem
    @State private var units: [UnitItem] = []
    @State private var blocks: [BlockItem] = []
    @State private var floors: [FloorItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showAddBlock = false
    @State private var showAddFloor = false
    @State private var showAddUnit = false

    init(property: PropertyItem) {
        _property = State(initialValue: property)
    }

    private var canManageStructure: Bool {
        session.user?.role == .ADMIN || session.user?.role == .OWNER
    }

    var body: some View {
        List {
            Section("Address") {
                Text(property.address)
                Text(property.locationLine).foregroundStyle(NriTheme.slate)
                Text("\(property.state) · \(property.propertyType) · \(property.propertyPurpose)")
                    .font(.footnote)
                    .foregroundStyle(NriTheme.slate)
                if let ownerName = property.ownerName {
                    Text("Owner: \(ownerName)").font(.footnote).foregroundStyle(NriTheme.slate)
                }
            }

            if !blocks.isEmpty {
                Section("Blocks") {
                    ForEach(blocks) { block in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Block \(block.blockNumber)").font(.subheadline.weight(.semibold))
                            if let name = block.name, !name.isEmpty {
                                Text(name).font(.footnote).foregroundStyle(NriTheme.slate)
                            }
                        }
                    }
                }
            }

            if !floors.isEmpty {
                Section("Floors") {
                    ForEach(floors) { floor in
                        Text(floorLabel(floor))
                            .font(.subheadline)
                    }
                }
            }

            Section("Units") {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                } else if units.isEmpty {
                    Text("No units yet.")
                } else {
                    ForEach(units) { unit in
                        NavigationLink {
                            UnitDetailView(unit: unit, propertyName: property.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(unit.title).font(.subheadline.weight(.semibold))
                                HStack {
                                    StatusChip(text: unit.unitType)
                                    StatusChip(text: unit.occupancyStatus)
                                    StatusChip(text: unit.toLetBoardStatus)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canManageStructure {
                    Menu {
                        Button("Edit property") { showEdit = true }
                        Button("Add block") { showAddBlock = true }
                        Button("Add floor") { showAddFloor = true }
                        Button("Add unit") { showAddUnit = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Manage property")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            PropertyFormView(mode: .edit(property)) { updated in
                property = updated
            }
        }
        .sheet(isPresented: $showAddBlock) {
            AddBlockSheet(propertyId: property.id) {
                await reload()
            }
        }
        .sheet(isPresented: $showAddFloor) {
            AddFloorSheet(propertyId: property.id, blocks: blocks) {
                await reload()
            }
        }
        .sheet(isPresented: $showAddUnit) {
            AddUnitSheet(propertyId: property.id, floors: floors) {
                await reload()
            }
        }
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func floorLabel(_ floor: FloorItem) -> String {
        var parts = ["Floor \(floor.floorNumber)"]
        if let block = floor.blockNumber, !block.isEmpty {
            parts.insert("Block \(block)", at: 0)
        }
        if let name = floor.name, !name.isEmpty {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let loadedUnits = appState.api.units(propertyId: property.id)
            async let loadedBlocks = appState.api.blocks(propertyId: property.id)
            async let loadedFloors = appState.api.floors(propertyId: property.id)
            units = try await loadedUnits
            blocks = (try? await loadedBlocks) ?? []
            floors = (try? await loadedFloors) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddBlockSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let propertyId: UUID
    var onSaved: () async -> Void

    @State private var blockNumber = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Block") {
                    TextField("Block number", text: $blockNumber)
                    TextField("Name (optional)", text: $name)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Add block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || blockNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await appState.api.createBlock(
                propertyId: propertyId,
                CreateBlockBody(
                    blockNumber: blockNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    name: trimmedName.isEmpty ? nil : trimmedName
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddFloorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let propertyId: UUID
    let blocks: [BlockItem]
    var onSaved: () async -> Void

    @State private var floorNumber = 1
    @State private var name = ""
    @State private var selectedBlockId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Floor") {
                    Stepper("Floor number: \(floorNumber)", value: $floorNumber, in: 0...200)
                    TextField("Name (optional)", text: $name)
                    if !blocks.isEmpty {
                        Picker("Block (optional)", selection: $selectedBlockId) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(blocks) { block in
                                Text("Block \(block.blockNumber)").tag(Optional(block.id))
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Add floor")
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let block = blocks.first(where: { $0.id == selectedBlockId })
        do {
            _ = try await appState.api.createFloor(
                propertyId: propertyId,
                CreateFloorBody(
                    floorNumber: floorNumber,
                    name: trimmedName.isEmpty ? nil : trimmedName,
                    blockId: selectedBlockId,
                    blockNumber: block?.blockNumber
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddUnitSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let propertyId: UUID
    let floors: [FloorItem]
    var onSaved: () async -> Void

    @State private var selectedFloorId: UUID?
    @State private var unitNumber = ""
    @State private var unitType: UnitTypeOption = .ONE_BHK
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit") {
                    if floors.isEmpty {
                        Text("Add a floor before creating units.")
                            .foregroundStyle(NriTheme.terracotta)
                    } else {
                        Picker("Floor", selection: $selectedFloorId) {
                            Text("Select floor").tag(Optional<UUID>.none)
                            ForEach(floors) { floor in
                                Text(floorPickerLabel(floor)).tag(Optional(floor.id))
                            }
                        }
                    }
                    TextField("Unit number", text: $unitNumber)
                    Picker("Type", selection: $unitType) {
                        ForEach(UnitTypeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Add unit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving || !canSave)
                }
            }
            .onAppear {
                if selectedFloorId == nil {
                    selectedFloorId = floors.first?.id
                }
            }
        }
    }

    private var canSave: Bool {
        selectedFloorId != nil && !unitNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func floorPickerLabel(_ floor: FloorItem) -> String {
        if let block = floor.blockNumber, !block.isEmpty {
            return "Block \(block) · Floor \(floor.floorNumber)"
        }
        return "Floor \(floor.floorNumber)"
    }

    private func save() async {
        guard let selectedFloorId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.createUnit(
                propertyId: propertyId,
                CreateUnitBody(
                    floorId: selectedFloorId,
                    unitNumber: unitNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                    unitType: unitType.rawValue
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
