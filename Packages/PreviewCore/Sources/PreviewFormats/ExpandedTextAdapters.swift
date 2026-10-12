import Foundation
import PreviewContracts

/// Shared checks also protect direct adapter callers outside PreviewPipeline.
enum ExpandedTextLimits {
    static func validate(_ input: DecodedText, context: RequestContext) throws {
        try context.checkpoint()
        guard input.byteCount <= context.budget.maxInputBytes,
              input.text.utf8.count <= context.budget.maxInputBytes else { throw PreviewFailure.inputTooLarge }
        guard input.text.utf8.count <= context.budget.maxOutputUTF8Bytes else { throw PreviewFailure.outputTooLarge }
        var lines = 1
        var lineBytes = 0
        var previousCR = false
        for (index, byte) in input.text.utf8.enumerated() {
            if index.isMultiple(of: 512) { try context.checkpoint() }
            if byte == 10 || byte == 13 {
                if byte != 10 || !previousCR { lines += 1 }
                guard lines <= context.budget.maxTextLines else { throw PreviewFailure.tooManyLines }
                lineBytes = 0
            } else {
                lineBytes += 1
                guard lineBytes <= context.budget.maxLineUTF8Bytes else { throw PreviewFailure.lineTooLong }
            }
            previousCR = byte == 13
        }
        try context.checkpoint()
    }
}
