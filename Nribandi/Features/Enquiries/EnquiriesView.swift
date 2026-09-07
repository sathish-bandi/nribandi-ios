import SwiftUI

struct EnquiriesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var items: [EnquiryItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    var embedsInParentNavigation = false

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading enquiries…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "bubble.left")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if items.isEmpty {
                ContentUnavailableView(
                    "No enquiries",
                    systemImage: "tray",
                    description: Text("WhatsApp and manual leads will appear here.")
                )
            } else {
                // Push-style links avoid SwiftUI double-push under loading conditionals.
                List(items) { item in
                    NavigationLink {
                        EnquiryDetailView(enquiryId: item.id) { await load() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.customerName).font(.headline)
                            Text(item.mobileNumber).font(.subheadline.monospaced()).foregroundStyle(NriTheme.slate)
                            if let locality = item.requestedLocality {
                                Text(locality).font(.subheadline)
                            }
                            HStack {
                                StatusChip(text: item.source)
                                StatusChip(text: item.status)
                                if let unit = item.requestedUnitType {
                                    StatusChip(text: UnitTypeDisplay.title(for: unit), emphasized: true)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.insetGrouped)
                .nriScrollable()
                .nriPhoneScrollInsets()
                .refreshable { await load() }
            }
        }
        .navigationTitle("Enquiries")
        .toolbar {
            if !embedsInParentNavigation {
                ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) }
            }
        }
        .task { await load() }
        .modifier(OptionalNavigationStack(enabled: !embedsInParentNavigation))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do { items = try await appState.api.enquiries().content }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct OptionalNavigationStack: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            NavigationStack { content }
        } else {
            content
        }
    }
}

struct EnquiryDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    let enquiryId: UUID
    var onChanged: (() async -> Void)? = nil

    @State private var item: EnquiryItem?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showAssign = false
    @State private var showStatus = false

    private var canStaffAct: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    var body: some View {
        Group {
            if isLoading && item == nil {
                ProgressView("Loading…")
            } else if let errorMessage, item == nil {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "bubble.left")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if let item {
                List {
                    Section("Lead") {
                        LabeledContent("Name", value: item.customerName)
                        LabeledContent("Mobile", value: item.mobileNumber)
                        if let whatsapp = item.whatsappNumber {
                            LabeledContent("WhatsApp", value: whatsapp)
                        }
                        if let locality = item.requestedLocality {
                            LabeledContent("Locality", value: locality)
                        }
                        if let unit = item.requestedUnitType {
                            LabeledContent("Unit type", value: UnitTypeDisplay.title(for: unit))
                        }
                        if let budget = item.budget {
                            LabeledContent("Budget", value: NriFormat.decimal(budget))
                        }
                        if let message = item.message, !message.isEmpty {
                            Text(message)
                        }
                        LabeledContent("Source", value: item.source)
                        LabeledContent("Status", value: item.status)
                        if let name = item.assignedEmployeeName {
                            LabeledContent("Assigned", value: name)
                        }
                    }

                    if canStaffAct {
                        Section("Actions") {
                            Button("Update status") { showStatus = true }
                            Button("Assign employee") { showAssign = true }
                        }
                    }

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                    }
                }
            }
        }
        .navigationTitle("Enquiry")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssign) {
            AssignEmployeeSheet(title: "Assign enquiry") { employeeId in
                item = try await appState.api.assignEnquiry(id: enquiryId, employeeUserId: employeeId)
                await onChanged?()
            }
        }
        .sheet(isPresented: $showStatus) {
            UpdateEnquiryStatusSheet(current: item?.status ?? "NEW") { status in
                item = try await appState.api.updateEnquiryStatus(id: enquiryId, status: status)
                await onChanged?()
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            item = try await appState.api.enquiry(id: enquiryId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UpdateEnquiryStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let current: String
    var onSave: (String) async throws -> Void

    @State private var status: EnquiryStatusOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(current: String, onSave: @escaping (String) async throws -> Void) {
        self.current = current
        self.onSave = onSave
        _status = State(initialValue: EnquiryStatusOption(rawValue: current) ?? .NEW)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Status", selection: $status) {
                        ForEach(EnquiryStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Update status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSave(status.rawValue)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
