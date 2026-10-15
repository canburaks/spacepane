import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

/// Synthetic OpenAPI and Swagger documents for the endpoint table (tier 1 item 5, workstream tq-openapi). Every fixture
/// is built in test code and read through the same concealed JSON outline that `SafePreviewModes` uses.
enum TqOpenAPIFixtures {
    /// A document with `count` path items, each with one GET operation and no children. It stays under the outline's
    /// node and byte limits, so the table, not the outline, is what the cap limits.
    static func cappedSpec(paths count: Int) -> String {
        let items = (0..<count).map { #""/p\#($0)": {"get": {}}"# }.joined(separator: ",")
        return #"{"openapi": "3.0.3", "paths": {"# + items + "}}"
    }
}

@Suite("OpenAPI endpoint table")
struct TqOpenAPIEndpointTableTests {
    private var yes: String { PreviewStrings.text(.summaryBooleanTrue) }

    private func root(_ json: String) throws -> SafeOutlineNode {
        try #require(SafeStructuredText.json(json)?.first)
    }

    private func list(_ json: String) throws -> OpenAPIEndpointList {
        try #require(OpenAPIEndpointList.derive(from: try root(json)))
    }

    @Test func openAPI30ListsEachOperationInFileOrderWithItsMethodPathSummaryAndMarker() throws {
        let spec = """
        {
          "openapi": "3.0.3",
          "info": {"title": "Pets", "version": "1.0.0"},
          "paths": {
            "/pets": {
              "get": {"summary": "List pets", "operationId": "listPets"},
              "post": {"operationId": "createPet"}
            },
            "/pets/{id}": {
              "parameters": [{"name": "id", "in": "path", "required": true}],
              "delete": {"summary": "Delete a pet", "deprecated": true},
              "patch": {"summary": "", "operationId": "patchPet"}
            }
          }
        }
        """
        let value = try list(spec)
        #expect(value.table.columns == [PreviewStrings.text(.dataMethod), PreviewStrings.text(.summaryPath),
                                        PreviewStrings.text(.previewModeSummary),
                                        PreviewStrings.text(.openAPIColumnDeprecated)])
        #expect(value.table.rows == [
            ["GET", "/pets", "List pets", ""],
            ["POST", "/pets", "createPet", ""],
            ["DELETE", "/pets/{id}", "Delete a pet", yes],
            ["PATCH", "/pets/{id}", "patchPet", ""]
        ])
        #expect(value.totalOperations == 4)
        #expect(value.unresolvedReferences == 0)
        #expect(value.table.truncation.isEmpty)
    }

    @Test func theDeprecatedColumnIsEnglishAndOnlyTrueMarksAnOperation() throws {
        #expect(PreviewStrings.text(.openAPIColumnDeprecated, languagePreferences: ["en"]) == "Deprecated")
        #expect(PreviewStrings.text(.summaryBooleanTrue, languagePreferences: ["en"]) == "Yes")
        let value = try list(#"{"openapi": "3.0.3", "paths": {"/a": {"get": {"deprecated": false}, "put": {}}}}"#)
        #expect(value.table.rows == [["GET", "/a", "", ""], ["PUT", "/a", "", ""]])
    }

    @Test func openAPI31AndSwagger20AreRecognizedToo() throws {
        let v31 = try list(#"{"openapi": "3.1.0", "paths": {"/ping": {"head": {"operationId": "ping"}, "trace": {}}}}"#)
        #expect(v31.table.rows == [["HEAD", "/ping", "ping", ""], ["TRACE", "/ping", "", ""]])
        // A key that is not a path template ("x-internal") is an extension, not a path item.
        let v2 = try list(#"{"swagger": "2.0", "paths": {"/users": {"get": {"summary": "Users"}}, "x-internal": {"get": {}}}}"#)
        #expect(v2.table.rows == [["GET", "/users", "Users", ""]])
    }

    @Test func documentsWithoutAMatchingVersionOrObjectPathsGetNoEndpointTable() throws {
        let notSpecifications = [
            #"{"paths": {"/a": {"get": {}}}}"#,
            #"{"openapi": "2.0", "paths": {}}"#,
            #"{"swagger": "3.0", "paths": {}}"#,
            #"{"swagger": "2", "paths": {}}"#,
            #"{"openapi": "3.0.3"}"#,
            #"{"openapi": "3.0.3", "paths": []}"#,
            #"{"openapi": "3.0.3", "paths": "/a"}"#,
            #"[{"openapi": "3.0.3", "paths": {}}]"#
        ]
        for json in notSpecifications {
            let value = try OpenAPIEndpointList.derive(from: root(json))
            #expect(value == nil, "\(json) is not an OpenAPI or Swagger document")
        }
    }

    @Test func aDocumentWithEmptyPathsIsRecognizedWithoutRows() throws {
        let value = try list(#"{"openapi": "3.0.3", "paths": {}}"#)
        #expect(value.table.rows.isEmpty)
        #expect(value.totalOperations == 0)
    }

    @Test func summaryFallsBackToOperationIdWhenTheSummaryIsMissingOrEmpty() throws {
        let value = try list(#"{"openapi": "3.0.3", "paths": {"/a": {"get": {"operationId": "one"}, "put": {"summary": "", "operationId": "two"}, "post": {}}}}"#)
        #expect(value.table.rows == [["GET", "/a", "one", ""], ["PUT", "/a", "two", ""], ["POST", "/a", "", ""]])
    }

    @Test func localReferencesResolveThroughChainsAndOtherReferencesAreCountedNotListed() throws {
        let spec = """
        {
          "openapi": "3.0.3",
          "paths": {
            "/a": {"$ref": "#/paths/~1b"},
            "/b": {"get": {"operationId": "b"}},
            "/c": {"$ref": "other.yaml#/paths/~1c"},
            "/d": {"$ref": "#/components/pathItems/Missing"},
            "/e": {"$ref": "#/paths/~1a"}
          }
        }
        """
        let value = try list(spec)
        #expect(value.table.rows == [["GET", "/a", "b", ""], ["GET", "/b", "b", ""], ["GET", "/e", "b", ""]])
        #expect(value.unresolvedReferences == 2)
        #expect(value.totalOperations == 3)
    }

    @Test func referenceCyclesStopAndCountAsUnresolved() throws {
        let value = try list(#"{"openapi": "3.0.3", "paths": {"/x": {"$ref": "#/paths/~1y"}, "/y": {"$ref": "#/paths/~1x"}}}"#)
        #expect(value.table.rows.isEmpty)
        #expect(value.unresolvedReferences == 2)
    }

    @Test func ownOperationsStayListedWhileAnUnfollowableReferenceIsStillCounted() throws {
        let value = try list(#"{"openapi": "3.0.3", "paths": {"/x": {"get": {"operationId": "x"}, "$ref": "other.yaml"}}}"#)
        #expect(value.table.rows == [["GET", "/x", "x", ""]])
        #expect(value.unresolvedReferences == 1)
    }

    @Test func jsonPointerEscapesAndPercentEncodingResolveToTheirTarget() throws {
        let spec = """
        {
          "openapi": "3.0.3",
          "paths": {
            "/a/b": {"get": {"operationId": "ab"}},
            "/t~x": {"put": {"operationId": "tx"}},
            "/a b": {"delete": {"operationId": "sp"}},
            "/by-slash": {"$ref": "#/paths/~1a~1b"},
            "/by-tilde": {"$ref": "#/paths/~1t~0x"},
            "/by-space": {"$ref": "#/paths/~1a%20b"}
          }
        }
        """
        let value = try list(spec)
        #expect(value.table.rows == [
            ["GET", "/a/b", "ab", ""], ["PUT", "/t~x", "tx", ""], ["DELETE", "/a b", "sp", ""],
            ["GET", "/by-slash", "ab", ""], ["PUT", "/by-tilde", "tx", ""], ["DELETE", "/by-space", "sp", ""]
        ])
        #expect(value.unresolvedReferences == 0)
    }

    @Test func localPointersNameTheirTargetsAndOtherReferencesNameNothing() throws {
        let document = try root(#"{"paths": {"/a~b": {"get": {}}}}"#)
        #expect(OpenAPIReferenceResolver.target(of: "#", in: document)?.value == "{…}")
        #expect(OpenAPIReferenceResolver.target(of: "#/paths/~1a~0b", in: document)?.children.map(\.name) == ["get"])
        #expect(OpenAPIReferenceResolver.target(of: "#/paths/~1missing", in: document) == nil)
        #expect(OpenAPIReferenceResolver.target(of: "other.yaml#/paths", in: document) == nil)
        #expect(OpenAPIReferenceResolver.target(of: "https://example.com/spec.json#/paths", in: document) == nil)
    }

    @Test func rowsStopAtTheCapButEveryOperationIsCounted() throws {
        let cap = OpenAPIEndpointList.maximumRows
        #expect(cap == 5_000)
        let value = try list(TqOpenAPIFixtures.cappedSpec(paths: cap + 1))
        #expect(value.table.rows.count == cap)
        #expect(value.table.truncation == [.rows])
        #expect(value.totalOperations == cap + 1)
        #expect(value.table.rows.first == ["GET", "/p0", "", ""])
        #expect(value.table.rows.last == ["GET", "/p\(cap - 1)", "", ""])
    }
}
