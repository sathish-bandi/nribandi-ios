import Foundation

/// Networking client. Runs on the main actor so it can safely use `SessionStore`.
@MainActor
final class APIClient {
    private var environment: AppEnvironment
    private let urlSession: URLSession
    private weak var sessionStore: SessionStore?

    init(environment: AppEnvironment, session: SessionStore) {
        self.environment = environment
        self.sessionStore = session
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.urlSession = URLSession(configuration: config)
    }

    func updateEnvironment(_ environment: AppEnvironment) {
        self.environment = environment
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await send(
            method: "POST",
            path: "/api/v1/auth/login",
            body: LoginRequest(email: email, password: password),
            authorized: false,
            as: AuthResponse.self
        )
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await send(
            method: "POST",
            path: "/api/v1/auth/refresh-token",
            body: RefreshTokenRequest(refreshToken: refreshToken),
            authorized: false,
            as: AuthResponse.self
        )
    }

    func logout(refreshToken: String) async throws {
        struct Empty: Decodable {}
        _ = try? await send(
            method: "POST",
            path: "/api/v1/auth/logout",
            body: RefreshTokenRequest(refreshToken: refreshToken),
            authorized: false,
            as: Empty.self
        )
    }

    /// Always succeeds with a generic message when the email may or may not exist.
    @discardableResult
    func forgotPassword(email: String) async throws -> String {
        try await sendMessage(
            method: "POST",
            path: "/api/v1/auth/forgot-password",
            body: ForgotPasswordRequest(email: email),
            authorized: false
        )
    }

    @discardableResult
    func resetPassword(token: String, newPassword: String) async throws -> String {
        try await sendMessage(
            method: "POST",
            path: "/api/v1/auth/reset-password",
            body: ResetPasswordRequest(token: token, newPassword: newPassword),
            authorized: false
        )
    }

    @discardableResult
    func changePassword(currentPassword: String, newPassword: String) async throws -> String {
        try await sendMessage(
            method: "POST",
            path: "/api/v1/users/me/change-password",
            body: ChangePasswordRequest(currentPassword: currentPassword, newPassword: newPassword),
            authorized: true
        )
    }

    func dashboardSummary() async throws -> DashboardSummary {
        try await send(
            method: "GET",
            path: "/api/v1/dashboard/summary",
            body: Optional<String>.none,
            authorized: true,
            as: DashboardSummary.self
        )
    }

    func properties(page: Int = 0, size: Int = 50) async throws -> PageResponse<PropertyItem> {
        try await send(
            method: "GET",
            path: "/api/v1/properties?page=\(page)&size=\(size)",
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<PropertyItem>.self
        )
    }

    func property(id: UUID) async throws -> PropertyItem {
        try await send(
            method: "GET",
            path: "/api/v1/properties/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: PropertyItem.self
        )
    }

    func units(propertyId: UUID) async throws -> [UnitItem] {
        let paged = "/api/v1/properties/\(propertyId.uuidString.lowercased())/units?page=0&size=200"
        if let page = try? await send(
            method: "GET",
            path: paged,
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<UnitItem>.self
        ) {
            return page.content
        }
        return try await send(
            method: "GET",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/units",
            body: Optional<String>.none,
            authorized: true,
            as: [UnitItem].self
        )
    }

    func serviceRequests(
        page: Int = 0,
        size: Int = 50,
        status: String? = nil,
        excludeStatus: String? = nil
    ) async throws -> PageResponse<ServiceRequestItem> {
        var path = "/api/v1/service-requests?page=\(page)&size=\(size)"
        if let status, !status.isEmpty {
            path += "&status=\(status)"
        }
        if let excludeStatus, !excludeStatus.isEmpty {
            path += "&excludeStatus=\(excludeStatus)"
        }
        return try await send(
            method: "GET",
            path: path,
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<ServiceRequestItem>.self
        )
    }

    func serviceRequest(id: UUID) async throws -> ServiceRequestItem {
        try await send(
            method: "GET",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func createServiceRequest(_ body: CreateServiceRequestBody) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests",
            body: body,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func cancelServiceRequest(id: UUID) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/cancel",
            body: Optional<String>.none,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func serviceRequestHistory(id: UUID) async throws -> [ServiceRequestHistoryItem] {
        try await send(
            method: "GET",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/history",
            body: Optional<String>.none,
            authorized: true,
            as: [ServiceRequestHistoryItem].self
        )
    }

    func myTenancies() async throws -> [TenancyItem] {
        try await send(
            method: "GET",
            path: "/api/v1/tenancies/mine",
            body: Optional<String>.none,
            authorized: true,
            as: [TenancyItem].self
        )
    }

    func enquiries(page: Int = 0, size: Int = 50) async throws -> PageResponse<EnquiryItem> {
        try await send(
            method: "GET",
            path: "/api/v1/enquiries?page=\(page)&size=\(size)",
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<EnquiryItem>.self
        )
    }

    func inspections(page: Int = 0, size: Int = 50) async throws -> PageResponse<InspectionItem> {
        try await send(
            method: "GET",
            path: "/api/v1/inspections?page=\(page)&size=\(size)",
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<InspectionItem>.self
        )
    }

    func tenantVerifications(status: String = "PENDING_REVIEW") async throws -> [TenantVerificationItem] {
        try await send(
            method: "GET",
            path: "/api/v1/tenant-verifications?status=\(status)",
            body: Optional<String>.none,
            authorized: true,
            as: [TenantVerificationItem].self
        )
    }

    func createProperty(_ body: CreatePropertyBody) async throws -> PropertyItem {
        try await send(
            method: "POST",
            path: "/api/v1/properties",
            body: body,
            authorized: true,
            as: PropertyItem.self
        )
    }

    func updateProperty(id: UUID, _ body: UpdatePropertyBody) async throws -> PropertyItem {
        try await send(
            method: "PUT",
            path: "/api/v1/properties/\(id.uuidString.lowercased())",
            body: body,
            authorized: true,
            as: PropertyItem.self
        )
    }

    @discardableResult
    func deleteProperty(id: UUID) async throws -> PropertyItem {
        try await send(
            method: "DELETE",
            path: "/api/v1/properties/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: PropertyItem.self
        )
    }

    func propertyAttachments(propertyId: UUID) async throws -> [PropertyAttachmentItem] {
        try await send(
            method: "GET",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/attachments",
            body: Optional<String>.none,
            authorized: true,
            as: [PropertyAttachmentItem].self
        )
    }

    func uploadPropertyAttachment(
        propertyId: UUID,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> PropertyAttachmentItem {
        try await uploadMultipart(
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/attachments",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            as: PropertyAttachmentItem.self
        )
    }

    func deletePropertyAttachment(propertyId: UUID, attachmentId: UUID) async throws {
        _ = try await sendMessage(
            method: "DELETE",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/attachments/\(attachmentId.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true
        )
    }

    func users(role: String? = nil, page: Int = 0, size: Int = 50) async throws -> PageResponse<ManagedUserItem> {
        var path = "/api/v1/users?page=\(page)&size=\(size)"
        if let role, !role.isEmpty {
            path += "&role=\(role)"
        }
        return try await send(
            method: "GET",
            path: path,
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<ManagedUserItem>.self
        )
    }

    func createUser(_ body: CreateUserBody) async throws -> ManagedUserItem {
        try await send(
            method: "POST",
            path: "/api/v1/users",
            body: body,
            authorized: true,
            as: ManagedUserItem.self
        )
    }

    func updateUser(id: UUID, _ body: UpdateUserBody) async throws -> ManagedUserItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/users/\(id.uuidString.lowercased())",
            body: body,
            authorized: true,
            as: ManagedUserItem.self
        )
    }

    func deactivateUser(id: UUID) async throws -> ManagedUserItem {
        try await send(
            method: "DELETE",
            path: "/api/v1/users/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: ManagedUserItem.self
        )
    }

    func user(id: UUID) async throws -> ManagedUserItem {
        try await send(
            method: "GET",
            path: "/api/v1/users/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: ManagedUserItem.self
        )
    }

    // MARK: - Blocks / Floors / Units

    func blocks(propertyId: UUID) async throws -> [BlockItem] {
        try await send(
            method: "GET",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/blocks",
            body: Optional<String>.none,
            authorized: true,
            as: [BlockItem].self
        )
    }

    func createBlock(propertyId: UUID, _ body: CreateBlockBody) async throws -> BlockItem {
        try await send(
            method: "POST",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/blocks",
            body: body,
            authorized: true,
            as: BlockItem.self
        )
    }

    func floors(propertyId: UUID) async throws -> [FloorItem] {
        try await send(
            method: "GET",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/floors",
            body: Optional<String>.none,
            authorized: true,
            as: [FloorItem].self
        )
    }

    func createFloor(propertyId: UUID, _ body: CreateFloorBody) async throws -> FloorItem {
        try await send(
            method: "POST",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/floors",
            body: body,
            authorized: true,
            as: FloorItem.self
        )
    }

    func createUnit(propertyId: UUID, _ body: CreateUnitBody) async throws -> UnitItem {
        try await send(
            method: "POST",
            path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/units",
            body: body,
            authorized: true,
            as: UnitItem.self
        )
    }

    func updateUnitStatus(unitId: UUID, _ body: UpdateUnitStatusBody) async throws -> UnitItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())/status",
            body: body,
            authorized: true,
            as: UnitItem.self
        )
    }

    func updateUnit(unitId: UUID, _ body: UpdateUnitBody) async throws -> UnitItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())",
            body: body,
            authorized: true,
            as: UnitItem.self
        )
    }

    func unit(id: UUID) async throws -> UnitItem {
        try await send(
            method: "GET",
            path: "/api/v1/units/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: UnitItem.self
        )
    }

    // MARK: - Tenancies

    func tenancies(unitId: UUID) async throws -> [TenancyItem] {
        try await send(
            method: "GET",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())/tenancies",
            body: Optional<String>.none,
            authorized: true,
            as: [TenancyItem].self
        )
    }

    func createTenancy(unitId: UUID, _ body: CreateTenancyBody) async throws -> TenancyItem {
        try await send(
            method: "POST",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())/tenancies",
            body: body,
            authorized: true,
            as: TenancyItem.self
        )
    }

    func endTenancy(id: UUID, _ body: EndTenancyBody) async throws -> TenancyItem {
        try await send(
            method: "POST",
            path: "/api/v1/tenancies/\(id.uuidString.lowercased())/end",
            body: body,
            authorized: true,
            as: TenancyItem.self
        )
    }

    func tenancy(id: UUID) async throws -> TenancyItem {
        try await send(
            method: "GET",
            path: "/api/v1/tenancies/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: TenancyItem.self
        )
    }

    func uploadTenancyAgreement(
        id: UUID,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> TenancyItem {
        try await uploadMultipart(
            path: "/api/v1/tenancies/\(id.uuidString.lowercased())/agreement",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            as: TenancyItem.self
        )
    }

    func updateTenancyAgreementMeta(id: UUID, _ body: UpdateTenancyAgreementMetaBody) async throws -> TenancyItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/tenancies/\(id.uuidString.lowercased())/agreement-meta",
            body: body,
            authorized: true,
            as: TenancyItem.self
        )
    }

    // MARK: - Service request staff actions

    func assignServiceRequest(id: UUID, employeeUserId: UUID) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/assign",
            body: AssignEmployeeBody(employeeUserId: employeeUserId),
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func updateServiceRequestStatus(id: UUID, _ body: UpdateServiceRequestStatusBody) async throws -> ServiceRequestItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/status",
            body: body,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func setServiceRequestEstimate(id: UUID, _ body: SetRepairEstimateBody) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/estimate",
            body: body,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func setServiceRequestPayer(id: UUID, _ body: SetServiceRequestPayerBody) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/payer",
            body: body,
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    func markServiceRequestWorkCompleted(id: UUID, comments: String?) async throws -> ServiceRequestItem {
        try await send(
            method: "POST",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/work-completed",
            body: MarkWorkCompletedBody(comments: comments),
            authorized: true,
            as: ServiceRequestItem.self
        )
    }

    // MARK: - Company payment accounts (UPI / GPay / PhonePe)

    func companyPaymentAccounts(includeInactive: Bool = false) async throws -> [CompanyPaymentAccountItem] {
        var path = "/api/v1/company-payment-accounts"
        if includeInactive {
            path += "?includeInactive=true"
        }
        return try await send(
            method: "GET",
            path: path,
            body: Optional<String>.none,
            authorized: true,
            as: [CompanyPaymentAccountItem].self
        )
    }

    func createCompanyPaymentAccount(_ body: UpsertCompanyPaymentAccountBody) async throws -> CompanyPaymentAccountItem {
        try await send(
            method: "POST",
            path: "/api/v1/company-payment-accounts",
            body: body,
            authorized: true,
            as: CompanyPaymentAccountItem.self
        )
    }

    func updateCompanyPaymentAccount(id: UUID, _ body: UpsertCompanyPaymentAccountBody) async throws -> CompanyPaymentAccountItem {
        try await send(
            method: "PUT",
            path: "/api/v1/company-payment-accounts/\(id.uuidString.lowercased())",
            body: body,
            authorized: true,
            as: CompanyPaymentAccountItem.self
        )
    }

    func deleteCompanyPaymentAccount(id: UUID) async throws {
        _ = try await sendMessage(
            method: "DELETE",
            path: "/api/v1/company-payment-accounts/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true
        )
    }

    func serviceRequestAttachments(id: UUID) async throws -> [ServiceRequestAttachmentItem] {
        try await send(
            method: "GET",
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/attachments",
            body: Optional<String>.none,
            authorized: true,
            as: [ServiceRequestAttachmentItem].self
        )
    }

    func uploadServiceRequestAttachment(
        id: UUID,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> ServiceRequestAttachmentItem {
        try await uploadMultipart(
            path: "/api/v1/service-requests/\(id.uuidString.lowercased())/attachments",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            as: ServiceRequestAttachmentItem.self
        )
    }

    // MARK: - Enquiries

    func enquiry(id: UUID) async throws -> EnquiryItem {
        try await send(
            method: "GET",
            path: "/api/v1/enquiries/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: EnquiryItem.self
        )
    }

    func assignEnquiry(id: UUID, employeeUserId: UUID) async throws -> EnquiryItem {
        try await send(
            method: "POST",
            path: "/api/v1/enquiries/\(id.uuidString.lowercased())/assign",
            body: AssignEmployeeBody(employeeUserId: employeeUserId),
            authorized: true,
            as: EnquiryItem.self
        )
    }

    func updateEnquiryStatus(id: UUID, status: String) async throws -> EnquiryItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/enquiries/\(id.uuidString.lowercased())/status",
            body: UpdateEnquiryStatusBody(status: status),
            authorized: true,
            as: EnquiryItem.self
        )
    }

    func unitEnquiries(unitId: UUID) async throws -> [EnquiryItem] {
        try await send(
            method: "GET",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())/enquiries",
            body: Optional<String>.none,
            authorized: true,
            as: [EnquiryItem].self
        )
    }

    func createUnitEnquiry(unitId: UUID, _ body: CreateUnitEnquiryBody) async throws -> EnquiryItem {
        try await send(
            method: "POST",
            path: "/api/v1/units/\(unitId.uuidString.lowercased())/enquiries",
            body: body,
            authorized: true,
            as: EnquiryItem.self
        )
    }

    func updateEnquiry(id: UUID, _ body: UpdateEnquiryBody) async throws -> EnquiryItem {
        try await send(
            method: "PUT",
            path: "/api/v1/enquiries/\(id.uuidString.lowercased())",
            body: body,
            authorized: true,
            as: EnquiryItem.self
        )
    }

    func deleteEnquiry(id: UUID) async throws {
        _ = try await sendMessage(
            method: "DELETE",
            path: "/api/v1/enquiries/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true
        )
    }

    // MARK: - Inspections

    func createInspection(_ body: CreateInspectionBody) async throws -> InspectionItem {
        try await send(
            method: "POST",
            path: "/api/v1/inspections",
            body: body,
            authorized: true,
            as: InspectionItem.self
        )
    }

    func updateInspectionStatus(id: UUID, status: String) async throws -> InspectionItem {
        try await send(
            method: "PATCH",
            path: "/api/v1/inspections/\(id.uuidString.lowercased())/status",
            body: UpdateInspectionStatusBody(status: status),
            authorized: true,
            as: InspectionItem.self
        )
    }

    func unitInspections(unitId: UUID, limit: Int? = nil) async throws -> [InspectionDetailItem] {
        var path = "/api/v1/inspections/by-unit/\(unitId.uuidString.lowercased())"
        if let limit {
            path += "?limit=\(limit)"
        }
        return try await send(
            method: "GET",
            path: path,
            body: Optional<String>.none,
            authorized: true,
            as: [InspectionDetailItem].self
        )
    }

    // MARK: - Invoices

    func invoices(page: Int = 0, size: Int = 50) async throws -> PageResponse<InvoiceItem> {
        try await send(
            method: "GET",
            path: "/api/v1/invoices?page=\(page)&size=\(size)",
            body: Optional<String>.none,
            authorized: true,
            as: PageResponse<InvoiceItem>.self
        )
    }

    func invoice(id: UUID) async throws -> InvoiceItem {
        try await send(
            method: "GET",
            path: "/api/v1/invoices/\(id.uuidString.lowercased())",
            body: Optional<String>.none,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    func createInvoice(_ body: CreateInvoiceBody) async throws -> InvoiceItem {
        try await send(
            method: "POST",
            path: "/api/v1/invoices",
            body: body,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    func submitInvoice(id: UUID) async throws -> InvoiceItem {
        try await send(
            method: "POST",
            path: "/api/v1/invoices/\(id.uuidString.lowercased())/submit",
            body: Optional<String>.none,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    func approveInvoice(id: UUID) async throws -> InvoiceItem {
        try await send(
            method: "POST",
            path: "/api/v1/invoices/\(id.uuidString.lowercased())/approve",
            body: Optional<String>.none,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    func rejectInvoice(id: UUID) async throws -> InvoiceItem {
        try await send(
            method: "POST",
            path: "/api/v1/invoices/\(id.uuidString.lowercased())/reject",
            body: Optional<String>.none,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    func markInvoicePaid(id: UUID) async throws -> InvoiceItem {
        try await send(
            method: "POST",
            path: "/api/v1/invoices/\(id.uuidString.lowercased())/mark-paid",
            body: Optional<String>.none,
            authorized: true,
            as: InvoiceItem.self
        )
    }

    // MARK: - KYC / tenant verification

    func tenantVerification(tenantUserId: UUID) async throws -> TenantVerificationItem {
        try await send(
            method: "GET",
            path: "/api/v1/tenants/\(tenantUserId.uuidString.lowercased())/verification",
            body: Optional<String>.none,
            authorized: true,
            as: TenantVerificationItem.self
        )
    }

    func upsertTenantVerification(tenantUserId: UUID, _ body: UpsertTenantVerificationBody) async throws -> TenantVerificationItem {
        try await send(
            method: "PUT",
            path: "/api/v1/tenants/\(tenantUserId.uuidString.lowercased())/verification",
            body: body,
            authorized: true,
            as: TenantVerificationItem.self
        )
    }

    func submitTenantVerification(tenantUserId: UUID) async throws -> TenantVerificationItem {
        try await send(
            method: "POST",
            path: "/api/v1/tenants/\(tenantUserId.uuidString.lowercased())/verification/submit",
            body: Optional<String>.none,
            authorized: true,
            as: TenantVerificationItem.self
        )
    }

    func reviewTenantVerification(tenantUserId: UUID, _ body: ReviewTenantVerificationBody) async throws -> TenantVerificationItem {
        try await send(
            method: "POST",
            path: "/api/v1/tenants/\(tenantUserId.uuidString.lowercased())/verification/review",
            body: body,
            authorized: true,
            as: TenantVerificationItem.self
        )
    }

    /// Document upload (multipart). Returns the uploaded document metadata.
    func uploadTenantVerificationDocument(
        tenantUserId: UUID,
        documentType: String,
        fileData: Data,
        fileName: String,
        mimeType: String
    ) async throws -> TenantVerificationDocumentItem {
        let encodedType = documentType.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? documentType
        return try await uploadMultipart(
            path: "/api/v1/tenants/\(tenantUserId.uuidString.lowercased())/verification/documents?documentType=\(encodedType)",
            fileData: fileData,
            fileName: fileName,
            mimeType: mimeType,
            as: TenantVerificationDocumentItem.self
        )
    }

    // MARK: - Internals

    private func uploadMultipart<Response: Decodable>(
        path: String,
        fileData: Data,
        fileName: String,
        mimeType: String,
        as _: Response.Type
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: environment.apiBaseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        guard let token = sessionStore?.accessToken, !token.isEmpty else {
            throw APIError.unauthorized
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var body = Data()
        if let preamble = "--\(boundary)\r\n".data(using: .utf8),
           let disposition = "Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8),
           let contentType = "Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8),
           let closing = "\r\n--\(boundary)--\r\n".data(using: .utf8) {
            body.append(preamble)
            body.append(disposition)
            body.append(contentType)
            body.append(fileData)
            body.append(closing)
        } else {
            throw APIError.transport("Could not build upload body.")
        }
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(Self.friendlyTransport(error, baseURL: environment.apiBaseURL))
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Unexpected response from server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ApiErrorResponse.self, from: data) {
                throw APIError.fromApiError(err, status: http.statusCode)
            }
            throw APIError.http(status: http.statusCode, code: nil, message: "Upload failed (\(http.statusCode)).")
        }
        do {
            let envelope = try JSONDecoder().decode(ApiResponse<Response>.self, from: data)
            if let value = envelope.data { return value }
            throw APIError.emptyData
        } catch let api as APIError {
            throw api
        } catch {
            return try JSONDecoder().decode(Response.self, from: data)
        }
    }

    /// Message-only endpoints (`ApiResponse` with null data).
    private func sendMessage<Body: Encodable>(
        method: String,
        path: String,
        body: Body?,
        authorized: Bool,
        retryOnUnauthorized: Bool = true
    ) async throws -> String {
        guard let url = URL(string: path, relativeTo: environment.apiBaseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        if authorized {
            guard let token = sessionStore?.accessToken, !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(Self.friendlyTransport(error, baseURL: environment.apiBaseURL))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Unexpected response from server.")
        }

        if http.statusCode == 401, authorized, retryOnUnauthorized {
            let ok = await sessionStore?.refreshIfNeeded(using: self) ?? false
            if ok {
                return try await sendMessage(
                    method: method,
                    path: path,
                    body: body,
                    authorized: authorized,
                    retryOnUnauthorized: false
                )
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ApiErrorResponse.self, from: data) {
                throw APIError.fromApiError(err, status: http.statusCode)
            }
            throw APIError.http(status: http.statusCode, code: nil, message: "Request failed (\(http.statusCode)).")
        }

        if let envelope = try? JSONDecoder().decode(ApiResponse<String?>.self, from: data),
           let message = envelope.message, !message.isEmpty {
            return message
        }
        if let parsed = try? JSONDecoder().decode(MessageOnlyPayload.self, from: data),
           let message = parsed.message, !message.isEmpty {
            return message
        }
        return "Done."
    }

    private func send<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body?,
        authorized: Bool,
        as _: Response.Type,
        retryOnUnauthorized: Bool = true
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: environment.apiBaseURL)?.absoluteURL else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        if authorized {
            guard let token = sessionStore?.accessToken, !token.isEmpty else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw APIError.transport(Self.friendlyTransport(error, baseURL: environment.apiBaseURL))
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Unexpected response from server.")
        }

        if http.statusCode == 401, authorized, retryOnUnauthorized {
            let ok = await sessionStore?.refreshIfNeeded(using: self) ?? false
            if ok {
                return try await send(
                    method: method,
                    path: path,
                    body: body,
                    authorized: authorized,
                    as: Response.self,
                    retryOnUnauthorized: false
                )
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ApiErrorResponse.self, from: data) {
                throw APIError.fromApiError(err, status: http.statusCode)
            }
            throw APIError.http(
                status: http.statusCode,
                code: nil,
                message: "Request failed (\(http.statusCode))."
            )
        }

        guard !data.isEmpty else { throw APIError.emptyData }

        do {
            let envelope = try JSONDecoder().decode(ApiResponse<Response>.self, from: data)
            if let value = envelope.data { return value }
            throw APIError.emptyData
        } catch let api as APIError {
            throw api
        } catch {
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        }
    }

    private static func friendlyTransport(_ error: Error, baseURL: URL) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                return "Cannot reach \(baseURL.absoluteString). Start the backend with ./scripts/local-up.sh in rental-property-app, then run this app with Local."
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return "HTTP blocked by App Transport Security. Local ATS should allow 127.0.0.1."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

/// Decodes message-only API envelopes. Kept outside generic methods (Swift
/// does not allow nested types inside generic functions).
private struct MessageOnlyPayload: Decodable {
    let message: String?
    let success: Bool?
}
