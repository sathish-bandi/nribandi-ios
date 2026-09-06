import Foundation

actor APIClient {
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
        try await send(method: "POST", path: "/api/v1/auth/login",
                       body: LoginRequest(email: email, password: password),
                       authorized: false, as: AuthResponse.self)
    }

    func refresh(refreshToken: String) async throws -> AuthResponse {
        try await send(method: "POST", path: "/api/v1/auth/refresh-token",
                       body: RefreshTokenRequest(refreshToken: refreshToken),
                       authorized: false, as: AuthResponse.self)
    }

    func logout(refreshToken: String) async throws {
        struct Empty: Decodable {}
        _ = try? await send(method: "POST", path: "/api/v1/auth/logout",
                            body: RefreshTokenRequest(refreshToken: refreshToken),
                            authorized: false, as: Empty.self)
    }

    func dashboardSummary() async throws -> DashboardSummary {
        try await send(method: "GET", path: "/api/v1/dashboard/summary",
                       body: Optional<String>.none, authorized: true, as: DashboardSummary.self)
    }

    func properties(page: Int = 0, size: Int = 50) async throws -> PageResponse<PropertyItem> {
        try await send(method: "GET", path: "/api/v1/properties?page=\(page)&size=\(size)",
                       body: Optional<String>.none, authorized: true, as: PageResponse<PropertyItem>.self)
    }

    func property(id: UUID) async throws -> PropertyItem {
        try await send(method: "GET", path: "/api/v1/properties/\(id.uuidString.lowercased())",
                       body: Optional<String>.none, authorized: true, as: PropertyItem.self)
    }

    func units(propertyId: UUID) async throws -> [UnitItem] {
        let paged = "/api/v1/properties/\(propertyId.uuidString.lowercased())/units?page=0&size=200"
        if let page = try? await send(method: "GET", path: paged, body: Optional<String>.none,
                                      authorized: true, as: PageResponse<UnitItem>.self) {
            return page.content
        }
        return try await send(method: "GET",
                              path: "/api/v1/properties/\(propertyId.uuidString.lowercased())/units",
                              body: Optional<String>.none, authorized: true, as: [UnitItem].self)
    }

    func serviceRequests(page: Int = 0, size: Int = 50) async throws -> PageResponse<ServiceRequestItem> {
        try await send(method: "GET", path: "/api/v1/service-requests?page=\(page)&size=\(size)",
                       body: Optional<String>.none, authorized: true, as: PageResponse<ServiceRequestItem>.self)
    }

    func enquiries(page: Int = 0, size: Int = 50) async throws -> PageResponse<EnquiryItem> {
        try await send(method: "GET", path: "/api/v1/enquiries?page=\(page)&size=\(size)",
                       body: Optional<String>.none, authorized: true, as: PageResponse<EnquiryItem>.self)
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
            let token = await MainActor.run { sessionStore?.accessToken }
            guard let token, !token.isEmpty else { throw APIError.unauthorized }
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
                return try await send(method: method, path: path, body: body,
                                      authorized: authorized, as: Response.self, retryOnUnauthorized: false)
            }
            throw APIError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ApiErrorResponse.self, from: data) {
                throw APIError.http(status: http.statusCode, code: err.errorCode,
                                    message: err.message ?? "Request failed (\(http.statusCode)).")
            }
            throw APIError.http(status: http.statusCode, code: nil,
                                message: "Request failed (\(http.statusCode)).")
        }

        guard !data.isEmpty else { throw APIError.emptyData }

        do {
            let envelope = try JSONDecoder().decode(ApiResponse<Response>.self, from: data)
            if let value = envelope.data { return value }
            throw APIError.emptyData
        } catch let api as APIError {
            throw api
        } catch {
            do { return try JSONDecoder().decode(Response.self, from: data) }
            catch { throw APIError.decoding(String(describing: error)) }
        }
    }

    private static func friendlyTransport(_ error: Error, baseURL: URL) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost:
                return "Cannot reach \(baseURL.absoluteString). Start Docker (`./scripts/local-up.sh`), then run this app in the iOS Simulator with Local."
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return "HTTP blocked by App Transport Security. Local ATS should allow 127.0.0.1."
            default: break
            }
        }
        return error.localizedDescription
    }
}
