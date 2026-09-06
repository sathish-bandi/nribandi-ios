import SwiftUI

enum DashboardMetric: String, Hashable, CaseIterable, Identifiable {
    case properties
    case units
    case occupied
    case vacant
    case toLetBoards
    case openRequests
    case inProgressRequests
    case newEnquiries
    case pendingKyc
    case upcomingInspections

    var id: String { rawValue }

    var title: String {
        switch self {
        case .properties: return "Properties"
        case .units: return "Units"
        case .occupied: return "Occupied"
        case .vacant: return "Vacant"
        case .toLetBoards: return "To-let boards"
        case .openRequests: return "Open requests"
        case .inProgressRequests: return "In progress"
        case .newEnquiries: return "New enquiries"
        case .pendingKyc: return "Pending KYC"
        case .upcomingInspections: return "Upcoming inspections"
        }
    }

    func value(from summary: DashboardSummary) -> String {
        switch self {
        case .properties: return "\(summary.totalProperties)"
        case .units: return "\(summary.totalUnits)"
        case .occupied: return "\(summary.occupiedUnits)"
        case .vacant: return "\(summary.vacantUnits)"
        case .toLetBoards: return "\(summary.unitsWithToLetBoards)"
        case .openRequests: return "\(summary.openServiceRequests)"
        case .inProgressRequests: return "\(summary.inProgressServiceRequests)"
        case .newEnquiries: return "\(summary.newEnquiries)"
        case .pendingKyc: return "\(summary.pendingTenantVerifications)"
        case .upcomingInspections: return "\(summary.upcomingInspections)"
        }
    }

    var accent: Color {
        switch self {
        case .properties: return NriTheme.teal
        case .units: return NriTheme.ink
        case .occupied: return NriTheme.leaf
        case .vacant: return NriTheme.terracotta
        case .toLetBoards: return NriTheme.test
        case .openRequests: return NriTheme.terracotta
        case .inProgressRequests: return NriTheme.teal
        case .newEnquiries: return NriTheme.ink
        case .pendingKyc: return NriTheme.prod
        case .upcomingInspections: return NriTheme.leaf
        }
    }
}

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
                    ContentUnavailableView(
                        "Could not load",
                        systemImage: "wifi.exclamationmark",
                        description: Text(errorMessage)
                    )
                } else if let summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            if summary.totalProperties == 0 && summary.totalUnits == 0 {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("No demo data yet")
                                        .font(.headline)
                                        .foregroundStyle(NriTheme.ink)
                                    Text("The API is connected, but Postgres has no demo rows yet.\n\nRun seed on the backend, then swipe down to refresh.")
                                        .font(.subheadline)
                                        .foregroundStyle(NriTheme.slate)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(NriTheme.sand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }

                            Text("Tap a card to open details")
                                .font(.caption)
                                .foregroundStyle(NriTheme.slate)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                ForEach(DashboardMetric.allCases) { metric in
                                    NavigationLink(value: metric) {
                                        MetricCard(
                                            title: metric.title,
                                            value: metric.value(from: summary),
                                            accent: metric.accent,
                                            showsChevron: true
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityHint("Shows \(metric.title.lowercased()) details")
                                }
                            }
                        }
                        .padding()
                    }
                    .refreshable { await load() }
                }
            }
            .navigationTitle("Dashboard")
            .navigationDestination(for: DashboardMetric.self) { metric in
                DashboardMetricDetailView(metric: metric)
            }
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

struct DashboardMetricDetailView: View {
    @EnvironmentObject private var appState: AppState

    let metric: DashboardMetric

    @State private var properties: [PropertyItem] = []
    @State private var units: [UnitListRow] = []
    @State private var requests: [ServiceRequestItem] = []
    @State private var enquiries: [EnquiryItem] = []
    @State private var inspections: [InspectionItem] = []
    @State private var verifications: [TenantVerificationItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading \(metric.title.lowercased())…")
            } else if let errorMessage, isEmpty {
                ContentUnavailableView(
                    "Could not load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "tray",
                    description: Text("No \(metric.title.lowercased()) right now.")
                )
            } else {
                List {
                    switch metric {
                    case .properties:
                        ForEach(properties) { property in
                            NavigationLink(value: property) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(property.name).font(.headline)
                                    Text(property.locationLine).font(.subheadline).foregroundStyle(NriTheme.slate)
                                    HStack {
                                        StatusChip(text: property.propertyType)
                                        StatusChip(text: property.propertyPurpose)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    case .units, .occupied, .vacant, .toLetBoards:
                        ForEach(units) { row in
                            NavigationLink(value: row.unit.propertyId) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(row.unit.title).font(.headline)
                                    Text(row.propertyName).font(.subheadline).foregroundStyle(NriTheme.slate)
                                    HStack {
                                        StatusChip(text: row.unit.unitType)
                                        StatusChip(text: row.unit.occupancyStatus)
                                        StatusChip(text: row.unit.toLetBoardStatus)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    case .openRequests, .inProgressRequests:
                        ForEach(requests) { item in
                            NavigationLink(value: item) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title).font(.headline)
                                    if let description = item.description, !description.isEmpty {
                                        Text(description).font(.subheadline).foregroundStyle(NriTheme.slate).lineLimit(2)
                                    }
                                    HStack {
                                        StatusChip(text: item.category)
                                        StatusChip(text: item.priority)
                                        StatusChip(text: item.status)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    case .newEnquiries:
                        ForEach(enquiries) { item in
                            VStack(alignment: .leading, spacing: 4) {
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
                            .padding(.vertical, 2)
                        }
                    case .pendingKyc:
                        ForEach(verifications) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.tenantName ?? "Tenant").font(.headline)
                                if !item.locationLine.isEmpty {
                                    Text(item.locationLine).font(.subheadline).foregroundStyle(NriTheme.slate)
                                }
                                if let address = item.permanentAddress, !address.isEmpty {
                                    Text(address).font(.footnote).foregroundStyle(NriTheme.slate)
                                }
                                StatusChip(text: item.status)
                            }
                            .padding(.vertical, 2)
                        }
                    case .upcomingInspections:
                        ForEach(inspections) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.propertyName ?? "Property").font(.headline)
                                if let unit = item.unitNumber {
                                    Text("Unit \(unit)").font(.subheadline).foregroundStyle(NriTheme.slate)
                                }
                                HStack {
                                    StatusChip(text: item.inspectionType)
                                    StatusChip(text: item.status)
                                    if let date = item.inspectionDate { StatusChip(text: date) }
                                }
                                if let inspector = item.inspectorEmployeeName {
                                    Text("Inspector: \(inspector)").font(.caption).foregroundStyle(NriTheme.slate)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: PropertyItem.self) { PropertyDetailView(property: $0) }
        .navigationDestination(for: ServiceRequestItem.self) { item in
            ServiceRequestDetailView(requestId: item.id)
        }
        .navigationDestination(for: UUID.self) { propertyId in
            PropertyDetailLoaderView(propertyId: propertyId)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var isEmpty: Bool {
        switch metric {
        case .properties: return properties.isEmpty
        case .units, .occupied, .vacant, .toLetBoards: return units.isEmpty
        case .openRequests, .inProgressRequests: return requests.isEmpty
        case .newEnquiries: return enquiries.isEmpty
        case .pendingKyc: return verifications.isEmpty
        case .upcomingInspections: return inspections.isEmpty
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            switch metric {
            case .properties:
                properties = try await appState.api.properties().content
            case .units:
                units = try await loadAllUnits()
            case .occupied:
                units = try await loadAllUnits().filter { $0.unit.occupancyStatus == "TENANTED" }
            case .vacant:
                units = try await loadAllUnits().filter { $0.unit.occupancyStatus == "VACANT" }
            case .toLetBoards:
                units = try await loadAllUnits().filter { $0.unit.toLetBoardStatus == "INSTALLED" }
            case .openRequests:
                requests = try await appState.api.serviceRequests(status: "OPEN").content
            case .inProgressRequests:
                requests = try await appState.api.serviceRequests(status: "IN_PROGRESS").content
            case .newEnquiries:
                enquiries = try await appState.api.enquiries().content.filter { $0.status == "NEW" }
            case .pendingKyc:
                verifications = try await appState.api.tenantVerifications(status: "PENDING_REVIEW")
            case .upcomingInspections:
                let today = Self.dayFormatter.string(from: Date())
                inspections = try await appState.api.inspections(size: 100).content.filter {
                    $0.status == "SCHEDULED" && ($0.inspectionDate ?? "0000-01-01") >= today
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func loadAllUnits() async throws -> [UnitListRow] {
        let properties = try await appState.api.properties(size: 100).content
        var rows: [UnitListRow] = []
        for property in properties {
            let propertyUnits = try await appState.api.units(propertyId: property.id)
            rows.append(contentsOf: propertyUnits.map {
                UnitListRow(id: $0.id, propertyName: property.name, unit: $0)
            })
        }
        return rows
    }
}

struct PropertyDetailLoaderView: View {
    @EnvironmentObject private var appState: AppState
    let propertyId: UUID

    @State private var property: PropertyItem?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading property…")
            } else if let property {
                PropertyDetailView(property: property)
            } else {
                ContentUnavailableView(
                    "Could not load",
                    systemImage: "building.2",
                    description: Text(errorMessage ?? "Property not found.")
                )
            }
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                property = try await appState.api.property(id: propertyId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
