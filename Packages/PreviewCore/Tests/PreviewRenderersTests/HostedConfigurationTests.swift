import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Hosted configuration")
struct HostedConfigurationTests {
    private func configuration(_ values: [String: String]) -> HostedConfiguration {
        HostedConfiguration(info: { values[$0] })
    }

    @Test func unsetOrUnresolvedValuesAreAbsent() {
        let configuration = configuration(["PreviewDisplayName": "$(PREV_DISPLAY_NAME)", "PreviewWebsiteURL": "",
                                           "PreviewSupportURL": "$(PREV_SUPPORT_URL)", "CFBundleShortVersionString": ""])
        #expect(configuration.displayName == PreviewStrings.text(.genericAppName))
        #expect(configuration.links.isEmpty)
        #expect(configuration.version == nil && configuration.build == nil)
    }

    @Test func prototypeGroupsNeverAdvertiseSharedSettings() {
        #expect(configuration(["PreviewAppGroupIdentifier": "group.invalid.example"]).appGroupIdentifier == nil)
        #expect(configuration(["PreviewAppGroupIdentifier": "group.example.shared"]).appGroupIdentifier == "group.example.shared")
    }

    @Test func webLinksNeedHTTPSAHostAndNoCredentials() {
        let accepted = configuration(["PreviewWebsiteURL": "https://example.com/app", "PreviewDocumentationURL": "HTTPS://example.com"])
        #expect(accepted.links.website?.absoluteString == "https://example.com/app")
        #expect(accepted.links.documentation != nil)
        for rejected in ["http://example.com", "https:", "https:///path", "file:///etc/hosts", "javascript:alert(1)",
                         "https://user:secret@example.com", "https://user@example.com", "mailto:help@example.com", "example.com"] {
            #expect(configuration(["PreviewWebsiteURL": rejected]).links.website == nil, "\(rejected)")
        }
    }

    @Test func mailLinksAreLimitedToSupportAndFeedbackWithARecipient() {
        let accepted = configuration(["PreviewSupportURL": "mailto:help@example.com",
                                      "PreviewFeedbackURL": "mailto:feedback@example.com?subject=Feedback",
                                      "PreviewPrivacyPolicyURL": "mailto:privacy@example.com"])
        #expect(accepted.links.support != nil && accepted.links.feedback != nil)
        #expect(accepted.links.privacyPolicy == nil)
        for rejected in ["mailto:", "mailto:?subject=x", "mailto:x", "mailto:@example.com", "mailto:help@"] {
            #expect(configuration(["PreviewSupportURL": rejected]).links.support == nil, "\(rejected)")
        }
    }

    @Test func theOpenSourceLinkNeedsHTTPSAndCountsAsAConfiguredLink() {
        let accepted = configuration(["PreviewOpenSourceURL": "https://github.com/example/helper-source"])
        #expect(accepted.links.openSource?.absoluteString == "https://github.com/example/helper-source")
        #expect(!accepted.links.isEmpty)
        for rejected in ["http://github.com/example/helper-source", "mailto:help@example.com", "file:///etc/hosts",
                         "https://user:secret@github.com/example/helper-source", "$(PREV_OPEN_SOURCE_URL)", ""] {
            #expect(configuration(["PreviewOpenSourceURL": rejected]).links.openSource == nil, "\(rejected)")
        }
    }

    @Test func versionAndBuildComeFromTheBundle() {
        let configuration = configuration(["CFBundleShortVersionString": "1.2", "CFBundleVersion": "34"])
        #expect(configuration.version == "1.2" && configuration.build == "34")
    }
}
