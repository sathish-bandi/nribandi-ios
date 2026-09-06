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
        session.user?.role == .ADMIN
    }

    private var usesBlocks: Bool {
        PropertyTypeOption(rawValue: property.propertyType)?.usesBlocks == true
    }

    private var structureHint: String {
        if usesBlocks {
            return "Set up this property in order: add blocks/towers → add floors under each block → add units and map each unit to 1/2/3 BHK."
        }
        return "Add floors first, then add units and map each unit to its BHK layout (1 BHK, 2 BHK, 3 BHK, …)."
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(structureHint)
                            .foregroundStyle(NriTheme.slate)
                        Text("When adding a unit, choose the BHK layout (1 BHK, 2 BHK, 3 BHK, …) for that floor.")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.slate)
                    }
                } else {
                    ForEach(units) { unit in
                        NavigationLink {
                            UnitDetailView(unit: unit, propertyName: property.name)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(unit.title).font(.subheadline.weight(.semibold))
                                HStack {
                                    StatusChip(text: UnitTypeDisplay.title(for: unit.unitType))
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
                        if usesBlocks {
                            Button("Add block / tower") { showAddBlock = true }
                        }
                        Button("Add floor") { showAddFloor = true }
                        Button("Add unit (BHK)") { showAddUnit = true }
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
            .environmentObject(appState)
            .environmentObject(session)
        }
        .sheet(isPresented: $showAddBlock) {
            AddBlockSheet(propertyId: property.id) {
                await reload()
            }
        }
        .sheet(isPresented: $showAddFloor) {
            AddFloorSheet(propertyId: property.id, blocks: blocks, requiresBlock: usesBlocks) {
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
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        let trimmedNumber = blockNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNumber.isEmpty else {
            errorMessage = "Block number is required (for example A, B, or Tower-1)."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            _ = try await appState.api.createBlock(
                propertyId: propertyId,
                CreateBlockBody(
                    blockNumber: trimmedNumber,
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
    let requiresBlock: Bool
    var onSaved: () async -> Void

    @State private var floorNumber = 1
    @State private var name = ""
    @State private var selectedBlockId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $floorNumber, in: 0...200) {
                        Text("Floor number: \(floorNumber)")
                    }
                    TextField("Name (optional)", text: $name)
                    if requiresBlock {
                        if blocks.isEmpty {
                            Text("Add a block / tower first. Apartment and high-rise floors must belong to a block.")
                                .foregroundStyle(NriTheme.terracotta)
                                .font(.footnote)
                        } else {
                            Picker("Block / tower", selection: $selectedBlockId) {
                                Text("Select block").tag(Optional<UUID>.none)
                                ForEach(blocks) { block in
                                    Text("Block \(block.blockNumber)").tag(Optional(block.id))
                                }
                            }
                        }
                    } else if !blocks.isEmpty {
                        Picker("Block (optional)", selection: $selectedBlockId) {
                            Text("None").tag(Optional<UUID>.none)
                            ForEach(blocks) { block in
                                Text("Block \(block.blockNumber)").tag(Optional(block.id))
                            }
                        }
                    }
                } header: {
                    Text("Floor")
                } footer: {
                    if requiresBlock {
                        Text("For apartments and high-rises, every floor must be mapped to a block.")
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
            .onAppear {
                if selectedBlockId == nil {
                    selectedBlockId = blocks.first?.id
                }
            }
        }
    }

    private func save() async {
        if requiresBlock {
            if blocks.isEmpty {
                errorMessage = "Add a block / tower before creating floors for this property type."
                return
            }
            if selectedBlockId == nil {
                errorMessage = "Select a block / tower for this floor."
                return
            }
        }
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
    @State private var unitType: UnitTypeOption = .TWO_BHK
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let commonLayouts: [UnitTypeOption] = [.ONE_BHK, .TWO_BHK, .THREE_BHK, .FOUR_BHK]
    private static let otherLayouts: [UnitTypeOption] = [
        .PENTHOUSE, .VILLA, .INDEPENDENT_HOUSE,
        .FIVE_BHK, .SIX_BHK, .SEVEN_BHK, .EIGHT_BHK, .NINE_BHK, .TEN_BHK
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
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
                    TextField("Unit number (e.g. 201)", text: $unitNumber)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Location")
                }

                Section {
                    ForEach(Self.commonLayouts) { option in
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
                    Text("Required. Map this flat to its layout — for example unit 201 as 2 BHK, unit 301 as 3 BHK.")
                }

                Section {
                    ForEach(Self.otherLayouts) { option in
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
                    Text("Specialty layouts")
                } footer: {
                    Text("Selected layout: \(unitType.title)")
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
                        .disabled(isSaving)
                }
            }
            .onAppear {
                if selectedFloorId == nil {
                    selectedFloorId = floors.first?.id
                }
            }
        }
    }

    private func floorPickerLabel(_ floor: FloorItem) -> String {
        if let block = floor.blockNumber, !block.isEmpty {
            return "Block \(block) · Floor \(floor.floorNumber)"
        }
        return "Floor \(floor.floorNumber)"
    }

    private func save() async {
        if floors.isEmpty {
            errorMessage = "Add a floor before creating units."
            return
        }
        guard let selectedFloorId else {
            errorMessage = "Select the floor this unit belongs to."
            return
        }
        let trimmed = unitNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a unit number (for example 101 or A-201)."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.createUnit(
                propertyId: propertyId,
                CreateUnitBody(
                    floorId: selectedFloorId,
                    unitNumber: trimmed,
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
