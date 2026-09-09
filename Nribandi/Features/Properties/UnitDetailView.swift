import SwiftUI
import UniformTypeIdentifiers

struct UnitDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    @State private var unit: UnitItem
    let propertyName: String
    var onChanged: (() async -> Void)? = nil

    @State private var tenancies: [TenancyItem] = []
    @State private var inspections: [InspectionDetailItem] = []
    @State private var enquiries: [EnquiryItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showAssignTenancy = false
    @State private var showUpdateStatus = false
    @State private var showEditDefinition = false
    @State private var endingTenancy: TenancyItem?
    @State private var showAddEnquiry = false
    @State private var editingEnquiry: EnquiryItem?
    @State private var showAgreementMeta = false
    @State private var showAgreementImporter = false

    init(unit: UnitItem, propertyName: String, onChanged: (() async -> Void)? = nil) {
        _unit = State(initialValue: unit)
        self.propertyName = propertyName
        self.onChanged = onChanged
    }

    private var role: UserRole? { session.user?.role }

    private var canUpdateStatus: Bool {
        role == .ADMIN || role == .OWNER || role == .EMPLOYEE
    }

    private var canManageTenancy: Bool {
        role == .ADMIN || role == .OWNER
    }

    private var canEditDefinition: Bool {
        role == .ADMIN
    }

    private var canViewEnquiries: Bool {
        (role == .ADMIN || role == .OWNER || role == .EMPLOYEE) && unit.isVacant
    }

    private var canManageEnquiries: Bool {
        role == .ADMIN || role == .EMPLOYEE
    }

    private var isTenantViewer: Bool {
        role == .TENANT
    }

    private var activeTenancy: TenancyItem? {
        tenancies.first(where: \.active) ?? tenancies.first
    }

    private var currentTenantSummary: CurrentTenancySummary? {
        unit.currentTenancy
    }

    var body: some View {
        List {
            occupancySection
            if !isTenantViewer {
                tenantSection
            }
            agreementSection
            inspectionsSection
            if canViewEnquiries {
                enquiriesSection
            }
            if !isTenantViewer {
                tenancyHistorySection
            } else {
                tenantOwnTenancySection
            }
            if !isTenantViewer {
                actionsSection
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                }
            }
        }
        .listStyle(.insetGrouped)
        .nriScrollable()
        .nriPhoneScrollInsets()
        .navigationTitle(unit.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAssignTenancy) {
            AssignTenancySheet(unitId: unit.id) {
                await load()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showUpdateStatus) {
            UpdateUnitStatusSheet(unit: unit) { updated in
                unit = updated
                Task {
                    await load()
                    await onChanged?()
                }
            }
        }
        .sheet(isPresented: $showEditDefinition) {
            EditUnitDefinitionSheet(unit: unit) { updated in
                unit = updated
                Task { await onChanged?() }
            }
        }
        .sheet(item: $endingTenancy) { tenancy in
            EndTenancySheet(tenancyId: tenancy.id) {
                await load()
                await onChanged?()
            }
        }
        .sheet(isPresented: $showAddEnquiry) {
            UnitEnquiryFormSheet(unitId: unit.id, existing: nil) {
                await load()
            }
        }
        .sheet(item: $editingEnquiry) { enquiry in
            UnitEnquiryFormSheet(unitId: unit.id, existing: enquiry) {
                await load()
            }
        }
        .sheet(isPresented: $showAgreementMeta) {
            if let tenancy = activeTenancy {
                AgreementMetaSheet(tenancy: tenancy) {
                    await load()
                }
            }
        }
        .fileImporter(
            isPresented: $showAgreementImporter,
            allowedContentTypes: [.pdf, .image],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleAgreementImport(result) }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    @ViewBuilder
    private var occupancySection: some View {
        Section("Unit") {
            LabeledContent("Property", value: propertyName)
            LabeledContent("Unit", value: unit.unitNumber)
            if let block = unit.blockNumber {
                LabeledContent("Block", value: block)
            }
            if let floor = unit.floorNumber {
                LabeledContent("Floor", value: "\(floor)")
            }
            StatusChip(text: UnitTypeDisplay.title(for: unit.unitType), emphasized: true)
            HStack {
                StatusChip(text: unit.occupancyStatus)
                StatusChip(text: unit.toLetBoardStatus)
            }
            Text(unit.isTenanted ? "Tenanted — rental agreement in place" : "Vacant / available for to-let")
                .font(.footnote)
                .foregroundStyle(NriTheme.slate)
        }
    }

    @ViewBuilder
    private var tenantSection: some View {
        Section("Current tenant") {
            if isLoading {
                ProgressView()
            } else if let tenant = currentTenantSummary {
                NavigationLink {
                    TenantPersonDetailView(userId: tenant.tenantUserId, fallbackName: tenant.tenantName)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tenant.tenantName ?? "Tenant")
                            .font(.subheadline.weight(.semibold))
                        if let email = tenant.tenantEmail, !email.isEmpty {
                            Text(email).font(.footnote).foregroundStyle(NriTheme.slate)
                        }
                        if let phone = tenant.tenantPhone, !phone.isEmpty {
                            Text(phone).font(.footnote.monospaced()).foregroundStyle(NriTheme.slate)
                        }
                        Text("In residence \(tenant.durationLabel) · since \(tenant.moveInDate ?? "—")")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.slate)
                    }
                }
            } else if unit.isVacant {
                Text("No active tenant. Unit is vacant.")
                    .foregroundStyle(NriTheme.slate)
            } else {
                Text("No tenant details loaded.")
                    .foregroundStyle(NriTheme.slate)
            }
        }
    }

    @ViewBuilder
    private var agreementSection: some View {
        if unit.isTenanted, let tenancy = activeTenancy ?? tenancies.first(where: \.active) {
            Section {
                if tenancy.hasRentalAgreement == true, let urlString = tenancy.agreementDownloadUrl,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(tenancy.agreementFilename ?? "Open rental agreement PDF", systemImage: "doc.richtext")
                    }
                } else {
                    Text("No rental agreement uploaded yet.")
                        .foregroundStyle(NriTheme.slate)
                }
                if let start = tenancy.agreementStartDate {
                    LabeledContent("Agreement start", value: start)
                }
                if let end = tenancy.agreementEndDate {
                    LabeledContent("Agreement end", value: end)
                    if tenancy.agreementExpiringSoon {
                        Text("Renewal reminder window — agreement ends within 30 days.")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.terracotta)
                    }
                }
                LabeledContent("Tenancy duration", value: tenancy.durationLabel)
                if canManageTenancy {
                    Button("Upload / replace agreement") { showAgreementImporter = true }
                    Button("Set agreement dates") { showAgreementMeta = true }
                }
            } header: {
                Text("Rental agreement")
            } footer: {
                Text("Owner, admin, and the current tenant can open the PDF. Expiry reminders go to owner, tenant, and ops.")
            }
        }
    }

    @ViewBuilder
    private var inspectionsSection: some View {
        Section {
            if isLoading {
                ProgressView()
            } else if inspections.isEmpty {
                Text("No recent inspections for this unit.")
                    .foregroundStyle(NriTheme.slate)
            } else {
                ForEach(inspections) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.inspectionType.replacingOccurrences(of: "_", with: " "))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            StatusChip(text: item.status)
                        }
                        Text("\(item.inspectionDate ?? "—") · \(item.inspectorEmployeeName ?? "Inspector")")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.slate)
                        if let notes = item.notes, !notes.isEmpty {
                            Text(notes).font(.footnote)
                        }
                        if let attachments = item.attachments, !attachments.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(attachments) { attachment in
                                        InspectionMediaThumb(attachment: attachment)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Inspections")
        } footer: {
            Text(inspectionFooter)
        }
    }

    private var inspectionFooter: String {
        switch role {
        case .OWNER:
            return "Showing the last 2 inspections with photos/videos."
        case .TENANT:
            return "Only inspections from your move-in date onward are shown (not prior tenants)."
        default:
            return "Showing the latest inspections with media (up to 3)."
        }
    }

    @ViewBuilder
    private var enquiriesSection: some View {
        Section {
            if enquiries.isEmpty {
                Text("No to-let enquiries yet.")
                    .foregroundStyle(NriTheme.slate)
            } else {
                ForEach(enquiries) { enquiry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(enquiry.customerName).font(.subheadline.weight(.semibold))
                            Spacer()
                            StatusChip(text: enquiry.status)
                        }
                        Text(enquiry.mobileNumber)
                            .font(.footnote.monospaced())
                            .foregroundStyle(NriTheme.slate)
                        if let message = enquiry.message, !message.isEmpty {
                            Text(message).font(.footnote)
                        }
                        if canManageEnquiries {
                            HStack {
                                Button("Edit") { editingEnquiry = enquiry }
                                Button("Delete", role: .destructive) {
                                    Task { await deleteEnquiry(enquiry) }
                                }
                            }
                            .font(.footnote)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            if canManageEnquiries {
                Button("Add to-let enquiry") { showAddEnquiry = true }
                    .disabled(enquiries.count >= 10)
            }
        } header: {
            Text("To-let enquiries")
        } footer: {
            Text("Visible while the unit is vacant. Hidden once tenanted. Max 10 leads.")
        }
    }

    @ViewBuilder
    private var tenancyHistorySection: some View {
        Section("Tenancy history") {
            if isLoading {
                ProgressView()
            } else if tenancies.isEmpty {
                Text("No tenancies yet.")
                    .foregroundStyle(NriTheme.slate)
            } else {
                ForEach(tenancies) { tenancy in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink {
                            TenantPersonDetailView(userId: tenancy.tenantUserId, fallbackName: tenancy.tenantName)
                        } label: {
                            Text(tenancy.tenantName ?? "Tenant")
                                .font(.subheadline.weight(.semibold))
                        }
                        Text("In: \(tenancy.moveInDate ?? "—") · Out: \(tenancy.moveOutDate ?? "—") · \(tenancy.durationLabel)")
                            .font(.footnote)
                            .foregroundStyle(NriTheme.slate)
                        StatusChip(text: tenancy.active ? "ACTIVE" : "ENDED")
                        if canManageTenancy, tenancy.active {
                            Button("End tenancy") { endingTenancy = tenancy }
                                .foregroundStyle(NriTheme.terracotta)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if canManageTenancy {
            Section {
                Button("Assign tenant") { showAssignTenancy = true }
                    .disabled(unit.isTenanted || activeTenancy?.active == true)
            } footer: {
                if unit.isTenanted {
                    Text("End the active tenancy before assigning another tenant.")
                }
            }
        }
        if canEditDefinition {
            Section {
                Button("Edit unit number / BHK") { showEditDefinition = true }
            } footer: {
                Text("Admins can correct the unit number or BHK layout.")
            }
        }
        if canUpdateStatus {
            Section {
                Button("Update occupancy / to-let board") { showUpdateStatus = true }
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let refreshedUnit = appState.api.unit(id: unit.id)
            async let loadedTenancies = appState.api.tenancies(unitId: unit.id)
            async let loadedInspections = appState.api.unitInspections(unitId: unit.id)
            unit = try await refreshedUnit
            tenancies = try await loadedTenancies
            inspections = try await loadedInspections
            if canViewEnquiries || unit.isVacant {
                if role == .ADMIN || role == .OWNER || role == .EMPLOYEE {
                    enquiries = try await appState.api.unitEnquiries(unitId: unit.id)
                } else {
                    enquiries = []
                }
            } else {
                enquiries = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteEnquiry(_ enquiry: EnquiryItem) async {
        do {
            try await appState.api.deleteEnquiry(id: enquiry.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleAgreementImport(_ result: Result<[URL], Error>) async {
        guard let tenancy = activeTenancy ?? tenancies.first(where: \.active) else { return }
        do {
            let urls = try result.get()
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                errorMessage = "Could not read the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            let data = try Data(contentsOf: url)
            let name = url.lastPathComponent
            let mime: String
            if name.lowercased().hasSuffix(".pdf") {
                mime = "application/pdf"
            } else if name.lowercased().hasSuffix(".png") {
                mime = "image/png"
            } else {
                mime = "image/jpeg"
            }
            _ = try await appState.api.uploadTenancyAgreement(
                id: tenancy.id,
                fileData: data,
                fileName: name,
                mimeType: mime
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tenant person (tap from unit)

struct TenantPersonDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    let userId: UUID
    let fallbackName: String?

    @State private var user: ManagedUserItem?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading && user == nil {
                ProgressView("Loading tenant…")
            } else if let user {
                UserDetailView(user: user, onChanged: { await reload() })
            } else {
                List {
                    Section("Tenant") {
                        LabeledContent("Name", value: fallbackName ?? "—")
                        LabeledContent("User id", value: userId.uuidString.lowercased())
                    }
                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                        }
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        // Own profile for tenants (and anyone viewing themselves).
        if session.user?.id == userId, let me = session.user {
            user = ManagedUserItem(
                id: me.id,
                email: me.email,
                phone: me.phone,
                fullName: me.fullName,
                role: me.role,
                active: me.active,
                createdAt: me.createdAt
            )
            errorMessage = nil
            return
        }
        do {
            user = try await appState.api.user(id: userId)
            errorMessage = nil
        } catch {
            do {
                let page = try await appState.api.users(role: "TENANT", size: 100)
                user = page.content.first(where: { $0.id == userId })
                if user == nil {
                    errorMessage = error.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct InspectionMediaThumb: View {
    let attachment: InspectionAttachmentItem

    var body: some View {
        Group {
            if let urlString = attachment.downloadUrl, let url = URL(string: urlString) {
                if attachment.isImage {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        default:
                            ProgressView().frame(width: 72, height: 72)
                        }
                    }
                    .frame(width: 88, height: 72)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Link(destination: url) {
                        Label(attachment.isVideo ? "Video" : (attachment.originalFilename ?? "File"),
                              systemImage: attachment.isVideo ? "video.fill" : "doc")
                            .font(.caption)
                            .padding(8)
                            .frame(width: 88, height: 72)
                            .background(NriTheme.sand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            } else {
                placeholder
            }
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .frame(width: 88, height: 72)
            .background(NriTheme.sand, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct UnitEnquiryFormSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unitId: UUID
    let existing: EnquiryItem?
    var onSaved: () async -> Void

    @State private var customerName = ""
    @State private var mobile = ""
    @State private var whatsapp = ""
    @State private var locality = ""
    @State private var message = ""
    @State private var status: EnquiryStatusOption = .NEW
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Lead") {
                    TextField("Customer name", text: $customerName)
                    TextField("Mobile", text: $mobile)
                        .keyboardType(.phonePad)
                    TextField("WhatsApp (optional)", text: $whatsapp)
                        .keyboardType(.phonePad)
                    TextField("Locality", text: $locality)
                    TextField("Message", text: $message, axis: .vertical)
                        .lineLimit(3...6)
                }
                if existing != nil {
                    Section("Status") {
                        Picker("Status", selection: $status) {
                            ForEach(EnquiryStatusOption.allCases) { option in
                                Text(option.title).tag(option)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle(existing == nil ? "Add enquiry" : "Edit enquiry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                if let existing {
                    customerName = existing.customerName
                    mobile = existing.mobileNumber
                    whatsapp = existing.whatsappNumber ?? ""
                    locality = existing.requestedLocality ?? ""
                    message = existing.message ?? ""
                    status = EnquiryStatusOption(rawValue: existing.status) ?? .NEW
                }
            }
        }
    }

    private func save() async {
        let name = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "Customer name is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let existing {
                _ = try await appState.api.updateEnquiry(
                    id: existing.id,
                    UpdateEnquiryBody(
                        customerName: name,
                        mobileNumber: mobile,
                        whatsappNumber: whatsapp.isEmpty ? nil : whatsapp,
                        requestedLocality: locality.isEmpty ? nil : locality,
                        message: message.isEmpty ? nil : message,
                        status: status.rawValue
                    )
                )
            } else {
                _ = try await appState.api.createUnitEnquiry(
                    unitId: unitId,
                    CreateUnitEnquiryBody(
                        customerName: name,
                        mobileNumber: mobile.isEmpty ? nil : mobile,
                        whatsappNumber: whatsapp.isEmpty ? nil : whatsapp,
                        requestedLocality: locality.isEmpty ? nil : locality,
                        requestedUnitType: nil,
                        budget: nil,
                        message: message.isEmpty ? nil : message
                    )
                )
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AgreementMetaSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let tenancy: TenancyItem
    var onSaved: () async -> Void

    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(60 * 60 * 24 * 330)
    @State private var errorMessage: String?
    @State private var isSaving = false

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
                Section {
                    DatePicker("Start", selection: $startDate, displayedComponents: .date)
                    DatePicker("End", selection: $endDate, displayedComponents: .date)
                } footer: {
                    Text("Reminders fire when the end date is within 30 days.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Agreement dates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear {
                if let s = tenancy.agreementStartDate, let d = Self.dayFormatter.date(from: String(s.prefix(10))) {
                    startDate = d
                } else if let s = tenancy.moveInDate, let d = Self.dayFormatter.date(from: String(s.prefix(10))) {
                    startDate = d
                }
                if let e = tenancy.agreementEndDate, let d = Self.dayFormatter.date(from: String(e.prefix(10))) {
                    endDate = d
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.updateTenancyAgreementMeta(
                id: tenancy.id,
                UpdateTenancyAgreementMetaBody(
                    agreementStartDate: Self.dayFormatter.string(from: startDate),
                    agreementEndDate: Self.dayFormatter.string(from: endDate)
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AssignTenancySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unitId: UUID
    var onSaved: () async -> Void

    @State private var tenants: [ManagedUserItem] = []
    @State private var selectedTenantId: UUID?
    @State private var moveInDate = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isLoading = true

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
                if isLoading {
                    ProgressView("Loading tenants…")
                } else {
                    Section("Tenant") {
                        if tenants.isEmpty {
                            Text("No active tenants found. Create a tenant in People first.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            Picker("Tenant", selection: $selectedTenantId) {
                                Text("Select").tag(Optional<UUID>.none)
                                ForEach(tenants) { tenant in
                                    Text(tenant.fullName).tag(Optional(tenant.id))
                                }
                            }
                        }
                        DatePicker("Move-in date", selection: $moveInDate, displayedComponents: .date)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Assign tenancy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .task { await loadTenants() }
        }
    }

    private func loadTenants() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tenants = try await appState.api.users(role: "TENANT", size: 100).content.filter { $0.active }
            if selectedTenantId == nil {
                selectedTenantId = tenants.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        if tenants.isEmpty {
            errorMessage = "No active tenants found. Create a tenant under People first, then assign tenancy."
            return
        }
        guard let selectedTenantId else {
            errorMessage = "Select a tenant for this unit."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            _ = try await appState.api.createTenancy(
                unitId: unitId,
                CreateTenancyBody(
                    tenantUserId: selectedTenantId,
                    moveInDate: Self.dayFormatter.string(from: moveInDate)
                )
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EndTenancySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let tenancyId: UUID
    var onSaved: () async -> Void

    @State private var moveOutDate = Date()
    @State private var errorMessage: String?
    @State private var isSaving = false

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
                Section {
                    DatePicker("Move-out date", selection: $moveOutDate, displayedComponents: .date)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("End tenancy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("End") { Task { await save() } }
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
            _ = try await appState.api.endTenancy(
                id: tenancyId,
                EndTenancyBody(moveOutDate: Self.dayFormatter.string(from: moveOutDate))
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct UpdateUnitStatusSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unit: UnitItem
    var onSaved: (UnitItem) -> Void

    @State private var occupancy: OccupancyStatusOption
    @State private var toLet: ToLetBoardStatusOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(unit: UnitItem, onSaved: @escaping (UnitItem) -> Void) {
        self.unit = unit
        self.onSaved = onSaved
        _occupancy = State(initialValue: OccupancyStatusOption(rawValue: unit.occupancyStatus) ?? .VACANT)
        _toLet = State(initialValue: ToLetBoardStatusOption(rawValue: unit.toLetBoardStatus) ?? .NOT_INSTALLED)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    Picker("Occupancy", selection: $occupancy) {
                        ForEach(OccupancyStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Picker("To-let board", selection: $toLet) {
                        ForEach(ToLetBoardStatusOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Update unit")
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
            let updated = try await appState.api.updateUnitStatus(
                unitId: unit.id,
                UpdateUnitStatusBody(
                    occupancyStatus: occupancy.rawValue,
                    toLetBoardStatus: toLet.rawValue
                )
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EditUnitDefinitionSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let unit: UnitItem
    var onSaved: (UnitItem) -> Void

    @State private var unitNumber: String
    @State private var unitType: UnitTypeOption
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(unit: UnitItem, onSaved: @escaping (UnitItem) -> Void) {
        self.unit = unit
        self.onSaved = onSaved
        _unitNumber = State(initialValue: unit.unitNumber)
        _unitType = State(initialValue: UnitTypeOption(rawValue: unit.unitType) ?? .TWO_BHK)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Unit") {
                    TextField("Unit number", text: $unitNumber)
                        .textInputAutocapitalization(.characters)
                }
                Section {
                    ForEach(UnitTypeOption.pickerCases) { option in
                        Button {
                            unitType = option
                        } label: {
                            HStack {
                                Text(option.title)
                                    .foregroundStyle(NriTheme.ink)
                                Spacer()
                                if unitType == option {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(NriTheme.teal)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("BHK layout")
                } footer: {
                    Text("Selected: \(unitType.title) (\(unitType.rawValue))")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle("Edit unit")
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
        let trimmed = unitNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Unit number is required."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            let updated = try await appState.api.updateUnit(
                unitId: unit.id,
                UpdateUnitBody(unitNumber: trimmed, unitType: unitType.rawValue)
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
