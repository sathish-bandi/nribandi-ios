import SwiftUI

struct PropertiesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var items: [PropertyItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false

    private var canManageProperties: Bool {
        session.user?.role == .ADMIN
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading properties…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load", systemImage: "building.2")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("No properties", systemImage: "building.2")
                    } description: {
                        Text(canManageProperties ? "Tap + to add a property." : "Nothing visible for this account yet.")
                    } actions: {
                        if canManageProperties {
                            Button("Add property") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    // Push-style links avoid SwiftUI double-push when list chrome swaps with loading/empty.
                    ScrollView(.vertical) {
                        VStack(spacing: 12) {
                            ForEach(items) { property in
                                NavigationLink {
                                    PropertyDetailView(property: property) { await load() }
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(property.name).font(.headline).foregroundStyle(NriTheme.ink)
                                        Text(property.locationLine).font(.subheadline).foregroundStyle(NriTheme.slate)
                                        HStack {
                                            StatusChip(text: property.propertyType)
                                            StatusChip(text: property.propertyPurpose)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(14)
                                    .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .strokeBorder(NriTheme.sage.opacity(0.35), lineWidth: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .padding(.bottom, 24)
                    }
                    .background(NriTheme.pageBackground.ignoresSafeArea())
                    .nriScrollable()
                    .nriPhoneScrollInsets()
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Properties")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if canManageProperties {
                            Button { showCreate = true } label: { Image(systemName: "plus") }
                        }
                        EnvBadge(env: appState.environment)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                PropertyFormView(mode: .create) { _ in await load() }
                    .environmentObject(appState)
                    .environmentObject(session)
            }
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
