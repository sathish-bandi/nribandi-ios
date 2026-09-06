import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var summary: DashboardSummary?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && summary == nil {
                    ProgressView("Loading dashboard…")
                } else if let errorMessage, summary == nil {
                    ContentUnavailableView("Could not load", systemImage: "wifi.exclamationmark", description: Text(errorMessage))
                } else if let summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if summary.totalProperties == 0 && summary.totalUnits == 0 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No demo data yet")
                                        .font(.headline)
                                        .foregroundStyle(NriTheme.ink)
                                    Text("The API is connected, but Postgres has no demo rows yet.\n\nIn rental-property-app on your Mac:\n\n1. ./scripts/local-up.sh\n2. ./scripts/local-seed.sh\n\nOr double-click SEED-ON-MAC.command\n\nThen swipe down to refresh. Login: admin@nribandi.local / Nribandi@123")
                                        .font(.subheadline)
                                        .foregroundStyle(NriTheme.slate)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NriTheme.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                MetricCard(title: "Properties", value: "\(summary.totalProperties)", accent: NriTheme.teal)
                                MetricCard(title: "Units", value: "\(summary.totalUnits)", accent: NriTheme.ink)
                                MetricCard(title: "Occupied", value: "\(summary.occupiedUnits)", accent: NriTheme.leaf)
                                MetricCard(title: "Vacant", value: "\(summary.vacantUnits)", accent: NriTheme.terracotta)
                                MetricCard(title: "To-let boards", value: "\(summary.unitsWithToLetBoards)", accent: NriTheme.test)
                                MetricCard(title: "Open requests", value: "\(summary.openServiceRequests)", accent: NriTheme.terracotta)
                                MetricCard(title: "In progress", value: "\(summary.inProgressServiceRequests)", accent: NriTheme.teal)
                                MetricCard(title: "New enquiries", value: "\(summary.newEnquiries)", accent: NriTheme.ink)
                                MetricCard(title: "Pending KYC", value: "\(summary.pendingTenantVerifications)", accent: NriTheme.prod)
                                MetricCard(title: "Upcoming inspections", value: "\(summary.upcomingInspections)", accent: NriTheme.leaf)
                            }
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) } }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { summary = try await appState.api.dashboardSummary() }
        catch { errorMessage = error.localizedDescription }
    }
}
