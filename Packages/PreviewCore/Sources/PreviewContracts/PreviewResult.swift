/// A request's safe outcome and the budget actually selected by the pipeline.
/// A nil budget means selection never reached an enabled, valid registration (for example a disabled
/// type or an invalid request). Hosts must not substitute a generic budget and present it as fact.
public struct PreviewResult: Equatable, Sendable {
    public let outcome: PreviewOutcome
    public let effectiveBudget: PreviewBudget?

    public init(outcome: PreviewOutcome, effectiveBudget: PreviewBudget? = nil) {
        self.outcome = outcome
        self.effectiveBudget = effectiveBudget?.isValid == true ? effectiveBudget : nil
    }
}
