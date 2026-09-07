import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Tenant self-service KYC and staff review, including identity document upload.
struct TenantVerificationView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var session: SessionStore

    /// When nil, uses the signed-in user's id (tenant "My KYC").
    var tenantUserId: UUID?
    var tenantName: String?
    var reviewMode: Bool = false

    @State private var item: TenantVerificationItem?
    @State private var address = ""
    @State private var locality = ""
    @State private var city = ""
    @State private var state = ""
    @State private var pincode = ""
    @State private var reviewNotes = ""
    @State private var idProofMatchedAddress = false
    @State private var documentType: IdDocumentTypeOption = .AADHAAR
    @State private var photoItem: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var isUploading = false

    private var resolvedTenantId: UUID? {
        tenantUserId ?? session.user?.id
    }

    private var canEditAddress: Bool {
        !reviewMode && (session.user?.role == .TENANT || session.user?.role == .ADMIN)
    }

    private var canUploadDocs: Bool {
        !reviewMode && (session.user?.role == .TENANT || session.user?.role == .ADMIN)
    }

    private var documents: [TenantVerificationDocumentItem] {
        item?.documents ?? []
    }

    private var canSubmit: Bool {
        guard let item else { return false }
        let addressOk = canSaveAddress || item.hasPermanentAddress
        let docsOk = item.identityRequirementMet == true || !documents.isEmpty
        return addressOk && docsOk
            && item.status != "PENDING_REVIEW"
            && item.status != "VERIFIED"
    }

    var body: some View {
        Group {
            if isLoading && item == nil && errorMessage == nil {
                ProgressView("Loading verification…")
            } else {
                Form {
                    if let name = tenantName ?? item?.tenantName {
                        Section("Tenant") {
                            Text(name)
                        }
                    }

                    Section("Permanent address") {
                        if canEditAddress {
                            TextField("Address", text: $address, axis: .vertical)
                                .lineLimit(2...4)
                            TextField("Locality", text: $locality)
                            TextField("City", text: $city)
                            TextField("State", text: $state)
                            TextField("Pincode", text: $pincode)
                                .keyboardType(.numberPad)
                        } else {
                            LabeledContent("Address", value: item?.permanentAddress ?? "—")
                            LabeledContent("Locality", value: item?.permanentLocality ?? "—")
                            LabeledContent("City", value: item?.permanentCity ?? "—")
                            LabeledContent("State", value: item?.permanentState ?? "—")
                            LabeledContent("Pincode", value: item?.permanentPincode ?? "—")
                        }
                    }

                    Section("Status") {
                        if let item {
                            StatusChip(text: item.status)
                            if let submitted = item.submittedAt {
                                LabeledContent("Submitted", value: submitted)
                            }
                            if let met = item.identityRequirementMet {
                                LabeledContent("Identity docs", value: met ? "Complete" : "Incomplete")
                            }
                            LabeledContent("ID verified", value: (item.idVerified == true) ? "Yes" : "No")
                            if let matched = item.idProofMatchedAddress {
                                LabeledContent("ID address matched", value: matched ? "Yes" : "No")
                            }
                        } else {
                            Text("No verification record yet. Save an address to start.")
                                .foregroundStyle(NriTheme.slate)
                        }
                    }

                    Section {
                        if documents.isEmpty {
                            Text("No identity documents uploaded yet.")
                                .foregroundStyle(NriTheme.slate)
                        } else {
                            ForEach(documents) { doc in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(IdDocumentTypeOption(rawValue: doc.documentType)?.title ?? doc.documentType)
                                        .font(.subheadline.weight(.semibold))
                                    Text(doc.originalFilename ?? "Document")
                                        .font(.footnote)
                                        .foregroundStyle(NriTheme.slate)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        if canUploadDocs {
                            Picker("Document type", selection: $documentType) {
                                ForEach(IdDocumentTypeOption.allCases) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                            PhotosPicker(
                                selection: $photoItem,
                                matching: .images
                            ) {
                                Label(isUploading ? "Uploading…" : "Upload ID photo", systemImage: "doc.badge.plus")
                            }
                            .disabled(isUploading)
                            .onChange(of: photoItem) { _, newItem in
                                guard let newItem else { return }
                                Task { await uploadDocument(newItem) }
                            }
                        }
                    } header: {
                        Text("Identity documents")
                    } footer: {
                        Text(item?.identityRequirement
                            ?? "Upload Aadhaar, or any two other ID proofs (PAN, passport, voter ID, driving licence).")
                    }

                    if canEditAddress {
                        Section {
                            Button(isSaving ? "Saving…" : "Save address") {
                                Task { await upsert() }
                            }
                            .disabled(isSaving || !canSaveAddress)

                            if item != nil {
                                Button("Submit for review") {
                                    Task { await submit() }
                                }
                                .disabled(isSaving || !canSubmit)
                            }
                        } footer: {
                            Text("Save your permanent address and upload identity documents before submitting.")
                        }
                    }

                    if reviewMode {
                        Section("Review") {
                            Toggle("ID proof matches permanent address", isOn: $idProofMatchedAddress)
                            TextField("Notes (optional)", text: $reviewNotes, axis: .vertical)
                                .lineLimit(2...4)
                            Button("Verify") {
                                Task { await review(decision: "VERIFIED") }
                            }
                            .disabled(isSaving)
                            Button("Reject", role: .destructive) {
                                Task { await review(decision: "REJECTED") }
                            }
                            .disabled(isSaving)
                        }
                    }

                    if let errorMessage {
                        Section {
                            Text(errorMessage).foregroundStyle(NriTheme.terracotta)
                        }
                    }
                }
            }
        }
        .navigationTitle(reviewMode ? "KYC review" : "My KYC")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var canSaveAddress: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !locality.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pincode.count == 6
    }

    private func load() async {
        guard let resolvedTenantId else {
            errorMessage = "No tenant user."
            isLoading = false
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await appState.api.tenantVerification(tenantUserId: resolvedTenantId)
            item = loaded
            address = loaded.permanentAddress ?? ""
            locality = loaded.permanentLocality ?? ""
            city = loaded.permanentCity ?? ""
            state = loaded.permanentState ?? ""
            pincode = loaded.permanentPincode ?? ""
            idProofMatchedAddress = loaded.idProofMatchedAddress ?? false
        } catch {
            // First-time KYC may not have a record yet.
            if let api = error as? APIError, case .http(let status, _, _) = api, status == 404 {
                item = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func upsert() async {
        guard let resolvedTenantId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            item = try await appState.api.upsertTenantVerification(
                tenantUserId: resolvedTenantId,
                UpsertTenantVerificationBody(
                    permanentAddress: address.trimmingCharacters(in: .whitespacesAndNewlines),
                    permanentLocality: locality.trimmingCharacters(in: .whitespacesAndNewlines),
                    permanentCity: city.trimmingCharacters(in: .whitespacesAndNewlines),
                    permanentState: state.trimmingCharacters(in: .whitespacesAndNewlines),
                    permanentPincode: pincode
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let resolvedTenantId else { return }
        if !canSubmit {
            errorMessage = "Add permanent address and identity documents before submitting."
            return
        }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            // Ensure latest address is saved if the form was edited.
            if canSaveAddress {
                _ = try await appState.api.upsertTenantVerification(
                    tenantUserId: resolvedTenantId,
                    UpsertTenantVerificationBody(
                        permanentAddress: address.trimmingCharacters(in: .whitespacesAndNewlines),
                        permanentLocality: locality.trimmingCharacters(in: .whitespacesAndNewlines),
                        permanentCity: city.trimmingCharacters(in: .whitespacesAndNewlines),
                        permanentState: state.trimmingCharacters(in: .whitespacesAndNewlines),
                        permanentPincode: pincode
                    )
                )
            }
            item = try await appState.api.submitTenantVerification(tenantUserId: resolvedTenantId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func review(decision: String) async {
        guard let resolvedTenantId else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let trimmed = reviewNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            item = try await appState.api.reviewTenantVerification(
                tenantUserId: resolvedTenantId,
                ReviewTenantVerificationBody(
                    decision: decision,
                    notes: trimmed.isEmpty ? nil : trimmed,
                    idProofMatchedAddress: idProofMatchedAddress
                )
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func uploadDocument(_ pickerItem: PhotosPickerItem) async {
        guard let resolvedTenantId else { return }
        isUploading = true
        errorMessage = nil
        defer {
            isUploading = false
            photoItem = nil
        }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                errorMessage = "Could not read the selected photo."
                return
            }
            let mime = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
            let ext = (mime == "image/png") ? "png" : "jpg"
            _ = try await appState.api.uploadTenantVerificationDocument(
                tenantUserId: resolvedTenantId,
                documentType: documentType.rawValue,
                fileData: data,
                fileName: "\(documentType.rawValue.lowercased()).\(ext)",
                mimeType: mime
            )
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct KycReviewListView: View {
    @EnvironmentObject private var appState: AppState

    @State private var items: [TenantVerificationItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    var embedsInParentNavigation = false

    var body: some View {
        Group {
            if isLoading && items.isEmpty {
                ProgressView("Loading KYC queue…")
            } else if let errorMessage, items.isEmpty {
                ContentUnavailableView("Could not load", systemImage: "person.text.rectangle", description: Text(errorMessage))
            } else if items.isEmpty {
                ContentUnavailableView("No pending KYC", systemImage: "checkmark.seal", description: Text("Submitted tenant verifications will appear here."))
            } else {
                List(items) { item in
                    NavigationLink {
                        TenantVerificationView(
                            tenantUserId: item.tenantUserId,
                            tenantName: item.tenantName,
                            reviewMode: true
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.tenantName ?? "Tenant").font(.headline)
                            if !item.locationLine.isEmpty {
                                Text(item.locationLine).font(.subheadline).foregroundStyle(NriTheme.slate)
                            }
                            HStack {
                                StatusChip(text: item.status)
                                if item.idVerified == true {
                                    StatusChip(text: "ID VERIFIED", emphasized: true)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.plain)
                .refreshable { await load() }
            }
        }
        .navigationTitle("KYC review")
        .toolbar {
            if !embedsInParentNavigation {
                ToolbarItem(placement: .topBarTrailing) { EnvBadge(env: appState.environment) }
            }
        }
        .task { await load() }
        .modifier(OpsOptionalNavigationStack(enabled: !embedsInParentNavigation))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            items = try await appState.api.tenantVerifications(status: "PENDING_REVIEW")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
