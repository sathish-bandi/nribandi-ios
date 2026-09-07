import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PropertyDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var property: PropertyItem
    @State private var units: [UnitItem] = []
    @State private var blocks: [BlockItem] = []
    @State private var floors: [FloorItem] = []
    @State private var attachments: [PropertyAttachmentItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showEdit = false
    @State private var showAddBlock = false
    @State private var showAddFloor = false
    @State private var showAddUnit = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var isUploadingMedia = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    init(property: PropertyItem) {
        _property = State(initialValue: property)
    }

    private var canManageStructure: Bool {
        session.user?.role == .ADMIN
    }

    private var canViewMedia: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .OWNER || role == .EMPLOYEE
    }

    private var usesBlocks: Bool {
        PropertyTypeOption(rawValue: property.propertyType)?.usesBlocks == true
    }

    private var structureHint: String {
        if floors.isEmpty {
            if usesBlocks && blocks.isEmpty {
                return "Add a block/tower, then floors under it, then units with a BHK layout."
            }
            if usesBlocks {
                return "Add floors under a block/tower, then add units and map each to 1/2/3 BHK."
            }
            return "Add floors first, then add units and map each unit to its BHK layout (1 BHK, 2 BHK, 3 BHK, …)."
        }
        return "No units yet. Use Add unit (BHK) to create a flat and choose its layout (1 BHK, 2 BHK, 3 BHK, …)."
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                NriSectionCard(title: "Address") {
                    Text(property.address)
                    Text(property.locationLine).foregroundStyle(NriTheme.slate)
                    Text("\(property.state) · \(property.propertyType) · \(property.propertyPurpose)")
                        .font(.footnote)
                        .foregroundStyle(NriTheme.slate)
                    if let ownerName = property.ownerName {
                        Text("Owner: \(ownerName)").font(.footnote).foregroundStyle(NriTheme.slate)
                    }
                    if property.isActive == false {
                        StatusChip(text: "INACTIVE")
                    }
                }

                if canViewMedia {
                    NriSectionCard(
                        title: "Gallery",
                        footer: canManageStructure
                            ? "Admins can upload images or videos for listings and walkthroughs."
                            : nil
                    ) {
                        if attachments.isEmpty {
                            Text("No photos or videos yet.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            // Grid inside the page ScrollView — no nested horizontal ScrollView.
                            LazyVGrid(
                                columns: [GridItem(.adaptive(minimum: 110), spacing: 12)],
                                spacing: 12
                            ) {
                                ForEach(attachments) { attachment in
                                    PropertyAttachmentThumb(
                                        attachment: attachment,
                                        canDelete: canManageStructure,
                                        onDelete: {
                                            Task { await deleteAttachment(attachment) }
                                        }
                                    )
                                }
                            }
                        }

                        if canManageStructure {
                            PhotosPicker(
                                selection: $photoItems,
                                maxSelectionCount: 6,
                                matching: .any(of: [.images, .videos])
                            ) {
                                Label(isUploadingMedia ? "Uploading…" : "Add photos / videos", systemImage: "photo.on.rectangle")
                            }
                            .disabled(isUploadingMedia)
                            .onChange(of: photoItems) { _, newItems in
                                guard !newItems.isEmpty else { return }
                                Task { await uploadPhotoItems(newItems) }
                            }

                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Import file", systemImage: "folder")
                            }
                            .disabled(isUploadingMedia)
                        }
                    }
                }

                if !blocks.isEmpty {
                    NriSectionCard(title: "Blocks") {
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
                    NriSectionCard(title: "Floors (\(floors.count))") {
                        ForEach(floors.sorted(by: floorSort)) { floor in
                            Text(floorLabel(floor))
                                .font(.subheadline)
                        }
                    }
                }

                NriSectionCard(title: "Units") {
                    if isLoading {
                        ProgressView()
                    } else if let errorMessage {
                        Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                    } else if units.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(structureHint)
                                .foregroundStyle(NriTheme.slate)
                            if floors.isEmpty {
                                Text("When floors exist, use Add unit (BHK) and choose the layout for each flat.")
                                    .font(.footnote)
                                    .foregroundStyle(NriTheme.slate)
                            }
                        }
                    } else {
                        ForEach(units) { unit in
                            NavigationLink {
                                UnitDetailView(unit: unit, propertyName: property.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(unit.title).font(.subheadline.weight(.semibold))
                                    StatusChip(text: UnitTypeDisplay.title(for: unit.unitType), emphasized: true)
                                    HStack {
                                        StatusChip(text: unit.occupancyStatus)
                                        StatusChip(text: unit.toLetBoardStatus)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if canManageStructure {
                    NriSectionCard(
                        title: nil,
                        footer: "Soft-deletes the property (marks inactive). Related tenancies and tickets stay intact."
                    ) {
                        Button("Delete property", role: .destructive) {
                            showDeleteConfirm = true
                        }
                        .disabled(isDeleting || property.isActive == false)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .padding(.bottom, 24)
        }
        .background(NriTheme.pageBackground.ignoresSafeArea())
        .nriScrollable()
        .nriPhoneScrollInsets()
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
                        Divider()
                        Button("Delete property", role: .destructive) { showDeleteConfirm = true }
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
            AddUnitSheet(propertyId: property.id, initialFloors: floors) {
                await reload()
            }
            .environmentObject(appState)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .movie, .mpeg4Movie, .quickTimeMovie, .jpeg, .png, .heic],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleImportedFile(result) }
        }
        .confirmationDialog(
            "Delete this property?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete property", role: .destructive) {
                Task { await softDelete() }
            }
            Button("Keep property", role: .cancel) {}
        } message: {
            Text("The property will be marked inactive and hidden from active listings.")
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

    private func floorSort(_ lhs: FloorItem, _ rhs: FloorItem) -> Bool {
        let leftBlock = lhs.blockNumber ?? ""
        let rightBlock = rhs.blockNumber ?? ""
        if leftBlock != rightBlock { return leftBlock < rightBlock }
        return lhs.floorNumber < rhs.floorNumber
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let loadedUnits = appState.api.units(propertyId: property.id)
            async let loadedBlocks = appState.api.blocks(propertyId: property.id)
            async let loadedFloors = appState.api.floors(propertyId: property.id)
            async let loadedAttachments = appState.api.propertyAttachments(propertyId: property.id)
            units = try await loadedUnits
            blocks = try await loadedBlocks
            floors = try await loadedFloors
            if canViewMedia {
                attachments = (try? await loadedAttachments) ?? []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func softDelete() async {
        isDeleting = true
        errorMessage = nil
        defer { isDeleting = false }
        do {
            property = try await appState.api.deleteProperty(id: property.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteAttachment(_ attachment: PropertyAttachmentItem) async {
        do {
            try await appState.api.deletePropertyAttachment(propertyId: property.id, attachmentId: attachment.id)
            attachments.removeAll { $0.id == attachment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadPhotoItems(_ items: [PhotosPickerItem]) async {
        isUploadingMedia = true
        defer {
            isUploadingMedia = false
            photoItems = []
        }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let mime = Self.guessMime(for: item, data: data)
                let name = "property-\(UUID().uuidString.prefix(8)).\(Self.fileExtension(for: mime))"
                let uploaded = try await appState.api.uploadPropertyAttachment(
                    propertyId: property.id,
                    fileData: data,
                    fileName: name,
                    mimeType: mime
                )
                attachments.insert(uploaded, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleImportedFile(_ result: Result<[URL], Error>) async {
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            isUploadingMedia = true
            defer { isUploadingMedia = false }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let mime = Self.mimeType(for: url) ?? "application/octet-stream"
                let uploaded = try await appState.api.uploadPropertyAttachment(
                    propertyId: property.id,
                    fileData: data,
                    fileName: url.lastPathComponent,
                    mimeType: mime
                )
                attachments.insert(uploaded, at: 0)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func guessMime(for item: PhotosPickerItem, data: Data) -> String {
        if let type = item.supportedContentTypes.first?.preferredMIMEType {
            return type
        }
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        return "image/jpeg"
    }

    private static func fileExtension(for mime: String) -> String {
        switch mime {
        case "image/png": return "png"
        case "image/heic": return "heic"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        default: return "jpg"
        }
    }

    private static func mimeType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }
}

private struct PropertyAttachmentThumb: View {
    let attachment: PropertyAttachmentItem
    let canDelete: Bool
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NriTheme.mist)
                    .frame(maxWidth: .infinity)
                    .frame(height: 90)
                if attachment.isVideo {
                    Image(systemName: "video.fill")
                        .font(.title2)
                        .foregroundStyle(NriTheme.teal)
                } else {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(NriTheme.teal)
                }
            }
            Text(attachment.originalFilename ?? "Media")
                .font(.caption2)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if canDelete {
                Button("Delete", role: .destructive, action: onDelete)
                    .font(.caption2)
            }
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
    let initialFloors: [FloorItem]
    var onSaved: () async -> Void

    @State private var floors: [FloorItem]
    @State private var selectedFloorId: UUID?
    @State private var unitNumber = ""
    @State private var unitType: UnitTypeOption = .TWO_BHK
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isLoadingFloors = false

    init(propertyId: UUID, initialFloors: [FloorItem], onSaved: @escaping () async -> Void) {
        self.propertyId = propertyId
        self.initialFloors = initialFloors
        self.onSaved = onSaved
        _floors = State(initialValue: Self.sortedFloors(initialFloors))
        _selectedFloorId = State(initialValue: Self.sortedFloors(initialFloors).first?.id)
    }

    private static let commonLayouts: [UnitTypeOption] = [.ONE_BHK, .TWO_BHK, .THREE_BHK, .FOUR_BHK]
    private static let otherLayouts: [UnitTypeOption] = [
        .PENTHOUSE, .VILLA, .INDEPENDENT_HOUSE,
        .FIVE_BHK, .SIX_BHK, .SEVEN_BHK, .EIGHT_BHK, .NINE_BHK, .TEN_BHK
    ]

    private var sortedFloors: [FloorItem] { Self.sortedFloors(floors) }

    private static func sortedFloors(_ floors: [FloorItem]) -> [FloorItem] {
        floors.sorted { lhs, rhs in
            let leftBlock = lhs.blockNumber ?? ""
            let rightBlock = rhs.blockNumber ?? ""
            if leftBlock != rightBlock { return leftBlock < rightBlock }
            return lhs.floorNumber < rhs.floorNumber
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if isLoadingFloors && floors.isEmpty {
                        ProgressView("Loading floors…")
                    } else if floors.isEmpty {
                        Text("No floors on this property yet. Create the property with a floor count, or add a floor first.")
                            .foregroundStyle(NriTheme.terracotta)
                    } else {
                        Picker("Floor", selection: $selectedFloorId) {
                            Text("Select floor").tag(Optional<UUID>.none)
                            ForEach(sortedFloors) { floor in
                                Text(floorPickerLabel(floor)).tag(Optional(floor.id))
                            }
                        }
                        Text("\(sortedFloors.count) floor\(sortedFloors.count == 1 ? "" : "s") available")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.slate)
                    }
                    TextField("Unit number (e.g. 201)", text: $unitNumber)
                        .textInputAutocapitalization(.characters)
                } header: {
                    Text("Location")
                }

                Section {
                    ForEach(Self.commonLayouts) { option in
                        unitTypeRow(option)
                    }
                } header: {
                    Text("BHK layout")
                } footer: {
                    Text("Required. Saves as \(unitType.rawValue) (for example 2 BHK → TWO_BHK).")
                }

                Section {
                    ForEach(Self.otherLayouts) { option in
                        unitTypeRow(option)
                    }
                } header: {
                    Text("Specialty layouts")
                } footer: {
                    Text("Selected: \(unitType.title)")
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
                        .disabled(isSaving || floors.isEmpty)
                }
            }
            .task { await refreshFloors() }
        }
    }

    private func floorPickerLabel(_ floor: FloorItem) -> String {
        if let block = floor.blockNumber, !block.isEmpty {
            return "Block \(block) · Floor \(floor.floorNumber)"
        }
        return "Floor \(floor.floorNumber)"
    }

    @ViewBuilder
    private func unitTypeRow(_ option: UnitTypeOption) -> some View {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private func refreshFloors() async {
        isLoadingFloors = true
        defer { isLoadingFloors = false }
        do {
            let loaded = try await appState.api.floors(propertyId: propertyId)
            floors = Self.sortedFloors(loaded)
            if selectedFloorId == nil || !floors.contains(where: { $0.id == selectedFloorId }) {
                selectedFloorId = floors.first?.id
            }
        } catch {
            if floors.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
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
            // unitType.rawValue is TWO_BHK / THREE_BHK — matches backend UnitType enum.
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
