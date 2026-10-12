import AppKit

/// Code role ink and configured font traits compose on the already-installed native paragraphs/cards.
enum NativeCodeBlockStyling {
    @MainActor
    static func apply(_ tokens: [JSONSyntaxToken], to storage: NSTextStorage, stylePass: NativeTextStylePass) {
        for token in tokens {
            let range = token.range
            guard range.location >= 0, range.location != NSNotFound, range.location <= storage.length,
                  range.length > 0, range.length <= storage.length - range.location else { continue }
            let attributes = stylePass.attributes(for: token.role).filter { $0.key == .font || $0.key == .foregroundColor }
            storage.addAttributes(attributes, range: range)
        }
    }
}
