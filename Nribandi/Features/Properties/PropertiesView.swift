import SwiftUI

struct PropertiesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [PropertyItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading properties…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Could not load", systemImage: "building.2", description: Text(errorMessage))
                } else if items.isEmpty {
                    ContentUnavailableView("No properties", systemImage: "building.2", description: Text("Nothing visible for this account yet."))
                } else {
                    List(items) { property in
                        NavigationLink(value: property) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(property.name).font(.headline).foregroundStyle(NriTheme.ink)
                                Text(property.locationLine).font(.subheadline).foregroundStyle(NriTheme.slate)
                                HStack {
                                    StatusChip(text: property.propertyType)
                                    StatusChip(text: property.propertyPurpose)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                    .navigationDestination(for: PropertyItem.self) { PropertyDetailView(property: $0) }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Properties")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { items = try await appState.api.properties().content }
        catch { errorMessage = error.localizedDescription }
    }
}
