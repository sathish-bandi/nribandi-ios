import SwiftUI

struct PropertyDetailView: View {
    @EnvironmentObject private var appState: AppState
    let property: PropertyItem

    @State private var units: [UnitItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        List {
            Section("Address") {
                Text(property.address)
                Text(property.locationLine).foregroundStyle(NriTheme.slate)
                Text("\(property.state) · \(property.propertyType) · \(property.propertyPurpose)")
                    .font(.footnote)
                    .foregroundStyle(NriTheme.slate)
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
