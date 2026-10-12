import Foundation
import Testing
@testable import PreviewRenderers

@Suite("Structured views of concealed source")
struct SafeStructuredTextTests {
    @Test func JSONOutlineRetainsNumbersDuplicatesUnicodeAndConcealedValues() throws {
        let source = #"{"😀":9007199254740993123456789,"same":1,"same":2,"password":••••}"#
        let nodes = try #require(SafeStructuredText.json(source))
        #expect(nodes[0].children.map(\.name) == ["😀", "same", "same", "password"])
        #expect(nodes[0].children[0].value == "9007199254740993123456789")
        #expect(nodes[0].children[1].isDuplicateKey)
        #expect(nodes[0].children[2].isDuplicateKey)
        #expect(nodes[0].children[3].value == "••••")
    }
    @Test func rendererBoundsRejectLargeDeepOrMalformedInput() {
        #expect(SafeStructuredText.json("[[[1]]]", maximumDepth: 2) == nil)
        #expect(SafeStructuredText.json("[1,2,3]", maximumNodes: 3) == nil)
        #expect(SafeStructuredText.json("[1,]" ) == nil)
        #expect(SafeStructuredText.json(String(repeating: "1", count: 65), maximumUTF16Units: 64) == nil)
    }
    @Test func YAMLAndTOMLAdvancedSyntaxFallsBackToSource() {
        #expect(SafeStructuredText.configuration("base: &base\ncopy: *base", syntax: .yaml) == nil)
        #expect(SafeStructuredText.configuration("[[products]]\nname=\"one\"", syntax: .toml) == nil)
        #expect(SafeStructuredText.configuration("[package]\nname = \"safe\"\npassword = ••••", syntax: .toml)?.count == 1)
        #expect(SafeStructuredText.configuration("title: safe\nchildren:\n  - one\n  - two", syntax: .yaml)?.count == 2)
    }

    // MARK: YAML sequences written at the indentation of their key

    @Test func aSequenceIndentedLikeItsKeyStaysUnderThatKey() throws {
        let source = "exclude_paths:\n- \"dist/*\"\n- \"build/*\"\nversion: 2\n"
        let nodes = try #require(SafeStructuredText.configuration(source, syntax: .yaml))
        #expect(nodes.map(\.name) == ["exclude_paths", "version"], "The items are not roots beside their key")
        #expect(nodes[0].children.map(\.name) == ["[0]", "[1]"])
        #expect(nodes[0].children.map(\.value) == ["\"dist/*\"", "\"build/*\""])
        #expect(nodes[1].value == "2" && nodes[1].children.isEmpty)
    }

    @Test func compactSequencesNestUnderDeeperKeysAndSiblingsKeepTheirOwnLevel() throws {
        let source = "---\nbuild:\n  exclude:\n  - a\n  - b\n  include:\n  - c\nname: x\nempty:\nlater:\n- last\n"
        let nodes = try #require(SafeStructuredText.configuration(source, syntax: .yaml))
        #expect(nodes.map(\.name) == ["build", "name", "empty", "later"])
        let build = nodes[0].children
        #expect(build.map(\.name) == ["exclude", "include"])
        #expect(build[0].children.map(\.value) == ["a", "b"])
        #expect(build[1].children.map(\.value) == ["c"])
        #expect(nodes[2].children.isEmpty, "A key without a sequence keeps no children")
        #expect(nodes[3].children.map(\.value) == ["last"])
    }

    @Test func anEmptyCompactItemCanHoldAnIndentedSequenceAndLaterItemsStillJoinTheKey() throws {
        let nodes = try #require(SafeStructuredText.configuration("steps:\n-\n  - a\n- c\n", syntax: .yaml))
        #expect(nodes.map(\.name) == ["steps"])
        let items = nodes[0].children
        #expect(items.map(\.name) == ["[0]", "[1]"])
        #expect(items[0].children.map(\.value) == ["a"])
        #expect(items[1].value == "c")
    }

    @Test func aSequenceIndentedDeeperThanItsKeyAndARootSequenceStillWork() throws {
        let nested = try #require(SafeStructuredText.configuration("title: safe\nchildren:\n  - one\n  - two\n", syntax: .yaml))
        #expect(nested.map(\.name) == ["title", "children"])
        #expect(nested[1].children.map(\.name) == ["[0]", "[1]"])
        #expect(nested[1].children.map(\.value) == ["one", "two"])
        let root = try #require(SafeStructuredText.configuration("- a\n- b\n", syntax: .yaml))
        #expect(root.map(\.name) == ["[0]", "[1]"] && root.map(\.value) == ["a", "b"])
    }

    @Test func aSequenceItemWithoutOneOwnerReturnsNilInsteadOfMovingToAnotherLevel() {
        // Beside the mapping entries of the key written at its indentation.
        #expect(SafeStructuredText.configuration("settings:\n  mode: fast\n- orphan\n", syntax: .yaml) == nil)
        // After a key whose sequence is indented deeper: the dedented item has no owner either.
        #expect(SafeStructuredText.configuration("items:\n  - a\n- b\n", syntax: .yaml) == nil)
        // Beside a scalar-valued key at the same level.
        #expect(SafeStructuredText.configuration("name: x\n- b\n", syntax: .yaml) == nil)
        // A key after the items of the same collection, or a key and an item under one parent.
        #expect(SafeStructuredText.configuration("- a\nname: x\n", syntax: .yaml) == nil)
        #expect(SafeStructuredText.configuration("items:\n  - a\n  name: x\n", syntax: .yaml) == nil)
        // A mapping inside a sequence item stays unsupported, whatever the indentation.
        #expect(SafeStructuredText.configuration("steps:\n- name: build\n", syntax: .yaml) == nil)
    }
}
