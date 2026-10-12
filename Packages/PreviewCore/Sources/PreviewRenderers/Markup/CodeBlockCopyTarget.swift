import Foundation

/// A retained code action identifies one body in one displayed revision, never a stored text copy.
struct CodeBlockCopyTarget: Equatable, Sendable {
    let revision: UUID
    let block: MarkupCodeBlock
}
