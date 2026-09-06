import SwiftUI

struct ServiceRequestsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [ServiceRequestItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading requests…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Could not load", systemImage: "wrench.and.screwdriver", description: Text(errorMessage))
                } else if items.isEmpty {
                    ContentUnavailableView("No service requests", systemImage: "checkmark.seal", description: Text("Open repairs and tickets will show here."))
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.headline)
                            if let description = item.description, !description.isEmpty {
                                Text(description).font(.subheadline).foregroundStyle(NriTheme.slate).lineLimit(2)
                            }
                            HStack {
                                StatusChip(text: item.category)
                                StatusChip(text: item.priority)
                                StatusChip(text: item.status)
                            }
                            if let name = item.assignedEmployeeName {
                                Text("Assigned: \(name)").font(.caption).foregroundStyle(NriTheme.slate)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Service requests")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { items = try await appState.api.serviceRequests().content }
        catch { errorMessage = error.localizedDescription }
    }
}
