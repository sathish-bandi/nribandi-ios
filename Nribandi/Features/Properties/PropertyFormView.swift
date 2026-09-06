import SwiftUI

struct PropertyFormView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    enum Mode {
        case create
        case edit(PropertyItem)
    }

    let mode: Mode
    let onSaved: (PropertyItem) async -> Void

    @State private var name = ""
    @State private var address = ""
    @State private var locality = ""
    @State private var city = "Hyderabad"
    @State private var state = "Telangana"
    @State private var pincode = ""
    @State private var numberOfFloors = 1
    @State private var propertyType: PropertyTypeOption = .APARTMENT
    @State private var propertyPurpose: PropertyPurposeOption = .RESIDENTIAL
    @State private var owners: [ManagedUserItem] = []
    @State private var selectedOwnerId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isLoadingOwners = false

    private var isCreate: Bool {
        if case .create = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Property") {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Locality", text: $locality)
                    TextField("City", text: $city)
                    TextField("State", text: $state)
                    TextField("Pincode", text: $pincode)
                        .keyboardType(.numberPad)
                    Stepper("Floors: \(numberOfFloors)", value: $numberOfFloors, in: 1...200)
                    Picker("Type", selection: $propertyType) {
                        ForEach(PropertyTypeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("Purpose", selection: $propertyPurpose) {
                        ForEach(PropertyPurposeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }

                if isCreate {
                    Section("Owner") {
                        if isLoadingOwners {
                            ProgressView("Loading owners…")
                        } else if owners.isEmpty {
                            Text("No owners found. Create an owner in People first.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            Picker("Owner", selection: $selectedOwnerId) {
                                Text("Select owner").tag(Optional<UUID>.none)
                                ForEach(owners) { owner in
                                    Text(owner.fullName).tag(Optional(owner.id))
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                    }
                }
            }
            .navigationTitle(isCreate ? "Add property" : "Edit property")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || !isValid)
                }
            }
            .task {
                prefill()
                if isCreate { await loadOwners() }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pincode.count == 6
            && (!isCreate || selectedOwnerId != nil)
    }

    private func prefill() {
        guard case .edit(let property) = mode else { return }
        name = property.name
        address = property.address
        locality = property.locality ?? ""
        city = property.city
        state = property.state
        pincode = property.pincode
        numberOfFloors = property.numberOfFloors ?? 1
        propertyType = PropertyTypeOption(rawValue: property.propertyType) ?? .APARTMENT
        propertyPurpose = PropertyPurposeOption(rawValue: property.propertyPurpose) ?? .RESIDENTIAL
    }

    private func loadOwners() async {
        isLoadingOwners = true
        defer { isLoadingOwners = false }
        do {
            owners = try await appState.api.users(role: "OWNER", size: 100).content.filter(\.active)
            if selectedOwnerId == nil {
                selectedOwnerId = owners.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let saved: PropertyItem
            switch mode {
            case .create:
                saved = try await appState.api.createProperty(
                    CreatePropertyBody(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                        locality: locality.trimmingCharacters(in: .whitespacesAndNewlines),
                        city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                        state: state.trimmingCharacters(in: .whitespacesAndNewlines),
                        pincode: pincode,
                        latitude: nil,
                        longitude: nil,
                        numberOfFloors: numberOfFloors,
                        propertyType: propertyType.rawValue,
                        propertyPurpose: propertyPurpose.rawValue,
                        ownerId: selectedOwnerId
                    )
                )
            case .edit(let property):
                saved = try await appState.api.updateProperty(
                    id: property.id,
                    UpdatePropertyBody(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                        locality: locality.trimmingCharacters(in: .whitespacesAndNewlines),
                        city: city.trimmingCharacters(in: .whitespacesAndNewlines),
                        state: state.trimmingCharacters(in: .whitespacesAndNewlines),
                        pincode: pincode,
                        latitude: nil,
                        longitude: nil,
                        numberOfFloors: numberOfFloors,
                        propertyType: propertyType.rawValue,
                        propertyPurpose: propertyPurpose.rawValue
                    )
                )
            }
            await onSaved(saved)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}