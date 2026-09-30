import Foundation

/// Response of `GET https://api.deepseek.com/user/balance`.
struct BalanceResponse: Decodable {
    let isAvailable: Bool
    let balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceInfo: Decodable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    var symbol: String {
        switch currency.uppercased() {
        case "CNY": return "¥"
        case "USD": return "$"
        default: return ""
        }
    }

    /// `¥110.00` — falls back to `110.00 CNY` for currencies we have no glyph for.
    var displayTotal: String {
        symbol.isEmpty ? "\(totalBalance) \(currency)" : "\(symbol)\(totalBalance)"
    }

    var displayGranted: String { "\(symbol)\(grantedBalance)" }
    var displayToppedUp: String { "\(symbol)\(toppedUpBalance)" }
}
