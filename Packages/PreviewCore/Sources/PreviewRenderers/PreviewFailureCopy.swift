import Foundation
import PreviewContracts

/// The limit values a failure body may print (decision 027, Q-110). Every field is optional: a limit the caller does not
/// know stays `nil`, and the body then states the failure without a number, because a wrong limit is worse than none.
/// Budgets differ per registration (standard, container, mesh and CAD), so a host passes the effective budget of the
/// request through `init(budget:)` and never a default of its own. A value that is zero or negative counts as unknown.
struct PreviewLimitsSummary: Equatable, Sendable {
    /// The largest input the registration reads, in bytes.
    var inputBytes: Int?
    /// The largest preview the registration produces, in UTF-8 bytes.
    var outputBytes: Int?
    /// The most text lines shown.
    var lines: Int?
    /// The longest line shown, in UTF-8 bytes.
    var lineBytes: Int?
    /// The most structure nodes (values, keys or elements) read.
    var nodes: Int?
    /// The deepest nesting read.
    var depth: Int?
    /// The time allowed for one request, in milliseconds.
    var milliseconds: Int?

    init(inputBytes: Int? = nil, outputBytes: Int? = nil, lines: Int? = nil, lineBytes: Int? = nil,
         nodes: Int? = nil, depth: Int? = nil, milliseconds: Int? = nil) {
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.lines = lines
        self.lineBytes = lineBytes
        self.nodes = nodes
        self.depth = depth
        self.milliseconds = milliseconds
    }

    /// Every limit that a request budget carries.
    init(budget: PreviewBudget) {
        self.init(inputBytes: budget.maxInputBytes, outputBytes: budget.maxOutputUTF8Bytes, lines: budget.maxTextLines,
                  lineBytes: budget.maxLineUTF8Bytes, nodes: budget.maxJSONNodes, depth: budget.maxJSONDepth,
                  milliseconds: budget.maxMilliseconds)
    }
}

/// Title and body wording for every failure and every non-content state, in one place so that the state view only
/// displays it (decision 027, Q-110). A title says what happened; a body says why and ends with the next step, and names
/// the limit when the caller supplies it. Both switches are exhaustive on purpose: a new `PreviewFailure` case or state
/// kind does not compile until it has wording. Nothing here reads file content, and a limit is printed only when the
/// caller passed it. Counted limits are plural sentences, sizes and durations are formatted for `locale`, and
/// `languagePreferences` selects the text language the way the string lookup does (nil follows the hosting process).
/// Keep the lookup call names out of comments: the localization validator scans for them.
enum PreviewFailureCopy {
    /// The title and body for a failed request.
    static func content(for failure: PreviewFailure, locale: Locale, limits: PreviewLimitsSummary? = nil,
                        languagePreferences: [String]? = nil) -> (title: String, body: String) {
        let preferences = languagePreferences
        switch failure {
        case .unsupportedFormat:
            return pair(.failureTitleUnsupportedFormat, .failureBodyUnsupportedFormat, preferences)
        case .missingFile:
            return pair(.failureTitleMissingFile, .failureBodyMissingFile, preferences)
        case .unreadableFile:
            return pair(.failureTitleUnreadableFile, .failureBodyUnreadableFile, preferences)
        case .notRegularFile:
            return pair(.failureTitleNotRegularFile, .failureBodyNotRegularFile, preferences)
        case .unavailableContent:
            return pair(.failureTitleUnavailableContent, .failureBodyUnavailableContent, preferences)
        case .inputTooLarge:
            guard let bytes = known(limits?.inputBytes) else {
                return pair(.failureTitleInputTooLarge, .failureBodyInputTooLarge, preferences)
            }
            return (title: line(.failureTitleInputTooLarge, preferences),
                    body: PreviewStrings.format(.failureBodyInputTooLargeLimit, arguments: [sizeText(bytes, locale: locale)],
                                                locale: locale, languagePreferences: preferences))
        case .outputTooLarge:
            guard let bytes = known(limits?.outputBytes) else {
                return pair(.failureTitleOutputTooLarge, .failureBodyOutputTooLarge, preferences)
            }
            return (title: line(.failureTitleOutputTooLarge, preferences),
                    body: PreviewStrings.format(.failureBodyOutputTooLargeLimit, arguments: [sizeText(bytes, locale: locale)],
                                                locale: locale, languagePreferences: preferences))
        case .binaryContent:
            return pair(.failureTitleBinaryContent, .failureBodyBinaryContent, preferences)
        case .unsupportedEncoding:
            return pair(.failureTitleUnsupportedEncoding, .failureBodyUnsupportedEncoding, preferences)
        case .malformedDocument:
            return pair(.failureTitleMalformedDocument, .failureBodyMalformedDocument, preferences)
        case .encryptedContent:
            return pair(.failureTitleEncryptedContent, .failureBodyEncryptedContent, preferences)
        case .structureTooDeep:
            guard let depth = known(limits?.depth) else {
                return pair(.failureTitleStructureTooDeep, .failureBodyStructureTooDeep, preferences)
            }
            return (title: line(.failureTitleStructureTooDeep, preferences),
                    body: PreviewStrings.count(.failureBodyStructureTooDeepLimit, depth, locale: locale,
                                               languagePreferences: preferences))
        case .tooManyNodes:
            guard let nodes = known(limits?.nodes) else {
                return pair(.failureTitleTooManyNodes, .failureBodyTooManyNodes, preferences)
            }
            return (title: line(.failureTitleTooManyNodes, preferences),
                    body: PreviewStrings.count(.failureBodyTooManyNodesLimit, nodes, locale: locale,
                                               languagePreferences: preferences))
        case .tooManyLines:
            guard let lines = known(limits?.lines) else {
                return pair(.failureTitleTooManyLines, .failureBodyTooManyLines, preferences)
            }
            return (title: line(.failureTitleTooManyLines, preferences),
                    body: PreviewStrings.count(.failureBodyTooManyLinesLimit, lines, locale: locale,
                                               languagePreferences: preferences))
        case .lineTooLong:
            guard let bytes = known(limits?.lineBytes) else {
                return pair(.failureTitleLineTooLong, .failureBodyLineTooLong, preferences)
            }
            return (title: line(.failureTitleLineTooLong, preferences),
                    body: PreviewStrings.format(.failureBodyLineTooLongLimit, arguments: [sizeText(bytes, locale: locale)],
                                                locale: locale, languagePreferences: preferences))
        case .invalidBudget:
            return pair(.failureTitleInvalidBudget, .failureBodyInvalidBudget, preferences)
        case .deadlineExceeded:
            guard let milliseconds = known(limits?.milliseconds) else {
                return pair(.failureTitleDeadlineExceeded, .failureBodyDeadlineExceeded, preferences)
            }
            return (title: line(.failureTitleDeadlineExceeded, preferences),
                    body: PreviewStrings.format(.failureBodyDeadlineExceededLimit,
                                                arguments: [durationText(milliseconds, locale: locale)],
                                                locale: locale, languagePreferences: preferences))
        case .unsupportedVariant:
            return pair(.failureTitleUnsupportedVariant, .failureBodyUnsupportedVariant, preferences)
        case .geometryTooComplex:
            return pair(.failureTitleGeometryTooComplex, .failureBodyGeometryTooComplex, preferences)
        }
    }

    /// The title and body of a state view. Loading has a title and no body; a failure forwards to `content(for:)`.
    static func content(forState state: NativeStateContent.Kind, locale: Locale, limits: PreviewLimitsSummary? = nil,
                        languagePreferences: [String]? = nil) -> (title: String, body: String) {
        let preferences = languagePreferences
        switch state {
        case .loading:
            return (title: line(.loading, preferences), body: "")
        case .empty:
            return pair(.stateEmptyTitle, .stateEmptyBody, preferences)
        case .unavailable(let failure):
            return content(for: failure, locale: locale, limits: limits, languagePreferences: preferences)
        case .disabled:
            return pair(.disabledTitle, .disabledDescription, preferences)
        case .settingsUnavailable:
            return pair(.stateSettingsUnavailableTitle, .extensionSettingsUnavailable, preferences)
        case .configurationUnavailable:
            return pair(.stateConfigurationUnavailableTitle, .extensionSettingsConfigurationUnavailable, preferences)
        }
    }

    // MARK: Helpers

    private static func line(_ key: PreviewStrings.Key, _ preferences: [String]?) -> String {
        PreviewStrings.text(key, languagePreferences: preferences)
    }

    private static func pair(_ title: PreviewStrings.Key, _ body: PreviewStrings.Key,
                             _ preferences: [String]?) -> (title: String, body: String) {
        (title: line(title, preferences), body: line(body, preferences))
    }

    /// A limit counts as known only when it is positive.
    private static func known(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    /// The same byte-count style the companion's limits rows use.
    private static func sizeText(_ bytes: Int, locale: Locale) -> String {
        Int64(bytes).formatted(.byteCount(style: .file).locale(locale))
    }

    private static func durationText(_ milliseconds: Int, locale: Locale) -> String {
        Duration.milliseconds(milliseconds).formatted(.units(allowed: [.seconds, .milliseconds], width: .wide).locale(locale))
    }
}
