import Foundation

/// The host passes technical configuration and replaceable branding through its Info.plist.
public struct HostedConfiguration: Sendable {
    /// Optional destinations supplied by branding configuration. A missing or
    /// unsupported value hides its entry; the app never invents an address.
    public struct Links: Equatable, Sendable {
        public let website: URL?
        public let support: URL?
        public let documentation: URL?
        public let privacyPolicy: URL?
        public let feedback: URL?
        /// The public source repository and written offer for the 3D import helper and its library.
        public let openSource: URL?

        public init(website: URL? = nil, support: URL? = nil, documentation: URL? = nil,
                    privacyPolicy: URL? = nil, feedback: URL? = nil, openSource: URL? = nil) {
            self.website = website
            self.support = support
            self.documentation = documentation
            self.privacyPolicy = privacyPolicy
            self.feedback = feedback
            self.openSource = openSource
        }

        public var isEmpty: Bool {
            website == nil && support == nil && documentation == nil && privacyPolicy == nil && feedback == nil
                && openSource == nil
        }
    }

    public let displayName: String
    public let appGroupIdentifier: String?
    public let version: String?
    public let build: String?
    public let links: Links

    public init(bundle: Bundle = .main) {
        self.init(info: { bundle.object(forInfoDictionaryKey: $0) as? String })
    }

    /// Reads the same keys from any dictionary-like source, so checks need no bundle.
    public init(info: (String) -> String?) {
        func value(_ key: InfoKey) -> String? { Self.resolvedValue(info(key.rawValue)) }
        displayName = value(.displayName) ?? value(.bundleDisplayName) ?? PreviewStrings.text(.genericAppName)
        let group = value(.appGroup)
        // Reserved prototype identities cannot advertise shared, signed extension settings.
        appGroupIdentifier = group?.hasPrefix("group.invalid.") == true ? nil : group
        version = value(.version)
        build = value(.build)
        links = Links(website: Self.link(value(.website), schemes: [.https]),
                      support: Self.link(value(.support), schemes: [.https, .mailto]),
                      documentation: Self.link(value(.documentation), schemes: [.https]),
                      privacyPolicy: Self.link(value(.privacyPolicy), schemes: [.https]),
                      feedback: Self.link(value(.feedback), schemes: [.https, .mailto]),
                      openSource: Self.link(value(.openSource), schemes: [.https]))
    }

    private enum InfoKey: String {
        case displayName = "PreviewDisplayName"
        case bundleDisplayName = "CFBundleDisplayName"
        case appGroup = "PreviewAppGroupIdentifier"
        case version = "CFBundleShortVersionString"
        case build = "CFBundleVersion"
        case website = "PreviewWebsiteURL"
        case support = "PreviewSupportURL"
        case documentation = "PreviewDocumentationURL"
        case privacyPolicy = "PreviewPrivacyPolicyURL"
        case feedback = "PreviewFeedbackURL"
        case openSource = "PreviewOpenSourceURL"
    }

    private enum LinkScheme: String {
        case https, mailto
    }

    private static func resolvedValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }

    /// Only explicit web or mail destinations are accepted; file and custom schemes are not.
    /// A web link names a host and carries no credentials; a mail link names a recipient.
    private static func link(_ value: String?, schemes: Set<LinkScheme>) -> URL? {
        guard let value, let components = URLComponents(string: value), let url = components.url,
              let scheme = components.scheme.flatMap({ LinkScheme(rawValue: $0.lowercased()) }),
              schemes.contains(scheme) else { return nil }
        switch scheme {
        case .https:
            guard components.host?.isEmpty == false, components.user == nil, components.password == nil else { return nil }
        case .mailto:
            let recipient = components.path.split(separator: "@", omittingEmptySubsequences: false)
            guard recipient.count == 2, recipient.allSatisfy({ !$0.isEmpty }) else { return nil }
        }
        return url
    }
}
