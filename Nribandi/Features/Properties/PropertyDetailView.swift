import SwiftUI

struct PropertyDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var property: PropertyItem
    @State private var units: [UnitItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showEdit = false

    init(property: PropertyItem) {
        _property = State(initialValue: property)
    }

    private var canEdit: Bool {
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
            Section("Units") {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                } else if units.isEmpty {
                    Text("No units yet.")
                } else {
                    ForEach(units) { unit in
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
        .navigationTitle(property.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEdit = true }
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            PropertyFormView(mode: .edit(property)) { updated in
                property = updated
            }
        }
        .task { await loadUnits() }
        .refreshable { await loadUnits() }
    }

    private func loadUnits() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { units = try await appState.api.units(propertyId: property.id) }
        catch { errorMessage = error.localizedDescription }
    }
}