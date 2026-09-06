import SwiftUI

struct EnquiriesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [EnquiryItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading enquiries…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView("Could not load", systemImage: "bubble.left", description: Text(errorMessage))
                } else if items.isEmpty {
                    ContentUnavailableView("No enquiries", systemImage: "tray", description: Text("WhatsApp and manual leads will appear here."))
                } else {
                    List(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.customerName).font(.headline)
                            Text(item.mobileNumber).font(.subheadline.monospaced()).foregroundStyle(NriTheme.slate)
                            if let locality = item.requestedLocality {
                                Text(locality).font(.subheadline)
                            }
                            HStack {
                                StatusChip(text: item.source)
                                StatusChip(text: item.status)
                                if let unit = item.requestedUnitType { StatusChip(text: unit) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listStyle(.plain)
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Enquiries")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { items = try await appState.api.enquiries().content }
        catch { errorMessage = error.localizedDescription }
    }
}
