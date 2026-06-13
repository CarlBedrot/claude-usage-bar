import Foundation

/// USD per MTok for one model, exact-match on the full model id string.
public struct Pricing {
    public let input: Double
    public let output: Double
    public let cacheRead: Double
    public let cacheWrite: Double

    public init(input: Double, output: Double, cacheRead: Double, cacheWrite: Double) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
    }
}

/// Exact values copied from claude_usage.py PRICING. cache_read = 0.1x input,
/// cache_write = 1.25x input (5m tier).
public let PRICING: [String: Pricing] = [
    "claude-fable-5":             Pricing(input: 10.0, output: 50.0, cacheRead: 1.0,  cacheWrite: 12.5),
    "claude-opus-4-8":            Pricing(input: 5.0,  output: 25.0, cacheRead: 0.5,  cacheWrite: 6.25),
    "claude-opus-4-7":            Pricing(input: 5.0,  output: 25.0, cacheRead: 0.5,  cacheWrite: 6.25),
    "claude-opus-4-6":            Pricing(input: 5.0,  output: 25.0, cacheRead: 0.5,  cacheWrite: 6.25),
    "claude-opus-4-5-20251101":   Pricing(input: 5.0,  output: 25.0, cacheRead: 0.5,  cacheWrite: 6.25),
    "claude-sonnet-4-6":          Pricing(input: 3.0,  output: 15.0, cacheRead: 0.3,  cacheWrite: 3.75),
    "claude-sonnet-4-5-20250929": Pricing(input: 3.0,  output: 15.0, cacheRead: 0.3,  cacheWrite: 3.75),
    "claude-haiku-4-5-20251001":  Pricing(input: 1.0,  output: 5.0,  cacheRead: 0.1,  cacheWrite: 1.25),
]

func modelCostUsd(_ counts: Counts, _ pricing: Pricing) -> Double {
    let dollarsPerMtok = Double(counts.input) * pricing.input
        + Double(counts.output) * pricing.output
        + Double(counts.cacheRead) * pricing.cacheRead
        + Double(counts.cacheWrite) * pricing.cacheWrite
    return dollarsPerMtok / 1_000_000
}

/// Estimated cost of today's tokens. '≥' prefix when some tokens are unpriced;
/// "cost n/a (unpriced models)" when every model is unpriced.
public func costRow(perModel: PerModelCounts, pricingTable: [String: Pricing] = PRICING) -> String {
    var pricedCostUsd = 0.0
    var pricedModels = 0
    var unpricedTokens = 0

    for (model, counts) in perModel {
        guard let pricing = pricingTable[model] else {
            unpricedTokens += counts.total
            continue
        }
        pricedModels += 1
        pricedCostUsd += modelCostUsd(counts, pricing)
    }

    if unpricedTokens > 0 && pricedModels == 0 {
        return "cost n/a (unpriced models)"
    }
    let prefix = unpricedTokens > 0 ? "≥ " : ""
    return String(format: "Cost today: %@$%.2f", prefix, pricedCostUsd)
}
