import Foundation

struct ApiResponse<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let message: String?
    let timestamp: String?
}

struct ApiErrorResponse: Decodable {
    let success: Bool?
    let errorCode: String?
    let message: String?
    let status: Int?
    let path: String?
    let timestamp: String?
    let fieldErrors: [ApiFieldError]?

    /// Prefer field-level details when the backend only returns a generic message.
    var userFacingMessage: String {
        let fields = (fieldErrors ?? []).compactMap { err -> String? in
            let label = FieldLabel.display(err.field)
            let msg = (err.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !msg.isEmpty else { return nil }
            return "\(label): \(msg)"
        }
        if !fields.isEmpty {
            return fields.joined(separator: "\n")
        }
        return (message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct ApiFieldError: Decodable {
    let field: String?
    let message: String?
}

enum FieldLabel {
    static func display(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "Field" }
        let leaf = raw.split(separator: ".").last.map(String.init) ?? raw
        switch leaf {
        case "fullName": return "Full name"
        case "email": return "Email"
        case "phone": return "Phone"
        case "password": return "Password"
        case "role": return "Role"
        case "pincode": return "Pincode"
        case "numberOfFloors": return "Floors"
        case "propertyType": return "Property type"
        case "propertyPurpose": return "Purpose"
        case "ownerId": return "Owner"
        case "blockNumber": return "Block number"
        case "floorNumber": return "Floor number"
        case "floorId": return "Floor"
        case "unitNumber": return "Unit number"
        case "unitType": return "Unit type"
        case "tenantUserId": return "Tenant"
        case "moveInDate": return "Move-in date"
        case "moveOutDate": return "Move-out date"
        default:
            guard let first = leaf.first else { return "Field" }
            return String(first).uppercased() + String(leaf.dropFirst())
        }
    }
}

struct PageResponse<T: Decodable>: Decodable {
    let content: [T]
    let pageNumber: Int
    let pageSize: Int
    let totalElements: Int64
    let totalPages: Int
    let last: Bool
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct ForgotPasswordRequest: Encodable {
    let email: String
}

struct ResetPasswordRequest: Encodable {
    let token: String
    let newPassword: String
}

struct ChangePasswordRequest: Encodable {
    let currentPassword: String
    let newPassword: String
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

struct AuthResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresInSeconds: Int64
    let user: UserProfile
}

struct UserProfile: Codable, Identifiable, Equatable {
    let id: UUID
    let email: String
    let phone: String?
    let fullName: String
    let role: UserRole
    let active: Bool
    let createdAt: String?
}

enum UserRole: String, Codable {
    case ADMIN, OWNER, TENANT, EMPLOYEE
    var title: String { rawValue.capitalized }
}

struct DashboardSummary: Decodable {
    let totalProperties: Int64
    let totalUnits: Int64
    let occupiedUnits: Int64
    let vacantUnits: Int64
    let unitsWithToLetBoards: Int64
    let openServiceRequests: Int64
    let assignedServiceRequests: Int64
    let inProgressServiceRequests: Int64
    let resolvedServiceRequests: Int64
    let closedServiceRequests: Int64
    let upcomingInspections: Int64
    let completedInspections: Int64
    let pendingInvoices: Int64
    let approvedInvoices: Int64
    let approvedInvoiceTotal: Decimal?
    let paidInvoiceTotal: Decimal?
    let newEnquiries: Int64
    let pendingTenantVerifications: Int64
}

struct PropertyItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let ownerId: UUID
    let ownerName: String?
    let name: String
    let address: String
    let locality: String?
    let city: String
    let state: String
    let pincode: String
    let latitude: Decimal?
    let longitude: Decimal?
    let numberOfFloors: Int?
    let propertyType: String
    let propertyPurpose: String
    let active: Bool?
    let createdAt: String?
    let updatedAt: String?

    var locationLine: String {
        [locality, city, pincode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var isActive: Bool { active ?? true }
}

struct PropertyAttachmentItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let originalFilename: String?
    let contentType: String?
    let sizeBytes: Int64?
    let mediaKind: String?
    let uploadedByUserId: UUID?
    let uploadedByName: String?
    let downloadUrl: String?
    let createdAt: String?

    var isImage: Bool {
        if let mediaKind, mediaKind.uppercased() == "IMAGE" { return true }
        return (contentType ?? "").hasPrefix("image/")
    }

    var isVideo: Bool {
        if let mediaKind, mediaKind.uppercased() == "VIDEO" { return true }
        return (contentType ?? "").hasPrefix("video/")
    }
}

struct UnitItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let blockId: UUID?
    let blockNumber: String?
    let floorId: UUID
    let floorNumber: Int?
    let unitNumber: String
    let unitType: String
    let occupancyStatus: String
    let toLetBoardStatus: String
    let createdAt: String?
    let updatedAt: String?

    var title: String {
        let floorLabel = floorNumber.map(String.init) ?? "—"
        if let blockNumber, !blockNumber.isEmpty {
            return "Block \(blockNumber) · Fl \(floorLabel) · \(unitNumber)"
        }
        return "Fl \(floorLabel) · \(unitNumber)"
    }
}

struct ServiceRequestItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let unitId: UUID?
    let raisedByUserId: UUID
    let raisedByName: String?
    let category: String
    let title: String
    let description: String?
    let priority: String
    let status: String
    let assignedEmployeeId: UUID?
    let assignedEmployeeName: String?
    let sourceInspectionId: UUID?
    let createdAt: String?
    let updatedAt: String?

    var canCancel: Bool {
        ["OPEN", "ASSIGNED", "IN_PROGRESS", "WAITING_FOR_PARTS"].contains(status)
    }
}

struct CreateServiceRequestBody: Encodable {
    let propertyId: UUID
    let unitId: UUID?
    let category: String
    let title: String
    let description: String
    let priority: String
}

struct TenancyItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let propertyName: String?
    let unitId: UUID
    let unitNumber: String?
    let unitType: String?
    let tenantUserId: UUID
    let tenantName: String?
    let moveInDate: String?
    let moveOutDate: String?
    let active: Bool
    let createdAt: String?
    let updatedAt: String?

    var label: String {
        let unit = unitNumber.map { "Unit \($0)" } ?? "Unit"
        let property = propertyName ?? "Property"
        if let unitType, !unitType.isEmpty {
            return "\(property) · \(unit) · \(UnitTypeDisplay.title(for: unitType))"
        }
        return "\(property) · \(unit)"
    }
}

struct ServiceRequestAttachmentItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let serviceRequestId: UUID
    let originalFilename: String?
    let contentType: String?
    let fileSize: Int64?
    let uploadedByUserId: UUID?
    let uploadedByName: String?
    let downloadUrl: String?
    let createdAt: String?
}

struct ServiceRequestHistoryItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let serviceRequestId: UUID
    let oldStatus: String?
    let newStatus: String
    let changedByUserId: UUID
    let changedByName: String?
    let comments: String?
    let timestamp: String?
}

struct EnquiryItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let customerName: String
    let mobileNumber: String
    let whatsappNumber: String?
    let requestedLocality: String?
    let requestedUnitType: String?
    let budget: Decimal?
    let message: String?
    let source: String
    let status: String
    let assignedEmployeeId: UUID?
    let assignedEmployeeName: String?
    let createdAt: String?
    let updatedAt: String?
}

struct InspectionItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let propertyName: String?
    let unitId: UUID?
    let unitNumber: String?
    let inspectorEmployeeId: UUID?
    let inspectorEmployeeName: String?
    let inspectionType: String
    let inspectionDate: String?
    let notes: String?
    let status: String
    let createdAt: String?
    let updatedAt: String?
}

struct TenantVerificationItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let tenantUserId: UUID
    let tenantName: String?
    let status: String
    let idVerified: Bool?
    let idProofMatchedAddress: Bool?
    let permanentAddress: String?
    let permanentLocality: String?
    let permanentCity: String?
    let permanentState: String?
    let permanentPincode: String?
    let identityRequirementMet: Bool?
    let identityRequirement: String?
    let documents: [TenantVerificationDocumentItem]?
    let submittedAt: String?
    let createdAt: String?
    let updatedAt: String?

    var locationLine: String {
        [permanentLocality, permanentCity, permanentPincode]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var hasPermanentAddress: Bool {
        !(permanentAddress ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(permanentCity ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !(permanentState ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (permanentPincode ?? "").count == 6
    }
}

struct TenantVerificationDocumentItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let documentType: String
    let originalFilename: String?
    let contentType: String?
    let fileSize: Int64?
    let uploadedByUserId: UUID?
    let uploadedByName: String?
    let downloadUrl: String?
    let createdAt: String?
}

enum IdDocumentTypeOption: String, CaseIterable, Identifiable {
    case AADHAAR, PAN, PASSPORT, VOTER_ID, DRIVING_LICENSE, OTHER
    var id: String { rawValue }

    var title: String {
        switch self {
        case .AADHAAR: return "Aadhaar"
        case .PAN: return "PAN"
        case .PASSPORT: return "Passport"
        case .VOTER_ID: return "Voter ID"
        case .DRIVING_LICENSE: return "Driving licence"
        case .OTHER: return "Other ID"
        }
    }
}

struct UnitListRow: Identifiable, Hashable {
    let id: UUID
    let propertyName: String
    let unit: UnitItem
}

struct ManagedUserItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let email: String
    let phone: String?
    let fullName: String
    let role: UserRole
    let active: Bool
    let createdAt: String?
}

struct CreateUserBody: Encodable {
    let email: String
    let phone: String?
    let fullName: String
    let password: String
    let role: String
}

struct UpdateUserBody: Encodable {
    var fullName: String?
    var phone: String?
    var active: Bool?
}

struct CreatePropertyBody: Encodable {
    let name: String
    let address: String
    let locality: String
    let city: String
    let state: String
    let pincode: String
    let latitude: Decimal?
    let longitude: Decimal?
    let numberOfFloors: Int
    let propertyType: String
    let propertyPurpose: String?
    let ownerId: UUID?
}

struct UpdatePropertyBody: Encodable {
    var name: String?
    var address: String?
    var locality: String?
    var city: String?
    var state: String?
    var pincode: String?
    var latitude: Decimal?
    var longitude: Decimal?
    var numberOfFloors: Int?
    var propertyType: String?
    var propertyPurpose: String?
}

enum PropertyTypeOption: String, CaseIterable, Identifiable, Hashable {
    case APARTMENT, INDEPENDENT_HOUSE, VILLA, HIGH_RISE, MULTI_STOREY
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
    var usesBlocks: Bool { self == .APARTMENT || self == .HIGH_RISE || self == .MULTI_STOREY }
}

enum PropertyPurposeOption: String, CaseIterable, Identifiable, Hashable {
    case RESIDENTIAL, COMMERCIAL
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct BlockItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let blockNumber: String
    let name: String?
}

struct FloorItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let propertyId: UUID
    let blockId: UUID?
    let blockNumber: String?
    let floorNumber: Int
    let name: String?
}

struct CreateBlockBody: Encodable {
    let blockNumber: String
    let name: String?
}

struct CreateFloorBody: Encodable {
    let floorNumber: Int
    let name: String?
    let blockId: UUID?
    let blockNumber: String?
}

enum UnitTypeOption: String, CaseIterable, Identifiable {
    case ONE_BHK, TWO_BHK, THREE_BHK, FOUR_BHK, FIVE_BHK, SIX_BHK, SEVEN_BHK, EIGHT_BHK, NINE_BHK, TEN_BHK, PENTHOUSE, VILLA, INDEPENDENT_HOUSE
    var id: String { rawValue }

    /// Common Hyderabad inventory first, then larger / specialty layouts.
    static var pickerCases: [UnitTypeOption] {
        [.ONE_BHK, .TWO_BHK, .THREE_BHK, .FOUR_BHK, .PENTHOUSE, .VILLA, .INDEPENDENT_HOUSE,
         .FIVE_BHK, .SIX_BHK, .SEVEN_BHK, .EIGHT_BHK, .NINE_BHK, .TEN_BHK]
    }

    var title: String {
        switch self {
        case .ONE_BHK: return "1 BHK"
        case .TWO_BHK: return "2 BHK"
        case .THREE_BHK: return "3 BHK"
        case .FOUR_BHK: return "4 BHK"
        case .FIVE_BHK: return "5 BHK"
        case .SIX_BHK: return "6 BHK"
        case .SEVEN_BHK: return "7 BHK"
        case .EIGHT_BHK: return "8 BHK"
        case .NINE_BHK: return "9 BHK"
        case .TEN_BHK: return "10 BHK"
        case .PENTHOUSE: return "Penthouse"
        case .VILLA: return "Villa"
        case .INDEPENDENT_HOUSE: return "Independent house"
        }
    }
}

enum UnitTypeDisplay {
    static func title(for raw: String) -> String {
        UnitTypeOption(rawValue: raw)?.title
            ?? raw.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct CreateUnitBody: Encodable {
    let floorId: UUID
    let unitNumber: String
    let unitType: String
}

struct UpdateUnitBody: Encodable {
    var unitNumber: String?
    var unitType: String?
}

struct UpdateUnitStatusBody: Encodable {
    var occupancyStatus: String?
    var toLetBoardStatus: String?
}

struct CreateTenancyBody: Encodable {
    let tenantUserId: UUID
    let moveInDate: String
}

struct EndTenancyBody: Encodable {
    let moveOutDate: String
}

struct AssignEmployeeBody: Encodable {
    let employeeUserId: UUID
}

struct UpdateServiceRequestStatusBody: Encodable {
    let status: String
    let comments: String?
}

struct UpdateEnquiryStatusBody: Encodable {
    let status: String
}

struct CreateInspectionBody: Encodable {
    let propertyId: UUID
    let unitId: UUID?
    let inspectorEmployeeId: UUID
    let inspectionType: String
    let inspectionDate: String
    let notes: String?
}

struct UpdateInspectionStatusBody: Encodable {
    let status: String
}

struct InvoiceLineItem: Codable, Hashable {
    var id: UUID? = nil
    /// Display/API line text. Named to avoid clashing with `CustomStringConvertible.description`.
    let itemDescription: String
    let quantity: Decimal
    let unitPrice: Decimal
    let lineTotal: Decimal?

    enum CodingKeys: String, CodingKey {
        case id
        case itemDescription = "description"
        case quantity
        case unitPrice
        case lineTotal
    }
}

struct InvoiceItem: Decodable, Identifiable, Hashable {
    let id: UUID
    let invoiceNumber: String?
    let serviceRequestId: UUID?
    let invoiceDate: String?
    let tax: Decimal?
    let discount: Decimal?
    let totalAmount: Decimal?
    let status: String
    let items: [InvoiceLineItem]?
    let createdAt: String?
    let updatedAt: String?
}

/// API body for one invoice line. UI draft rows use `DraftInvoiceLine` (Identifiable) instead.
struct CreateInvoiceLineBody: Encodable, Hashable {
    /// Line text sent to the API as `description`.
    let itemDescription: String
    let quantity: Decimal
    let unitPrice: Decimal

    enum CodingKeys: String, CodingKey {
        case itemDescription = "description"
        case quantity
        case unitPrice
    }
}

/// Local draft row for the create-invoice form (stable `id` is not sent to the API).
struct DraftInvoiceLine: Identifiable, Hashable {
    let id: UUID
    let itemDescription: String
    let quantity: Decimal
    let unitPrice: Decimal

    init(id: UUID = UUID(), itemDescription: String, quantity: Decimal, unitPrice: Decimal) {
        self.id = id
        self.itemDescription = itemDescription
        self.quantity = quantity
        self.unitPrice = unitPrice
    }

    var asBody: CreateInvoiceLineBody {
        CreateInvoiceLineBody(
            itemDescription: itemDescription,
            quantity: quantity,
            unitPrice: unitPrice
        )
    }
}

struct CreateInvoiceBody: Encodable {
    let serviceRequestId: UUID
    let invoiceDate: String
    let tax: Decimal
    let discount: Decimal
    let items: [CreateInvoiceLineBody]
}

struct UpsertTenantVerificationBody: Encodable {
    let permanentAddress: String
    let permanentLocality: String
    let permanentCity: String
    let permanentState: String
    let permanentPincode: String
}

struct ReviewTenantVerificationBody: Encodable {
    let decision: String
    let notes: String?
    var idProofMatchedAddress: Bool? = nil
}

enum ServiceRequestStatusOption: String, CaseIterable, Identifiable {
    case OPEN, ASSIGNED, IN_PROGRESS, WAITING_FOR_PARTS, RESOLVED, CLOSED, REJECTED, CANCELLED
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

enum EnquiryStatusOption: String, CaseIterable, Identifiable {
    case NEW, CONTACTED, PROPERTY_SHARED, VISIT_SCHEDULED, FOLLOW_UP, CONVERTED, NOT_INTERESTED, CLOSED
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

enum InspectionTypeOption: String, CaseIterable, Identifiable {
    case MOVE_IN, MOVE_OUT, PERIODIC, REPAIR, VACANCY
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

enum InspectionStatusOption: String, CaseIterable, Identifiable {
    case SCHEDULED, IN_PROGRESS, COMPLETED, CANCELLED
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}

enum OccupancyStatusOption: String, CaseIterable, Identifiable {
    case TENANTED, VACANT
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ToLetBoardStatusOption: String, CaseIterable, Identifiable {
    case INSTALLED, NOT_INSTALLED
    var id: String { rawValue }
    var title: String { rawValue.replacingOccurrences(of: "_", with: " ") }
}
