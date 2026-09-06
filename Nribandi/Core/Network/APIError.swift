import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case http(status: Int, code: String?, message: String)
    case decoding(String)
    case transport(String)
    case emptyData

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL for this environment."
        case .unauthorized: return "Please sign in again."
        case .http(_, _, let message): return message
        case .decoding(let detail): return "Could not read the server response. \(detail)"
        case .transport(let detail): return detail
        case .emptyData: return "Server returned an empty response."
        }
    }
}
