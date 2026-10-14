import Foundation
import PreviewContracts

/// Admits listed tensors only while their escaped text keeps the summary well inside the request's output
/// budget, so a file whose tensor names are made of control characters (each escapes to six bytes) is
/// listed in part instead of failing the whole preview. Shared by both model adapters.
struct ModelListingBudget {
    /// Per-entry allowance for the fixed JSON syntax and the short fields (type, shape, parameter count).
    private static let entryOverhead = 192
    private var remaining: Int

    init(context: RequestContext) {
        remaining = min(800_000, context.budget.maxOutputUTF8Bytes / 3)
    }

    /// Whether an entry with these texts still fits; a refused entry leaves the budget unchanged.
    mutating func admit(_ texts: String...) -> Bool {
        let cost = Self.entryOverhead + texts.reduce(0) { $0 + ListingBudget.escapedUTF8Count($1) }
        guard cost <= remaining else { return false }
        remaining -= cost
        return true
    }
}
