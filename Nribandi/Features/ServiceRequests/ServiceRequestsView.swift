import PhotosUI
import SwiftUI

struct ServiceRequestsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var items: [ServiceRequestItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showCreate = false

    private var canRaise: Bool {
        let role = session.user?.role
        return role == .OWNER || role == .TENANT
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && items.isEmpty {
                    ProgressView("Loading requests…")
                } else if let errorMessage, items.isEmpty {
                    ContentUnavailableView {
                        Label("Could not load", systemImage: "wrench.and.screwdriver")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("Try again") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                } else if items.isEmpty {
                    ContentUnavailableView {
                        Label("No service requests", systemImage: "checkmark.seal")
                    } description: {
                        Text(
                            canRaise
                                ? "Raise a repair or maintenance ticket for your property or unit."
                                : "Open repairs and tickets will show here."
                        )
                    } actions: {
                        if canRaise {
                            Button("Raise request") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                } else {
                    // Push-style links avoid SwiftUI double-push under loading conditionals.
                    List(items) { item in
                        NavigationLink {
                            ServiceRequestDetailView(requestId: item.id) { await load() }
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.title).font(.headline)
                                if let description = item.description, !description.isEmpty {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(NriTheme.slate)
                                        .lineLimit(2)
                                }
                                HStack {
                                    StatusChip(text: item.category)
                                    StatusChip(text: item.priority)
                                }
                                Text(item.statusLabel)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NriTheme.terracotta)
                                if let name = item.assignedEmployeeName {
                                    Text("Assigned: \(name)")
                                        .font(.caption)
                                        .foregroundStyle(NriTheme.slate)
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
            .navigationTitle("Service requests")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        if canRaise {
                            Button {
                                showCreate = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                            }
                            .accessibilityLabel("Raise request")
                        }
                        EnvBadge(env: appState.environment)
                    }
                }
            }
            .sheet(isPresented: $showCreate) {
                CreateServiceRequestView {
                    showCreate = false
                    await load()
                }
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
        do {
            // Active tickets uncapped; closed history limited to the newest 10.
            async let activePage = appState.api.serviceRequests(size: 100, excludeStatus: "CLOSED")
            async let closedPage = appState.api.serviceRequests(size: 10, status: "CLOSED")
            let active = try await activePage.content
            let closed = try await closedPage.content
            items = active + closed
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct CreateServiceRequestView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var onCreated: () async -> Void

    @State private var properties: [PropertyItem] = []
    @State private var units: [UnitItem] = []
    @State private var tenancies: [TenancyItem] = []
    @State private var selectedPropertyId: UUID?
    @State private var selectedUnitId: UUID?
    @State private var selectedTenancyId: UUID?
    @State private var category = "PLUMBING"
    @State private var priority = "MEDIUM"
    @State private var titleText = ""
    @State private var descriptionText = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isBootstrapping = true

    private let categories = ["PLUMBING", "ELECTRICAL", "CARPENTRY", "CLEANING", "AC", "PAINTING", "WATER", "OTHER"]
    private let priorities = ["LOW", "MEDIUM", "HIGH", "URGENT"]

    private var isTenant: Bool { session.user?.role == .TENANT }

    var body: some View {
        NavigationStack {
            Form {
                if isBootstrapping {
                    ProgressView("Loading…")
                } else if isTenant {
                    Section("Your unit") {
                        if tenancies.isEmpty {
                            Text("No active tenancy found. Ask your owner/admin to assign a unit.")
                                .foregroundStyle(NriTheme.terracotta)
                        } else {
                            Picker("Tenancy", selection: $selectedTenancyId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(tenancies) { tenancy in
                                    Text(tenancy.label).tag(Optional(tenancy.id))
                                }
                            }
                        }
                    }
                } else {
                    Section("Property") {
                        Picker("Property", selection: $selectedPropertyId) {
                            Text("Select").tag(Optional<UUID>.none)
                            ForEach(properties) { property in
                                Text(property.name).tag(Optional(property.id))
                            }
                        }
                        .onChange(of: selectedPropertyId) { _, newValue in
                            Task { await loadUnits(for: newValue) }
                        }
                        Picker("Unit (optional)", selection: $selectedUnitId) {
                            Text("Whole property / not specific").tag(Optional<UUID>.none)
                            ForEach(units) { unit in
                                Text(unit.title).tag(Optional(unit.id))
                            }
                        }
                    }
                }

                Section("Request") {
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(value.replacingOccurrences(of: "_", with: " ")).tag(value)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(priorities, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Title", text: $titleText)
                    TextField("Describe the issue", text: $descriptionText, axis: .vertical)
                        .lineLimit(4...8)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                    }
                }
            }
            .navigationTitle("Raise request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") { Task { await submit() } }
                        .disabled(isSaving || isBootstrapping)
                }
            }
            .task { await bootstrap() }
        }
    }

    private func bootstrap() async {
        isBootstrapping = true
        defer { isBootstrapping = false }
        do {
            if isTenant {
                tenancies = try await appState.api.myTenancies().filter { $0.active }
                selectedTenancyId = tenancies.first?.id
            } else {
                properties = try await appState.api.properties().content
                selectedPropertyId = properties.first?.id
                await loadUnits(for: selectedPropertyId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadUnits(for propertyId: UUID?) async {
        selectedUnitId = nil
        units = []
        guard let propertyId else { return }
        do {
            units = try await appState.api.units(propertyId: propertyId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTitle.isEmpty {
            errorMessage = "Title is required."
            return
        }
        if trimmedDescription.isEmpty {
            errorMessage = "Describe the issue so staff can act on it."
            return
        }

        let propertyId: UUID
        let unitId: UUID?
        if isTenant {
            guard let tenancy = tenancies.first(where: { $0.id == selectedTenancyId }) else {
                errorMessage = "Select your unit."
                return
            }
            propertyId = tenancy.propertyId
            unitId = tenancy.unitId
        } else {
            guard let selectedPropertyId else {
                errorMessage = "Select a property."
                return
            }
            propertyId = selectedPropertyId
            unitId = selectedUnitId
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let body = CreateServiceRequestBody(
            propertyId: propertyId,
            unitId: unitId,
            category: category,
            title: trimmedTitle,
            description: trimmedDescription,
            priority: priority
        )

        do {
            _ = try await appState.api.createServiceRequest(body)
            await onCreated()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ServiceRequestDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    let requestId: UUID
    var onChanged: (() async -> Void)? = nil

    @State private var item: ServiceRequestItem?
    @State private var history: [ServiceRequestHistoryItem] = []
    @State private var attachments: [ServiceRequestAttachmentItem] = []
    @State private var linkedInvoice: InvoiceItem?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isCancelling = false
    @State private var isUploading = false
    @State private var showCancelConfirm = false
    @State private var showAssign = false
    @State private var showUpdateStatus = false
    @State private var showEstimate = false
    @State private var showPayer = false
    @State private var showWorkCompleted = false
    @State private var photoItem: PhotosPickerItem?

    private var canCancel: Bool {
        guard let item, item.canCancel else { return false }
        let role = session.user?.role
        return role == .OWNER || role == .TENANT || role == .ADMIN
    }

    private var canStaffAct: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE
    }

    private var canAttach: Bool {
        let role = session.user?.role
        return role == .ADMIN || role == .EMPLOYEE || role == .OWNER
    }

    private var canSetEstimate: Bool {
        guard canStaffAct, let item else { return false }
        return ["OPEN", "ASSIGNED", "IN_PROGRESS", "WAITING_FOR_PARTS"].contains(item.status)
            || item.expectedAmount == nil
    }

    private var canSetPayer: Bool {
        guard canStaffAct, let item else { return false }
        return item.expectedAmount != nil
            && !["CLOSED", "CANCELLED", "REJECTED"].contains(item.status)
    }

    private var canMarkWorkCompleted: Bool {
        guard canStaffAct, let item else { return false }
        return item.workCompleted != true
            && !["CLOSED", "CANCELLED", "REJECTED"].contains(item.status)
            && item.payerType != nil
    }

    var body: some View {
        Group {
            if isLoading && item == nil {
                ProgressView("Loading…")
            } else if let errorMessage, item == nil {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "wrench.and.screwdriver")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if let item {
                List {
                    Section("Request") {
                        LabeledContent("Title", value: item.title)
                        if let description = item.description, !description.isEmpty {
                            Text(description)
                        }
                        LabeledContent("Category", value: item.category)
                        LabeledContent("Priority", value: item.priority)
                        LabeledContent("Status", value: item.statusLabel)
                        if item.statusLabel != item.status.replacingOccurrences(of: "_", with: " ") {
                            LabeledContent("System status", value: item.status.replacingOccurrences(of: "_", with: " "))
                        }
                        if let name = item.assignedEmployeeName {
                            LabeledContent("Assigned", value: name)
                        }
                        if let raised = item.raisedByName {
                            LabeledContent("Raised by", value: raised)
                        }
                    }

                    Section("Repair & payment") {
                        if let amount = item.expectedAmount {
                            LabeledContent("Expected amount", value: NriFormat.decimal(amount))
                        } else {
                            Text("Expected repair amount not set yet.")
                                .foregroundStyle(NriTheme.slate)
                        }
                        if let payerType = item.payerType {
                            LabeledContent(
                                "Who pays",
                                value: payerType == "COMPANY"
                                    ? "Company (no payment required)"
                                    : payerType.capitalized
                            )
                        }
                        if let payerName = item.payerName {
                            LabeledContent("Payer", value: payerName)
                        }
                        if let paymentStatus = item.paymentStatus {
                            LabeledContent(
                                "Payment",
                                value: paymentStatus.replacingOccurrences(of: "_", with: " ")
                            )
                        }
                        LabeledContent(
                            "Work",
                            value: item.workCompleted == true ? "Completed" : "Pending"
                        )
                        if let notes = item.payerNotes, !notes.isEmpty {
                            Text(notes).font(.footnote).foregroundStyle(NriTheme.slate)
                        }
                        if let invoice = linkedInvoice {
                            NavigationLink {
                                InvoiceDetailView(invoice: invoice) {
                                    await load()
                                    await onChanged?()
                                }
                            } label: {
                                LabeledContent(
                                    "Invoice",
                                    value: invoice.invoiceNumber ?? "View invoice"
                                )
                            }
                        } else if item.linkedInvoiceId != nil {
                            Text("Invoice linked — pull to refresh if it does not appear.")
                                .font(.footnote)
                                .foregroundStyle(NriTheme.slate)
                        }
                    }

                    if canStaffAct {
                        Section("Staff actions") {
                            Button("Assign employee") { showAssign = true }
                            if canSetEstimate {
                                Button("Set expected repair amount") { showEstimate = true }
                            }
                            if canSetPayer {
                                Button("Confirm who pays") { showPayer = true }
                            }
                            if canMarkWorkCompleted {
                                Button("Mark work completed") { showWorkCompleted = true }
                            }
                            Button("Update status") { showUpdateStatus = true }
                        } footer: {
                            Text(
                                "Flow: estimate → confirm payer (invoice emails owner/tenant, or company = no payment) → mark work done → mark invoice paid → close only when work and payment are both settled."
                            )
                        }
                    }

                    Section {
                        if attachments.isEmpty {
                            Text("No photos attached yet.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            ForEach(attachments) { attachment in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(attachment.originalFilename ?? "Attachment")
                                        .font(.subheadline.weight(.semibold))
                                    if let name = attachment.uploadedByName {
                                        Text("By \(name)")
                                            .font(.caption)
                                            .foregroundStyle(NriTheme.slate)
                                    }
                                }
                            }
                        }
                        if canAttach {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label(isUploading ? "Uploading…" : "Add photo", systemImage: "photo.badge.plus")
                            }
                            .disabled(isUploading)
                            .onChange(of: photoItem) { _, newItem in
                                guard let newItem else { return }
                                Task { await uploadAttachment(newItem) }
                            }
                        }
                    } header: {
                        Text("Attachments")
                    }

                    if !history.isEmpty {
                        Section("Status history") {
                            ForEach(history) { event in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(event.oldStatus ?? "—") → \(event.newStatus)")
                                        .font(.subheadline.weight(.semibold))
                                    if let comments = event.comments, !comments.isEmpty {
                                        Text(comments).font(.footnote).foregroundStyle(NriTheme.slate)
                                    }
                                    HStack {
                                        if let name = event.changedByName {
                                            Text(name)
                                        }
                                        Spacer()
                                        if let timestamp = event.timestamp {
                                            Text(timestamp).font(.caption2)
                                        }
                                    }
                                    .font(.caption)
                                    .foregroundStyle(NriTheme.slate)
                                }
                            }
                        }
                    }

                    if canCancel {
                        Section {
                            Button("Cancel request", role: .destructive) {
                                showCancelConfirm = true
                            }
                            .disabled(isCancelling)
                        } footer: {
                            Text(
                                session.user?.role == .ADMIN
                                    ? "Admins can cancel open or in-progress requests."
                                    : "You can cancel while the request is still open or in progress."
                            )
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                        }
                    }
                }
            }
        }
        .navigationTitle("Request")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssign) {
            AssignEmployeeSheet(title: "Assign request") { employeeId in
                item = try await appState.api.assignServiceRequest(id: requestId, employeeUserId: employeeId)
                history = try await appState.api.serviceRequestHistory(id: requestId)
                await onChanged?()
            }
        }
        .sheet(isPresented: $showUpdateStatus) {
            UpdateServiceRequestStatusSheet(current: item?.status ?? "OPEN") { status, comments in
                item = try await appState.api.updateServiceRequestStatus(
                    id: requestId,
                    UpdateServiceRequestStatusBody(status: status, comments: comments)
                )
                history = try await appState.api.serviceRequestHistory(id: requestId)
                await onChanged?()
            }
        }
        .sheet(isPresented: $showEstimate) {
            SetRepairEstimateSheet { amount, comments in
                item = try await appState.api.setServiceRequestEstimate(
                    id: requestId,
                    SetRepairEstimateBody(expectedAmount: amount, comments: comments)
                )
                history = try await appState.api.serviceRequestHistory(id: requestId)
                await onChanged?()
            }
        }
        .sheet(isPresented: $showPayer) {
            SetServiceRequestPayerSheet { payerType, comments, workCompleted in
                item = try await appState.api.setServiceRequestPayer(
                    id: requestId,
                    SetServiceRequestPayerBody(
                        payerType: payerType,
                        comments: comments,
                        workCompleted: workCompleted
                    )
                )
                history = try await appState.api.serviceRequestHistory(id: requestId)
                await refreshLinkedInvoice()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showWorkCompleted) {
            MarkWorkCompletedSheet { comments in
                item = try await appState.api.markServiceRequestWorkCompleted(
                    id: requestId,
                    comments: comments
                )
                history = try await appState.api.serviceRequestHistory(id: requestId)
                await onChanged?()
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Cancel this service request?",
            isPresented: $showCancelConfirm,
            titleVisibility: .visible
        ) {
            Button("Cancel request", role: .destructive) {
                Task { await cancel() }
            }
            Button("Keep request", role: .cancel) {}
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let detail = appState.api.serviceRequest(id: requestId)
            async let events = appState.api.serviceRequestHistory(id: requestId)
            async let files = appState.api.serviceRequestAttachments(id: requestId)
            item = try await detail
            history = try await events
            attachments = (try? await files) ?? []
            await refreshLinkedInvoice()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLinkedInvoice() async {
        guard let invoiceId = item?.linkedInvoiceId else {
            linkedInvoice = nil
            return
        }
        linkedInvoice = try? await appState.api.invoice(id: invoiceId)
    }

    private func cancel() async {
        isCancelling = true
        errorMessage = nil
        defer { isCancelling = false }
        do {
            item = try await appState.api.cancelServiceRequest(id: requestId)
            history = try await appState.api.serviceRequestHistory(id: requestId)
            await onChanged?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadAttachment(_ pickerItem: PhotosPickerItem) async {
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            photoItem = nil
        }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read the selected photo."
                return
            }
            let mime = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let uploaded = try await appState.api.uploadServiceRequestAttachment(
                id: requestId,
                fileData: data,
                fileName: "sr-\(UUID().uuidString.prefix(8)).jpg",
                mimeType: mime
            )
            attachments.insert(uploaded, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AssignEmployeeSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let title: String
    var onAssign: (UUID) async throws -> Void

    @State private var employees: [ManagedUserItem] = []
    @State private var selectedEmployeeId: UUID?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Form {
                if isLoading {
                    ProgressView("Loading employees…")
                } else {
                    Section("Employee") {
                        if employees.isEmpty {
                            Text("No active employees found.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            Picker("Assign to", selection: $selectedEmployeeId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(employees) { employee in
                                    Text(employee.fullName).tag(Optional(employee.id))
                                }
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign") { Task { await save() } }
                        .disabled(isSaving || selectedEmployeeId == nil)
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            employees = try await appState.api.users(role: "EMPLOYEE", size: 100).content.filter { $0.active }
            selectedEmployeeId = employees.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard let selectedEmployeeId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onAssign(selectedEmployeeId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UpdateServiceRequestStatusSheet: View {
    @Environment(\.dismiss) private var dismiss

    let current: String
    var onSave: (String, String?) async throws -> Void

    @State private var status: ServiceRequestStatusOption
    @State private var comments = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(current: String, onSave: @escaping (String, String?) async throws -> Void) {
        self.current = current
        self.onSave = onSave
        _status = State(initialValue: ServiceRequestStatusOption(rawValue: current) ?? .OPEN)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Status", selection: $status) {
                        ForEach(ServiceRequestStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField("Comments (optional)", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
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
        let trimmed = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onSave(status.rawValue, trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetRepairEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (Decimal, String?) async throws -> Void

    @State private var amountText = ""
    @State private var comments = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Expected amount (₹)", text: $amountText)
                        .keyboardType(.decimalPad)
                    TextField("Comments (optional)", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("Sets the request to In Progress so you can confirm who pays next.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Repair estimate")
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
        guard let amount = Decimal(string: amountText.trimmingCharacters(in: .whitespacesAndNewlines)),
              amount > 0
        else {
            errorMessage = "Enter a valid expected amount greater than zero."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onSave(amount, trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SetServiceRequestPayerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (String, String?, Bool) async throws -> Void

    @State private var payerType: ServiceRequestPayerTypeOption = .OWNER
    @State private var comments = ""
    @State private var workCompleted = false
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Who pays", selection: $payerType) {
                        ForEach(ServiceRequestPayerTypeOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Toggle("Work already completed", isOn: $workCompleted)
                    TextField(
                        payerType == .COMPANY
                            ? "Comments (required for company pay)"
                            : "Comments (optional)",
                        text: $comments,
                        axis: .vertical
                    )
                    .lineLimit(3...8)
                } footer: {
                    Text(
                        payerType == .COMPANY
                            ? "No invoice is created. Status becomes No payment required."
                            : "An invoice is created automatically in the payer’s name and emailed to them."
                    )
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Confirm payer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        let trimmed = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        if payerType == .COMPANY && trimmed.isEmpty {
            errorMessage = "Add comments explaining why the company covers this work."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await onSave(payerType.rawValue, trimmed.isEmpty ? nil : trimmed, workCompleted)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MarkWorkCompletedSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (String?) async throws -> Void

    @State private var comments = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Comments (optional)", text: $comments, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text(
                        "If payment is still pending, the request stays open with a clear payment-pending status until the invoice is marked paid."
                    )
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Work completed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Mark done") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = comments.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onSave(trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
