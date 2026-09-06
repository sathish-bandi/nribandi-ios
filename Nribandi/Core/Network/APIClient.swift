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

    func serviceRequests(page: Int = 0, size: Int = 50, status: String? = nil) async throws -> PageResponse<ServiceRequestItem> {
        var path = "/api/v1/service-requests?page=\(page)&size=\(size)"
        if let status, !status.isEmpty {
            path += "&status=\(status)"
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
                throw APIError.http(
                    status: http.statusCode,
                    code: err.errorCode,
                    message: err.message ?? "Request failed (\(http.statusCode))."
                )
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
