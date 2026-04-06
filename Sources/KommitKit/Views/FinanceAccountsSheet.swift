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

private struct FinanceAccountRowCard: View {
    let account: FinanceAccount
    @ObservedObject var viewModel: KommitViewModel
    var onEdit: () -> Void
    var onDelete: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    private var creditSubtitle: String? {
        guard account.isCreditAccount else { return nil }
        if let limit = account.creditLimit {
            return "Limit \(viewModel.formatFinancialCurrency(limit))"
        }
        return "No limit set"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button(action: onEdit) {
                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.primary.opacity(0.07))
                        Image(systemName: account.isCreditAccount ? "creditcard.fill" : "building.columns.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(account.name.isEmpty ? "Untitled" : account.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            if account.isCreditAccount {
                                Text("Credit")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Color.orange.opacity(0.95))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.16))
                                    .clipShape(Capsule(style: .continuous))
                            }
                        }

                        if let creditSubtitle {
                            Text(creditSubtitle)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(viewModel.formatFinancialCurrency(account.balance))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit account")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(FinanceAccountTrashButtonStyle(isRowHovered: isHovered))
            .help("Delete account")
        }
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(rowFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 1)
        }
        .onHover { isHovered = $0 }
    }

    private var rowBorder: Color {
        Color.primary.opacity(isHovered ? 0.14 : 0.08)
    }

    private var rowFill: Color {
        if isHovered {
            return Color.primary.opacity(colorScheme == .dark ? 0.10 : 0.05)
        }
        return Color.primary.opacity(colorScheme == .dark ? 0.06 : 0.03)
    }
}

private struct FinanceAccountTrashButtonStyle: ButtonStyle {
    var isRowHovered: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (isRowHovered ? 0.07 : 0.04)))
            }
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
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button {
                    formRoute = .add
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(KommitIconButtonStyle())
                .help("Add account")
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.financeAccounts.isEmpty {
                        financeAccountsEmptyState
                    } else {
                        ForEach(viewModel.financeAccounts) { account in
                            FinanceAccountRowCard(account: account, viewModel: viewModel) {
                                formRoute = .edit(account.id)
                            } onDelete: {
                                viewModel.removeFinanceAccount(id: account.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(minWidth: 380, minHeight: 360)
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

    private var financeAccountsEmptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "building.columns.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)
            VStack(spacing: 6) {
                Text("No accounts yet")
                    .font(.system(size: 14, weight: .semibold))
                Text("Add at least one account so your calendar balance matches what you hold.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            Button("Add account") {
                formRoute = .add
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
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
