import SwiftUI

struct InvoicesView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var items: [InvoiceItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false
    var embedsInParentNavigation = false

    private var canCreate: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading invoices…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "doc.text")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if items.isEmpty {
                ContentUnavailableView {
                    Label("No invoices", systemImage: "doc.text")
                } description: {
                    Text("Create an invoice against a service request.")
                } actions: {
                    if canCreate {
                        Button("Create invoice") { showCreate = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List(items) { item in
                    NavigationLink {
                        InvoiceDetailView(invoice: item) { await load() }
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.invoiceNumber ?? "Draft invoice").font(.headline)
                            if let total = item.totalAmount {
                                Text(verbatim: "Total \(NriFormat.decimal(total))").font(.subheadline).foregroundStyle(NriTheme.slate)
                            }
                            HStack {
                                StatusChip(text: item.status)
                                if let date = item.invoiceDate { StatusChip(text: date) }
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
        .navigationTitle("Invoices")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    if canCreate {
                        Button { showCreate = true } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                        .accessibilityLabel("Create invoice")
                    }
                    if !embedsInParentNavigation {
                        EnvBadge(env: appState.environment)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            CreateInvoiceView {
                showCreate = false
                await load()
            }
            .environmentObject(appState)
        }
        .task { await load() }
        .modifier(OpsOptionalNavigationStack(enabled: !embedsInParentNavigation))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await appState.api.invoices(size: 100).content
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct InvoiceDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var invoice: InvoiceItem
    var onChanged: () async -> Void

    @State private var errorMessage: String?
    @State private var isWorking = false

    init(invoice: InvoiceItem, onChanged: @escaping () async -> Void) {
        _invoice = State(initialValue: invoice)
        self.onChanged = onChanged
    }

    private var isAdmin: Bool { session.user?.role == .ADMIN }
    private var isStaff: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    var body: some View {
        List {
            Section("Invoice") {
                LabeledContent("Number", value: invoice.invoiceNumber ?? "—")
                LabeledContent("Date", value: invoice.invoiceDate ?? "—")
                LabeledContent("Status", value: invoice.status)
                if let billedTo = invoice.billedToName {
                    LabeledContent(
                        "Billed to",
                        value: invoice.billedToRole.map { "\(billedTo) (\($0))" } ?? billedTo
                    )
                }
                if let tax = invoice.tax { LabeledContent("Tax", value: NriFormat.decimal(tax)) }
                if let discount = invoice.discount { LabeledContent("Discount", value: NriFormat.decimal(discount)) }
                if let total = invoice.totalAmount { LabeledContent("Total", value: NriFormat.decimal(total)) }
            }

            if let lines = invoice.items, !lines.isEmpty {
                Section("Line items") {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(line.itemDescription).font(.subheadline.weight(.semibold))
                            Text(verbatim: "Qty \(NriFormat.decimal(line.quantity)) × \(NriFormat.decimal(line.unitPrice))")
                                .font(.footnote)
                                .foregroundStyle(NriTheme.slate)
                        }
                    }
                }
            }

            if invoice.status == "APPROVED" || invoice.status == "SUBMITTED" {
                CompanyPaymentInstructionsSection()
            }

            if isStaff {
                Section("Actions") {
                    if invoice.status == "DRAFT" {
                        Button("Submit for approval") { Task { await run { try await appState.api.submitInvoice(id: invoice.id) } } }
                            .disabled(isWorking)
                    }
                    if isAdmin && invoice.status == "SUBMITTED" {
                        Button("Approve") { Task { await run { try await appState.api.approveInvoice(id: invoice.id) } } }
                            .disabled(isWorking)
                        Button("Reject", role: .destructive) { Task { await run { try await appState.api.rejectInvoice(id: invoice.id) } } }
                            .disabled(isWorking)
                    }
                    if (isAdmin || isStaff) && invoice.status == "APPROVED" {
                        Button("Mark paid") { Task { await run { try await appState.api.markInvoicePaid(id: invoice.id) } } }
                            .disabled(isWorking)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func run(_ action: () async throws -> InvoiceItem) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            invoice = try await action()
            await onChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateInvoiceView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var onCreated: () async -> Void

    @State private var requests: [ServiceRequestItem] = []
    @State private var selectedRequestId: UUID?
    @State private var invoiceDate = Date()
    @State private var taxText = "0"
    @State private var discountText = "0"
    @State private var lineDescription = ""
    @State private var lineQuantityText = "1"
    @State private var lineUnitPriceText = ""
    @State private var lines: [DraftInvoiceLine] = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isBootstrapping = true

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    var body: some View {
        NavigationStack {
            Form {
                if isBootstrapping {
                    ProgressView("Loading service requests…")
                } else {
                    Section("Service request") {
                        if requests.isEmpty {
                            Text("No service requests available.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            Picker("Request", selection: $selectedRequestId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(requests) { request in
                                    Text(request.title).tag(Optional(request.id))
                                }
                            }
                        }
                        DatePicker("Invoice date", selection: $invoiceDate, displayedComponents: .date)
                        TextField("Tax", text: $taxText).keyboardType(.decimalPad)
                        TextField("Discount", text: $discountText).keyboardType(.decimalPad)
                    }

                    Section("Add line item") {
                        TextField("Description", text: $lineDescription)
                        TextField("Quantity", text: $lineQuantityText).keyboardType(.decimalPad)
                        TextField("Unit price", text: $lineUnitPriceText).keyboardType(.decimalPad)
                        Button("Add line") { addLine() }
                            .disabled(!canAddLine)
                    }

                    if !lines.isEmpty {
                        Section("Lines") {
                            ForEach(lines) { line in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(line.itemDescription)
                                        Text(verbatim: "\(NriFormat.decimal(line.quantity)) × \(NriFormat.decimal(line.unitPrice))")
                                            .font(.caption)
                                            .foregroundStyle(NriTheme.slate)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        lines.removeAll { $0.id == line.id }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Create invoice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await submit() } }
                        .disabled(isSaving || selectedRequestId == nil || lines.isEmpty)
                }
            }
            .task { await bootstrap() }
        }
    }

    private var canAddLine: Bool {
        !lineDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Decimal(string: lineQuantityText) != nil
            && Decimal(string: lineUnitPriceText) != nil
    }

    private func addLine() {
        guard let quantity = Decimal(string: lineQuantityText),
              let unitPrice = Decimal(string: lineUnitPriceText)
        else { return }
        lines.append(
            DraftInvoiceLine(
                itemDescription: lineDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: quantity,
                unitPrice: unitPrice
            )
        )
        lineDescription = ""
        lineQuantityText = "1"
        lineUnitPriceText = ""
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            requests = try await appState.api.serviceRequests(size: 100).content
            selectedRequestId = requests.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let selectedRequestId,
              let tax = Decimal(string: taxText),
              let discount = Decimal(string: discountText)
        else {
            errorMessage = "Enter valid tax and discount amounts."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.createInvoice(
                CreateInvoiceBody(
                    serviceRequestId: selectedRequestId,
                    invoiceDate: Self.dayFormatter.string(from: invoiceDate),
                    tax: tax,
                    discount: discount,
                    items: lines.map { $0.asBody }
                )
            )
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
