import SwiftUI

enum OpsSegment: String, CaseIterable, Identifiable {
    case enquiries
    case inspections
    case invoices
    case kyc

    var id: String { rawValue }

    var title: String {
        switch self {
        case .enquiries: return "Enquiries"
        case .inspections: return "Inspections"
        case .invoices: return "Invoices"
        case .kyc: return "KYC"
        }
    }
}

/// Staff ops hub — keeps tab count reasonable while exposing Enquiries, Inspections, Invoices, and KYC.
struct OpsHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var segment: OpsSegment = .enquiries

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Ops", selection: $segment) {
                    ForEach(OpsSegment.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    switch segment {
                    case .enquiries:
                        EnquiriesView(embedsInParentNavigation: true)
                    case .inspections:
                        InspectionsView(embedsInParentNavigation: true)
                    case .invoices:
                        InvoicesView(embedsInParentNavigation: true)
                    case .kyc:
                        KycReviewListView(embedsInParentNavigation: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle("Ops")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    EnvBadge(env: appState.environment)
                }
            }
        }
    }
}
