import Foundation

enum FinancialCurrencyFormatting {
    private static let displayLocaleCacheLock = NSLock()
    nonisolated(unsafe) private static var displayLocaleCache: [String: Locale] = [:]

    static var sortedISOCurrencyCodes: [String] {
        Locale.commonISOCurrencyCodes.sorted()
    }

    /// Picks a locale whose primary currency is `isoCode` so `NumberFormatter` shows the symbol people use day to day (e.g. NOK → `kr`), instead of spelling out `NOK` when that currency is “foreign” to `Locale.current`.
    static func localeForCurrencyDisplay(isoCode: String) -> Locale {
        let code = normalizedISOCurrencyCode(isoCode)
        displayLocaleCacheLock.lock()
        if let cached = displayLocaleCache[code] {
            displayLocaleCacheLock.unlock()
            return cached
        }
        displayLocaleCacheLock.unlock()

        if Locale.current.currency?.identifier == code {
            displayLocaleCacheLock.lock()
            displayLocaleCache[code] = Locale.current
            displayLocaleCacheLock.unlock()
            return Locale.current
        }

        var resolved = Locale.current
        for identifier in Locale.availableIdentifiers {
            let locale = Locale(identifier: identifier)
            guard locale.currency?.identifier == code else { continue }
            resolved = locale
            break
        }

        displayLocaleCacheLock.lock()
        displayLocaleCache[code] = resolved
        displayLocaleCacheLock.unlock()
        return resolved
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
}
