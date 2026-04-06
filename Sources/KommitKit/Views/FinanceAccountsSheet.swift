import SwiftUI

/// How the accounts UI was opened from the finance calendar header.
package enum FinanceAccountsSheetLaunch: Identifiable, Equatable {
    case manage
    case addAccount

    package var id: String {
        switch self {
        case .manage: "manage"
        case .addAccount: "addAccount"
        }
    }
}

private enum FinanceAccountFormRoute: Identifiable, Hashable {
    case add
    case edit(UUID)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let uuid): uuid.uuidString
        }
    }
}

private struct FinanceAccountListRowLabel: View {
    let account: FinanceAccount
    @ObservedObject var viewModel: KommitViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(account.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(viewModel.formatFinancialCurrency(account.balance))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)
                if account.isCreditAccount {
                    if let limit = account.creditLimit {
                        Text("Limit \(viewModel.formatFinancialCurrency(limit))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("No limit set")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 8)
            if account.isCreditAccount {
                Text("Credit")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.22))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct FinanceAccountRowButtonStyle: ButtonStyle {
    var isHovered: Bool
    @Environment(\.colorScheme) private var colorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(fill(pressed: configuration.isPressed))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(border(pressed: configuration.isPressed), lineWidth: 1)
            }
    }

    private func fill(pressed: Bool) -> Color {
        if pressed {
            return Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.10)
        }
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.07)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.04)
    }

    private func border(pressed: Bool) -> Color {
        Color.primary.opacity(pressed ? 0.28 : (isHovered ? 0.20 : 0.14))
    }
}

private struct FinanceAccountRow: View {
    let account: FinanceAccount
    @ObservedObject var viewModel: KommitViewModel
    var onEdit: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onEdit) {
            FinanceAccountListRowLabel(account: account, viewModel: viewModel)
        }
        .buttonStyle(FinanceAccountRowButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
    }
}

/// Lists document accounts and hosts add/edit forms. Starting calendar balance is the sum of account balances.
package struct FinanceAccountsSheet: View {
    @ObservedObject var viewModel: KommitViewModel
    let launch: FinanceAccountsSheetLaunch
    @Environment(\.dismiss) private var dismiss

    @State private var formRoute: FinanceAccountFormRoute?
    @State private var appliedLaunch = false

    package init(viewModel: KommitViewModel, launch: FinanceAccountsSheetLaunch) {
        self.viewModel = viewModel
        self.launch = launch
    }

    package var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                Text("Accounts")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            Text("Tap a row to edit. ⌫ deletes a selected row.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)

            List {
                if viewModel.financeAccounts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No accounts yet")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Add accounts to set your starting balance.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                ForEach(viewModel.financeAccounts) { account in
                    FinanceAccountRow(account: account, viewModel: viewModel) {
                        formRoute = .edit(account.id)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteAccounts)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)

            Divider()

            HStack {
                Spacer()
                Button {
                    formRoute = .add
                } label: {
                    Label("Add account", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                .help("Add a new account")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 340, minHeight: 320)
        .onAppear {
            guard !appliedLaunch else { return }
            appliedLaunch = true
            if launch == .addAccount {
                formRoute = .add
            }
        }
        .sheet(item: $formRoute) { route in
            FinanceAccountEditorSheet(viewModel: viewModel, route: route) {
                formRoute = nil
            }
        }
    }

    private func deleteAccounts(at offsets: IndexSet) {
        viewModel.removeFinanceAccounts(at: offsets)
    }
}

private struct FinanceAccountEditorSheet: View {
    @ObservedObject var viewModel: KommitViewModel
    let route: FinanceAccountFormRoute
    var onDismiss: () -> Void

    @State private var name: String = ""
    @State private var balanceText: String = ""
    @State private var isCreditAccount: Bool = false
    @State private var creditLimitText: String = ""

    private var editingID: UUID? {
        if case .edit(let id) = route { return id }
        return nil
    }

    private var isEditing: Bool { editingID != nil }

    private var parsedBalance: Double? {
        let t = balanceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        return FinancialCurrencyFormatting.parseDecimalInput(balanceText)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedBalance != nil
    }

    private var balanceFieldPlaceholder: String {
        isCreditAccount ? "e.g. -1200" : "e.g. 2500"
    }

    private var creditLimitPlaceholder: String {
        "e.g. 10000"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel", action: onDismiss)
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text(isEditing ? "Edit account" : "New account")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    FieldGroup("Account") {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Name")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            KommitTextField("e.g. Checking, Visa", text: $name)
                        }

                        Toggle("Credit account", isOn: $isCreditAccount)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Balance")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                Text(viewModel.effectiveFinancialCurrencySymbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                KommitTextField(balanceFieldPlaceholder, text: $balanceText)
                                    .font(.system(size: 14, design: .monospaced))
                            }
                        }

                        if isCreditAccount {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("Credit limit")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                    Text("optional")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.06))
                                        .clipShape(Capsule())
                                }
                                HStack(spacing: 8) {
                                    Text(viewModel.effectiveFinancialCurrencySymbol)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                    KommitTextField(creditLimitPlaceholder, text: $creditLimitText)
                                        .font(.system(size: 14, design: .monospaced))
                                }
                            }
                        }
                    }

                    if isEditing, let id = editingID {
                        Button("Delete account", role: .destructive) {
                            viewModel.removeFinanceAccount(id: id)
                            onDismiss()
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(20)
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .onAppear(perform: loadDraft)
    }

    private func loadDraft() {
        switch route {
        case .add:
            name = ""
            balanceText = ""
            isCreditAccount = false
            creditLimitText = ""
        case .edit(let id):
            guard let existing = viewModel.financeAccounts.first(where: { $0.id == id }) else {
                name = ""
                balanceText = ""
                isCreditAccount = false
                creditLimitText = ""
                return
            }
            name = existing.name
            balanceText = FinancialCurrencyFormatting.editorAmountString(existing.balance)
            isCreditAccount = existing.isCreditAccount
            creditLimitText = existing.creditLimit.map { FinancialCurrencyFormatting.editorAmountString($0) } ?? ""
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let balance = parsedBalance else { return }
        let limitParsed = FinancialCurrencyFormatting.parseDecimalInput(creditLimitText)
        let creditLimit: Double? = {
            guard isCreditAccount else { return nil }
            guard let v = limitParsed else { return nil }
            return max(0, v)
        }()
        let id = editingID ?? UUID()
        let account = FinanceAccount(
            id: id,
            name: trimmed,
            balance: balance,
            isCreditAccount: isCreditAccount,
            creditLimit: creditLimit
        )
        viewModel.upsertFinanceAccount(account)
        onDismiss()
    }
}
