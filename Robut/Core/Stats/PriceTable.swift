// PriceTable.swift — API list prices, for "what would this have cost?"
//
// Robut users are on subscriptions; the value of pricing local token
// counts is the API-EQUIVALENT figure ("your $200/mo did $X of API work").
// It is an estimate by construction: list prices snapshotted on a date,
// matched by model-id prefix. Update the table, not the call sites.
//
// Sources (2026-07): Anthropic platform pricing; OpenAI API pricing for
// the gpt-5.6 tier (sol/terra/luna). Cache reads bill at 10% of input on
// both providers; cache writes at 1.25× (5m TTL) / 2× (1h TTL, Claude).

import Foundation

struct ModelPrice: Sendable, Hashable {
    /// USD per million tokens.
    var input: Double
    var output: Double

    var cacheRead: Double { input * 0.10 }
    var cacheWrite5m: Double { input * 1.25 }
    var cacheWrite1h: Double { input * 2.0 }
}

enum PriceTable {

    static let snapshotDate = "2026-07"

    /// Longest-prefix match against the model id, so dated variants
    /// ("claude-haiku-4-5-20251001") resolve without their own row.
    static let prices: [(prefix: String, price: ModelPrice)] = [
        // Anthropic
        ("claude-fable-5", ModelPrice(input: 10.00, output: 50.00)),
        ("claude-opus-4", ModelPrice(input: 5.00, output: 25.00)),
        ("claude-sonnet-5", ModelPrice(input: 3.00, output: 15.00)),
        ("claude-sonnet-4", ModelPrice(input: 3.00, output: 15.00)),
        ("claude-haiku-4-5", ModelPrice(input: 1.00, output: 5.00)),
        // OpenAI (Codex CLI models)
        ("gpt-5.6-sol", ModelPrice(input: 5.00, output: 30.00)),
        ("gpt-5.6-terra", ModelPrice(input: 2.50, output: 15.00)),
        ("gpt-5.6-luna", ModelPrice(input: 1.00, output: 6.00)),
        ("gpt-5", ModelPrice(input: 1.25, output: 10.00)),
    ]

    static func price(forModel model: String) -> ModelPrice? {
        prices
            .filter { model.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .price
    }

    /// API-equivalent USD for a tally under a model's list prices.
    /// nil when the model isn't in the table — display layers should say
    /// "unpriced" rather than silently drop the tokens.
    static func cost(of tally: TokenTally, model: String) -> Double? {
        guard let price = price(forModel: model) else { return nil }
        let millions = 1_000_000.0
        var usd = Double(tally.input) / millions * price.input
        usd += Double(tally.output) / millions * price.output
        usd += Double(tally.cacheRead) / millions * price.cacheRead
        usd += Double(tally.cacheWrite5m) / millions * price.cacheWrite5m
        usd += Double(tally.cacheWrite1h) / millions * price.cacheWrite1h
        return usd
    }
}
