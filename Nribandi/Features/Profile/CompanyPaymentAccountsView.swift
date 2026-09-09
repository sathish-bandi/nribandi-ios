import SwiftUI
import UIKit

/// Read-only list of company UPI / GPay / PhonePe IDs for payers.
struct CompanyPaymentInstructionsSection: View {
    @EnvironmentObject private var appState: AppState

    var footer: String = "Pay using any of these company IDs. There is no in-app payment gateway — staff will mark the invoice paid after they receive your transfer."

    @State private var accounts: [CompanyPaymentAccountItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Section {
            if isLoading && accounts.isEmpty {
                ProgressView("Loading payment IDs…")
            } else if accounts.isEmpty {
                Text(errorMessage ?? "No company payment IDs are configured yet. Ask an admin to add a UPI / GPay / PhonePe ID.")
                    .foregroundStyle(NriTheme.slate)
            } else {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                        Text("\(account.providerTitle): \(account.accountId)")
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        if let notes = account.notes, !notes.isEmpty {
                            Text(notes)
                                .font(.caption)
                                .foregroundStyle(NriTheme.slate)
                        }
                        Button {
                            UIPasteboard.general.string = account.accountId
                        } label: {
                            Label("Copy ID", systemImage: "doc.on.doc")
                        }
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }
            if let errorMessage, !accounts.isEmpty {
                Text(errorMessage).foregroundStyle(NriTheme.terracotta)
            }
        } header: {
            Text("Pay via company UPI")
        } footer: {
            Text(footer)
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            accounts = try await appState.api.companyPaymentAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// ADMIN manage screen: add / update / delete company payment IDs.
struct CompanyPaymentAccountsAdminView: View {
    @EnvironmentObject private var appState: AppState

    @State private var accounts: [CompanyPaymentAccountItem] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var showEditor = false
    @State private var editing: CompanyPaymentAccountItem?

    var body: some View {
        Group {
            if isLoading && accounts.isEmpty {
                ProgressView("Loading…")
            } else if let errorMessage, accounts.isEmpty {
                ContentUnavailableView {
                    Label("Could not load", systemImage: "creditcard")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else if accounts.isEmpty {
                ContentUnavailableView {
                    Label("No payment IDs", systemImage: "creditcard")
                } description: {
                    Text("Add a UPI, GPay, or PhonePe ID that owners and tenants can use for repair invoices.")
                } actions: {
                    Button("Add payment ID") {
                        editing = nil
                        showEditor = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section {
                        ForEach(accounts) { account in
                            Button {
                                editing = account
                                showEditor = true
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(account.displayName)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if !account.active {
                                            Text("Inactive")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(NriTheme.terracotta)
                                        }
                                    }
                                    Text("\(account.providerTitle) · \(account.accountId)")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(NriTheme.slate)
                                    if let notes = account.notes, !notes.isEmpty {
                                        Text(notes)
                                            .font(.caption)
                                            .foregroundStyle(NriTheme.slate)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .onDelete { indexSet in
                            Task { await delete(at: indexSet) }
                        }
                    } footer: {
                        Text("Visible IDs appear on invoices and service requests when payment is pending. No payment gateway is used.")
                    }
                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Payment IDs")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .accessibilityLabel("Add payment ID")
            }
        }
        .sheet(isPresented: $showEditor) {
            CompanyPaymentAccountEditorSheet(existing: editing) {
                showEditor = false
                await load()
            }
            .environmentObject(appState)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            accounts = try await appState.api.companyPaymentAccounts(includeInactive: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) async {
        errorMessage = nil
        for index in offsets {
            let account = accounts[index]
            do {
                try await appState.api.deleteCompanyPaymentAccount(id: account.id)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        await load()
    }
}

private struct CompanyPaymentAccountEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let existing: CompanyPaymentAccountItem?
    var onSaved: () async -> Void

    @State private var provider: PaymentProviderOption = .UPI
    @State private var accountId = ""
    @State private var displayName = ""
    @State private var notes = ""
    @State private var active = true
    @State private var sortOrderText = "0"
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Provider", selection: $provider) {
                        ForEach(PaymentProviderOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    TextField("Account / UPI ID", text: $accountId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Display name", text: $displayName)
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                    Toggle("Active (visible to all users)", isOn: $active)
                    TextField("Sort order", text: $sortOrderText)
                        .keyboardType(.numberPad)
                } footer: {
                    Text("Example local test ID: nribandi.local@oksbi")
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(NriTheme.terracotta) }
                }
            }
            .navigationTitle(existing == nil ? "Add payment ID" : "Edit payment ID")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
            .onAppear { populate() }
        }
    }

    private func populate() {
        guard let existing else { return }
        provider = PaymentProviderOption(rawValue: existing.provider) ?? .UPI
        accountId = existing.accountId
        displayName = existing.displayName
        notes = existing.notes ?? ""
        active = existing.active
        sortOrderText = String(existing.sortOrder ?? 0)
    }

    private func save() async {
        let trimmedId = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId.isEmpty {
            errorMessage = "Enter the UPI / GPay / PhonePe ID."
            return
        }
        if trimmedName.isEmpty {
            errorMessage = "Enter a display name."
            return
        }
        let sortOrder = Int(sortOrderText.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = UpsertCompanyPaymentAccountBody(
            provider: provider.rawValue,
            accountId: trimmedId,
            displayName: trimmedName,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            active: active,
            sortOrder: sortOrder
        )
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            if let existing {
                _ = try await appState.api.updateCompanyPaymentAccount(id: existing.id, body)
            } else {
                _ = try await appState.api.createCompanyPaymentAccount(body)
            }
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
