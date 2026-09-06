import Foundation
import Combine

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var user: UserProfile?
    @Published private(set) var isAuthenticated = false

    private(set) var accessToken: String?
    private var refreshToken: String?
    private weak var api: APIClient?

    private let accessAccount = "accessToken"
    private let refreshAccount = "refreshToken"
    private let userAccount = "userJson"

    init() {
        accessToken = KeychainStore.get(account: accessAccount)
        refreshToken = KeychainStore.get(account: refreshAccount)
        if let json = KeychainStore.get(account: userAccount),
           let data = json.data(using: .utf8),
           let saved = try? JSONDecoder().decode(UserProfile.self, from: data) {
            user = saved
        }
        isAuthenticated = accessToken != nil && user != nil
    }

    func bind(api: APIClient) {
        self.api = api
    }

    func apply(_ auth: AuthResponse) {
        accessToken = auth.accessToken
        refreshToken = auth.refreshToken
        user = auth.user
        isAuthenticated = true
        KeychainStore.set(auth.accessToken, account: accessAccount)
        KeychainStore.set(auth.refreshToken, account: refreshAccount)
        if let data = try? JSONEncoder().encode(auth.user),
           let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, account: userAccount)
        }
    }

    func logout() async {
        if let refreshToken, let api {
            try? await api.logout(refreshToken: refreshToken)
        }
        clearLocalSession()
    }

    func clearLocalSession() {
        accessToken = nil
        refreshToken = nil
        user = nil
        isAuthenticated = false
        KeychainStore.delete(account: accessAccount)
        KeychainStore.delete(account: refreshAccount)
        KeychainStore.delete(account: userAccount)
    }

    func refreshIfNeeded(using client: APIClient) async -> Bool {
        guard let refreshToken else { return false }
        do {
            let auth = try await client.refresh(refreshToken: refreshToken)
            apply(auth)
            return true
        } catch {
            clearLocalSession()
            return false
        }
    }
}
