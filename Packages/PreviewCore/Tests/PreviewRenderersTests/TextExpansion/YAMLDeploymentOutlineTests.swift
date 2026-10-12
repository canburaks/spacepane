import Foundation
import Testing
import PreviewContracts
import PreviewCore
import PreviewFormats
@testable import PreviewRenderers

private struct InlineSourceReader: PreviewFileReading {
    let data: Data
    func read(url: URL, context: RequestContext) throws -> FileBytes {
        try context.checkpoint()
        return FileBytes(data: data, totalByteCount: data.count)
    }
}

@Suite("YAML deployment documents get an outline")
struct YAMLDeploymentOutlineTests {
    static let harborDeploy = """
    # Harbor deployment (synthetic sample)
    service: harbor-api
    replicas: 3
    image: registry.harbor.example/harbor-api:1.4.0

    database:
      host: db.harbor.example
      port: 5432
      user: harbor_app
      password: harbor-demo-password-not-real

    auth:
      issuer: https://login.harbor.example
      api_token: harbor-demo-token-not-a-real-credential
      client_secret: harbor-demo-client-secret-not-real

    alerts:
      storm_wind_knots: 34
      notify:
        - harbor-master@harbor.example
        - duty-officer@harbor.example

    resources:
      cpu: 500m
      memory: 512Mi

    """

    private func modes(_ text: String) async throws -> (TextPresentation, SafePreviewModes) {
        let pipeline = PreviewPipeline(registrations: StandardFormatAdapters.registrations,
                                       reader: InlineSourceReader(data: Data(text.utf8)))
        guard case .ready(let presentation) = await pipeline.preview(url: URL(fileURLWithPath: "/unused/deploy.yaml"),
                                                                     budget: PreviewBudget(maxMilliseconds: 30_000)) else {
            Issue.record("No ready presentation"); throw CancellationError()
        }
        return (presentation, SafePreviewModes(presentation, locale: Locale(identifier: "en_US")))
    }

    /// What is true under the conservative privacy rule: a sensitive key whose value is empty (`auth:`, here a
    /// whole block of credentials) conceals everything from there to the end of the text, because indentation is
    /// not trusted to bound it. The structured view therefore shows the part before that key, ending with the
    /// concealed key, and not the keys that follow it. Concealment is not weakened to show more.
    @Test func theStoreDemoDeploymentFileConcealsItsSecretsAndOutlinesTheVisiblePart() async throws {
        let (presentation, modes) = try await modes(Self.harborDeploy)
        for secret in ["harbor-demo-password-not-real", "harbor-demo-token-not-a-real-credential",
                       "harbor-demo-client-secret-not-real", "login.harbor.example"] {
            #expect(!presentation.text.contains(secret), "\(secret) is visible:\n\(presentation.text)")
        }
        #expect(presentation.redactionCount > 0)
        #expect(!modes.hasStructureFallback, "The outline is offered for the visible part:\n\(presentation.text)")
        let outline = try #require(modes.outline)
        #expect(outline.map(\.name) == ["service", "replicas", "image", "database", "auth"])
        let database = try #require(outline.first { $0.name == "database" })
        #expect(database.children.map(\.name) == ["host", "port", "user", "password"])
        #expect(database.children.first { $0.name == "password" }?.value == SecretFieldPolicy.concealmentToken)
        #expect(outline.first { $0.name == "auth" }?.value == SecretFieldPolicy.concealmentToken)
        // The keys after `auth:` are concealed with it, so they are not in the text or the outline.
        #expect(!presentation.text.contains("alerts") && !outline.contains { $0.name == "alerts" })
    }

    /// The common case: an ordinary secret scalar inside a nested mapping is concealed on its own line, and the
    /// rest of the document keeps its outline.
    @Test func aNestedMappingWithAnOrdinaryConcealedScalarKeepsItsOutline() async throws {
        let source = "database:\n  host: db.internal\n  password: hunter2-FAKE\n  port: 5432\nlogging:\n  level: info\n"
        let (presentation, modes) = try await modes(source)
        #expect(!presentation.text.contains("hunter2-FAKE"))
        #expect(!modes.hasStructureFallback, "Fell back to source:\n\(presentation.text)")
        let outline = try #require(modes.outline)
        #expect(outline.map(\.name) == ["database", "logging"])
        let database = try #require(outline.first)
        #expect(database.children.map(\.name) == ["host", "password", "port"])
        #expect(database.children.map(\.value) == ["db.internal", SecretFieldPolicy.concealmentToken, "5432"])
        #expect(outline[1].children.map(\.name) == ["level"] && outline[1].children.first?.value == "info")
    }
}
