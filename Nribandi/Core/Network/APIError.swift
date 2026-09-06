import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case unauthorized
    case http(status: Int, code: String?, message: String)
    case decoding(String)
    case transport(String)
    case emptyData
    case validation(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid API URL for this environment."
        case .unauthorized: return "Please sign in again."
        case .http(_, _, let message): return message
        case .decoding: return "Could not read the server response. Please try again."
        case .transport(let detail): return detail
        case .emptyData: return "Server returned an empty response."
        case .validation(let message): return message
        }
    }

    static func fromApiError(_ err: ApiErrorResponse, status: Int) -> APIError {
        let composed = err.userFacingMessage
        let message = composed.isEmpty ? "Request failed (\(status))." : composed
        return .http(status: status, code: err.errorCode, message: message)
    }
}
