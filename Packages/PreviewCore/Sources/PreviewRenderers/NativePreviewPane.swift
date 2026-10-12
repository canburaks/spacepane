import SwiftUI
import PreviewContracts

/// The bridge carries immutable, already-concealed data; AppKit owns only text-system state.
public struct NativePreviewPane: NSViewRepresentable {
    /// What to show; nil while the first outcome is still being prepared (see `isLoading`).
    public let outcome: PreviewOutcome?
    public let limits: PreviewBudget?
    /// A request is in flight. With no outcome yet the pane shows its loading state, which draws nothing for a short
    /// grace period; an outcome already on screen stays until its replacement arrives. With neither an outcome nor
    /// a request the pane leaves what it shows untouched.
    public let isLoading: Bool
    public let typography: PreviewTypography
    public let generation: UUID
    public let theme: PreviewTheme
    public let syntaxStyle: PreviewSyntaxStyle
    public let isActive: Bool
    /// The configured display name shown as "Preview by …" in the info badge's tooltip; nil leaves only the
    /// read-only caption.
    public let providerName: String?
    /// Fixes the chrome's density when the host must not follow the pane's width (the Theme page's sample); nil
    /// decides it from the width.
    public let forcedDensity: PreviewChrome.Density?
    @Environment(\.locale) private var locale

    /// The entry point for a pane that may not have an outcome yet: Try Preview and the Theme sample keep one native
    /// view through loading, so its loading state and its content look the same.
    public init(outcome: PreviewOutcome?, isLoading: Bool, typography: PreviewTypography, generation: UUID,
                theme: PreviewTheme = .system, syntaxStyle: PreviewSyntaxStyle = .init(), isActive: Bool = true,
                providerName: String? = nil, forcedDensity: PreviewChrome.Density? = nil, limits: PreviewBudget? = nil) {
        self.providerName = providerName
        self.outcome = outcome
        self.limits = limits
        self.isLoading = isLoading
        self.typography = typography
        self.generation = generation
        self.theme = theme
        self.syntaxStyle = syntaxStyle
        self.isActive = isActive
        self.forcedDensity = forcedDensity
    }

    /// The earlier entry point: a pane whose outcome is always present.
    public init(outcome: PreviewOutcome, typography: PreviewTypography, generation: UUID, theme: PreviewTheme = .system, syntaxStyle: PreviewSyntaxStyle = .init(), isActive: Bool = true, providerName: String? = nil, forcedDensity: PreviewChrome.Density? = nil, limits: PreviewBudget? = nil) {
        self.init(outcome: outcome, isLoading: false, typography: typography, generation: generation, theme: theme,
                  syntaxStyle: syntaxStyle, isActive: isActive, providerName: providerName, forcedDensity: forcedDensity, limits: limits)
    }

    /// A result-bearing pane preserves the actual limits instead of guessing from a format label.
    public init(result: PreviewResult, typography: PreviewTypography, generation: UUID,
                theme: PreviewTheme = .system, syntaxStyle: PreviewSyntaxStyle = .init(), isActive: Bool = true,
                providerName: String? = nil, forcedDensity: PreviewChrome.Density? = nil) {
        self.init(outcome: result.outcome, isLoading: false, typography: typography, generation: generation,
                  theme: theme, syntaxStyle: syntaxStyle, isActive: isActive, providerName: providerName,
                  forcedDensity: forcedDensity, limits: result.effectiveBudget)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }
    public func makeNSView(context: Context) -> NativePreviewView { NativePreviewView(frame: .zero) }
    public static func dismantleNSView(_ nsView: NativePreviewView, coordinator: Coordinator) { nsView.suspendResources() }

    public func updateNSView(_ nsView: NativePreviewView, context: Context) {
        if nsView.providerName != providerName { nsView.providerName = providerName }
        if nsView.forcedDensity != forcedDensity { nsView.forcedDensity = forcedDensity }
        if !isActive { nsView.suspendResources() }
        let showsLoading = outcome == nil && isLoading
        guard context.coordinator.generation != generation || context.coordinator.outcome != outcome || context.coordinator.typography != typography
                || context.coordinator.theme != theme || context.coordinator.syntaxStyle != syntaxStyle || context.coordinator.locale != locale || context.coordinator.isActive != isActive
                || context.coordinator.showsLoading != showsLoading || context.coordinator.limits != limits else { return }
        if let outcome {
            nsView.display(outcome, typography: typography, theme: theme, syntaxStyle: syntaxStyle, locale: locale,
                           resetsContentState: context.coordinator.generation != generation, limits: limits)
        } else if showsLoading {
            nsView.showLoading(typography: typography, theme: theme, syntaxStyle: syntaxStyle, locale: locale)
        }
        context.coordinator.generation = generation
        context.coordinator.outcome = outcome
        context.coordinator.limits = limits
        context.coordinator.typography = typography
        context.coordinator.theme = theme
        context.coordinator.syntaxStyle = syntaxStyle
        context.coordinator.locale = locale
        context.coordinator.isActive = isActive
        context.coordinator.showsLoading = showsLoading
        if isActive { nsView.resumeResources() }
        else { nsView.suspendResources() }
    }

    @MainActor public final class Coordinator {
        fileprivate var generation: UUID?
        fileprivate var outcome: PreviewOutcome?
        fileprivate var limits: PreviewBudget?
        fileprivate var typography: PreviewTypography?
        fileprivate var theme: PreviewTheme?
        fileprivate var syntaxStyle: PreviewSyntaxStyle?
        fileprivate var locale: Locale?
        fileprivate var isActive: Bool?
        fileprivate var showsLoading: Bool?
    }
}
