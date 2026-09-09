import Foundation

/// API target. Debug builds can switch Local ↔ Prod; Release is always Prod.
enum AppEnvironment: String, CaseIterable, Identifiable, Codable {
    case local
    case test // kept for older saved prefs; treated like Prod in the UI
    case prod

    var id: String { rawValue }

    /// Values shown in pickers (Local / Prod only).
    static var selectableCases: [AppEnvironment] { [.local, .prod] }

    var displayName: String {
        switch self {
        case .local: return "Local"
        case .test, .prod: return "Prod"
        }
    }

    var apiBaseURL: URL {
        switch self {
        case .local:
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

    /// Debug / local Xcode runs may switch Local / Prod.
    /// App Store and TestFlight (Release) are always Prod — no picker.
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
            // Older builds could save "test" — map to Prod in the UI.
            return env == .test ? .prod : env
        }
        if let forced = Bundle.main.object(forInfoDictionaryKey: "NribandiDefaultEnvironment") as? String,
           let env = AppEnvironment(rawValue: forced.lowercased()) {
            return env == .test ? .prod : env
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

enum AppBuildInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    /// e.g. "1.0.0 (12)"
    static var versionAndBuild: String {
        "\(version) (\(build))"
    }
}
