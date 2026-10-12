import Foundation
import PreviewContracts

/// One element of a bounded markup tree. Names are lowercased local names.
struct MarkupElement: Equatable, Sendable {
    let name: String
    let attributes: [MarkupAttribute]
    var children: [MarkupNode] = []

    /// First attribute whose local name matches `name` (`href` also matches `xlink:href`).
    func attribute(_ name: String) -> String? { attributes.first { $0.name == name }?.value }
    /// Attribute matched by its qualified spelling, such as `epub:type`.
    func qualifiedAttribute(_ name: String) -> String? { attributes.first { $0.qualifiedName == name }?.value }

    var childElements: [MarkupElement] {
        children.compactMap { if case .element(let element) = $0 { element } else { nil } }
    }
    func children(named name: String) -> [MarkupElement] { childElements.filter { $0.name == name } }
    func firstChild(named name: String) -> MarkupElement? { childElements.first { $0.name == name } }

    /// First descendant (depth first, document order) with `name`, not including `self`.
    func firstDescendant(named name: String) -> MarkupElement? {
        for child in childElements {
            if child.name == name { return child }
            if let found = child.firstDescendant(named: name) { return found }
        }
        return nil
    }

    /// All descendants named `name` in document order, stopping after `limit` matches.
    func descendants(named name: String, limit: Int = 10_000) -> [MarkupElement] {
        var result: [MarkupElement] = []
        func visit(_ element: MarkupElement) {
            for child in element.childElements {
                guard result.count < limit else { return }
                if child.name == name { result.append(child) }
                visit(child)
            }
        }
        visit(self)
        return result
    }

    /// Concatenated text of this subtree with whitespace runs collapsed to single spaces.
    var textContent: String {
        var pieces: [String] = []
        func visit(_ element: MarkupElement) {
            for child in element.children {
                switch child {
                case .text(let text): pieces.append(text)
                case .element(let nested): visit(nested)
                }
            }
        }
        visit(self)
        return pieces.joined().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

enum MarkupNode: Equatable, Sendable {
    case element(MarkupElement)
    case text(String)
}

/// Builds a tree from tolerant markup with the request's depth and node budgets. Unmatched end tags are
/// ignored and unclosed elements close at the end of input, so structural defects never fail a document
/// that is otherwise readable; only the budgets do.
enum MarkupTreeBuilder {
    static let rootName = "#document"

    static func parse(_ text: String, rawTextElements: Set<String> = ["script", "style"],
                      voidElements: Set<String> = [], context: RequestContext) throws -> MarkupElement {
        var tokenizer = MarkupTokenizer(text, rawTextElements: rawTextElements, voidElements: voidElements, context: context)
        var stack = [MarkupElement(name: rootName, attributes: [])]
        var nodes = 0
        func close(downTo index: Int) {
            while stack.count > index {
                let finished = stack.removeLast()
                stack[stack.count - 1].children.append(.element(finished))
            }
        }
        while let event = try tokenizer.next() {
            switch event {
            case .start(let name, let attributes, let selfClosing):
                nodes += 1
                guard nodes <= context.budget.maxJSONNodes else { throw PreviewFailure.tooManyNodes }
                let element = MarkupElement(name: name, attributes: attributes)
                if selfClosing {
                    stack[stack.count - 1].children.append(.element(element))
                } else {
                    guard stack.count <= context.budget.maxJSONDepth else { throw PreviewFailure.structureTooDeep }
                    stack.append(element)
                }
            case .end(let name):
                if let index = stack.lastIndex(where: { $0.name == name }), index > 0 { close(downTo: index) }
            case .text(let text):
                stack[stack.count - 1].children.append(.text(text))
            }
        }
        close(downTo: 1)
        try context.checkpoint()
        return stack[0]
    }
}
