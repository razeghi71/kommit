import Foundation

enum FinancialCurrencyFormatting {
    static var sortedISOCurrencyCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }

    static func normalizedISOCurrencyCode(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.count == 3, Locale.commonISOCurrencyCodes.contains(trimmed) {
            return trimmed
        }
        return "USD"
    }

    static func defaultCodeForCurrentLocale() -> String {
        normalizedISOCurrencyCode(Locale.current.currency?.identifier ?? "USD")
    }

    static func displaySymbol(for isoCode: String, locale: Locale = .current) -> String {
        let code = normalizedISOCurrencyCode(isoCode)
        if locale.currency?.identifier == code, let symbol = locale.currencySymbol, !symbol.isEmpty {
            return symbol
        }

        let symbols = Locale.availableIdentifiers
            .compactMap { identifier -> String? in
                let candidate = Locale(identifier: identifier)
                guard candidate.currency?.identifier == code else { return nil }
                guard let symbol = candidate.currencySymbol?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !symbol.isEmpty
                else { return nil }
                return symbol
            }

        let filtered = Array(
            Set(symbols.filter { symbol in
                let uppercased = symbol.uppercased()
                return uppercased != code && uppercased != "\(code) "
            })
        )
        if let best = filtered.sorted(by: preferredSymbolOrder).first {
            return best
        }
        return locale.localizedString(forCurrencyCode: code) ?? code
    }

    static func parseDecimalInput(_ raw: String, locale: Locale = .current) -> Double? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.isLenient = true

        let normalized = trimmed
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")

        if let number = formatter.number(from: normalized) {
            return number.doubleValue
        }

        let groupingSeparator = formatter.groupingSeparator ?? ","
        let decimalSeparator = formatter.decimalSeparator ?? "."
        var fallback = normalized.replacingOccurrences(of: " ", with: "")

        if groupingSeparator != decimalSeparator {
            fallback = fallback.replacingOccurrences(of: groupingSeparator, with: "")
        }
        if decimalSeparator != "." {
            fallback = fallback.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        return Double(fallback)
    }

    static func editorAmountString(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .current
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    private static func preferredSymbolOrder(_ lhs: String, _ rhs: String) -> Bool {
        if lhs.count != rhs.count {
            return lhs.count < rhs.count
        }
        return lhs < rhs
    }
}
