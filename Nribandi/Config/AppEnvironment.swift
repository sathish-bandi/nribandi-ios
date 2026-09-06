import Foundation

/// Maps to backend Spring profiles: local → local, TEST → qa, PROD → prod.
enum AppEnvironment: String, CaseIterable, Identifiable, Codable {
    case local, test, prod

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .test: return "TEST"
        case .prod: return "PROD"
        }
    }

    var backendProfile: String {
        switch self {
        case .local: return "local"
        case .test: return "qa"
        case .prod: return "prod"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .local:
            // iOS Simulator → Docker on this Mac
            return URL(string: "http://127.0.0.1:8082")!
        case .test:
            let raw = (Bundle.main.object(forInfoDictionaryKey: "NribandiTestAPIBaseURL") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: (raw?.isEmpty == false ? raw! : "https://api-qa.example.com"))!
        case .prod:
            let raw = (Bundle.main.object(forInfoDictionaryKey: "NribandiProdAPIBaseURL") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return URL(string: (raw?.isEmpty == false ? raw! : "https://api.example.com"))!
        }
    }

    /// Debug / local Xcode runs may switch Local / TEST / PROD.
    /// App Store and TestFlight (Release) are always PROD — no picker.
    static var allowsEnvironmentSelection: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    private static let key = "nribandi.selectedEnvironment"

    static func loadSaved() -> AppEnvironment {
        guard allowsEnvironmentSelection else {
            UserDefaults.standard.removeObject(forKey: key)
            return .prod
        }
        if let raw = UserDefaults.standard.string(forKey: key), let env = AppEnvironment(rawValue: raw) {
            return env
        }
        if let forced = Bundle.main.object(forInfoDictionaryKey: "NribandiDefaultEnvironment") as? String,
           let env = AppEnvironment(rawValue: forced.lowercased()) {
            return env
        }
        return .local
    }

    func save() {
        guard Self.allowsEnvironmentSelection else {
            UserDefaults.standard.removeObject(forKey: Self.key)
            return
        }
        UserDefaults.standard.set(rawValue, forKey: Self.key)
    }
}
