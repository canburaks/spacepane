import Foundation
import PreviewContracts

/// Applies a `SourceLanguageProfile` to already-concealed text in one linear pass over UTF-16 code
/// units. Every unit is visited a bounded number of times: openers are compared by length, strings and
/// comments advance to their ends exactly once, and an unterminated construct ends at the end of its
/// line (strings) or of the text (block comments, multi-line strings). Token ranges are exact UTF-16
/// offsets and never overlap. The tokenizer never changes text and recognizes no grammar; at most
/// `maximumTokens` tokens are returned, in order, so a very large file is colored from its start.
enum ProfiledSourceTokenizer {
    static func tokens(in units: [UInt16], profile: SourceLanguageProfile, maximumTokens: Int) -> [JSONSyntaxToken] {
        var engine = Engine(units: units, profile: profile, maximumTokens: maximumTokens)
        if profile.markup != nil { engine.runMarkup() } else { engine.run() }
        return engine.result
    }

    private struct Engine {
        let units: [UInt16]
        let profile: SourceLanguageProfile
        let maximumTokens: Int
        var result: [JSONSyntaxToken] = []
        var index = 0
        /// Whether anything other than blanks precedes the current position on its line.
        var lineHasContent = false

        init(units: [UInt16], profile: SourceLanguageProfile, maximumTokens: Int) {
            self.units = units
            self.profile = profile
            self.maximumTokens = maximumTokens
        }

        var isFull: Bool { result.count >= maximumTokens }

        mutating func emit(_ start: Int, _ end: Int, _ role: PreviewSyntaxRole) {
            guard end > start, !isFull else { return }
            result.append(JSONSyntaxToken(range: NSRange(location: start, length: end - start), role: role))
        }

        // MARK: Main loop

        mutating func run() {
            while index < units.count, !isFull {
                let unit = units[index]
                if unit == 10 || unit == 13 { index += 1; lineHasContent = false; continue }
                if unit == 32 || unit == 9 { index += 1; continue }
                step(unit)
                lineHasContent = true
            }
        }

        private mutating func step(_ unit: UInt16) {
            if tryStarters(unit) { return }
            if profile.longBrackets, unit == 91, let end = longBracketEnd(at: index) {
                emit(index, end, .string); index = end; return
            }
            if profile.hashDelimitedStrings, unit == 35, let end = hashDelimitedStringEnd(hashStart: index) {
                emit(index, end, .string); index = end; return
            }
            if tryPreprocessor(unit) { return }
            if profile.rustAttributes, unit == 35, tryRustAttribute() { return }
            if isDecoratorStart(unit) { scanDecorator(); return }
            if profile.variableSigils.contains(unit), index + 1 < units.count, isIdentifierStart(units[index + 1]) {
                index += 1
                while index < units.count, isIdentifierPart(units[index]) { index += 1 }
                return
            }
            if startsNumber(unit) {
                let end = numberEnd(from: index)
                emit(index, end, .number)
                index = end
                return
            }
            if isIdentifierStart(unit) { scanIdentifier(); return }
            if profile.operators.contains(unit) {
                let start = index
                index += 1
                while index < units.count, profile.operators.contains(units[index]), !startsComment(at: index) { index += 1 }
                emit(start, index, .operator)
                return
            }
            index += 1
        }

        // MARK: Comments and strings

        private mutating func tryStarters(_ unit: UInt16) -> Bool {
            guard let candidates = profile.starters[unit] else { return false }
            for candidate in candidates {
                switch candidate {
                case .lineComment(let spec):
                    guard matches(spec.marker, at: index) else { continue }
                    if spec.lineStartOnly, lineHasContent { continue }
                    if spec.atWordStart, !isAtWordStart(index) { continue }
                    if spec.notBeforeSymbol, let next = unitAt(index + spec.marker.count), Self.isSymbol(next) { continue }
                    if profile.longBrackets, spec.marker == [45, 45],
                       let end = longBracketEnd(at: index + 2) {
                        emit(index, end, .comment); index = end; return true
                    }
                    var end = index
                    while end < units.count, units[end] != 10, units[end] != 13 { end += 1 }
                    emit(index, end, .comment)
                    index = end
                    return true
                case .blockComment(let spec):
                    guard matches(spec.open, at: index) else { continue }
                    if spec.lineStartOnly, lineHasContent { continue }
                    let end = blockCommentEnd(spec)
                    emit(index, end, .comment)
                    index = end
                    return true
                case .string(let spec):
                    guard matches(spec.open, at: index) else { continue }
                    if spec.isCharacter {
                        guard let end = characterEnd(spec) else { continue }
                        emit(index, end, spec.role)
                        index = end
                        return true
                    }
                    let end = stringEnd(spec, from: index)
                    emit(index, end, profile.stringKeys && spec.role == .string && isFollowedByColon(end) ? .key : spec.role)
                    index = end
                    return true
                }
            }
            return false
        }

        private func blockCommentEnd(_ spec: SourceLanguageProfile.BlockCommentSpec) -> Int {
            var depth = 1
            var position = index + spec.open.count
            while position < units.count {
                if spec.nests, matches(spec.open, at: position) {
                    depth += 1
                    position += spec.open.count
                } else if matches(spec.close, at: position) {
                    depth -= 1
                    position += spec.close.count
                    if depth == 0 { return position }
                } else {
                    position += 1
                }
            }
            return units.count
        }

        /// The end of a string that opens at `start`. Single-line strings stop before a line break that
        /// is not escaped; multi-line strings run to their closer or the end of the text.
        private func stringEnd(_ spec: SourceLanguageProfile.StringSpec, from start: Int) -> Int {
            var position = start + spec.open.count
            while position < units.count {
                let unit = units[position]
                if let escape = spec.escape, unit == escape {
                    position = min(position + 2, units.count)
                    continue
                }
                if matches(spec.close, at: position) {
                    if spec.doubledQuote, spec.close.count == 1, position + 1 < units.count, units[position + 1] == spec.close[0] {
                        position += 2
                        continue
                    }
                    return position + spec.close.count
                }
                if !spec.multiline, unit == 10 || unit == 13 { return position }
                position += 1
            }
            return units.count
        }

        /// `'x'`, `'\n'`, `'\u{1F600}'`: a character literal, or `nil` when the quote is something else.
        private func characterEnd(_ spec: SourceLanguageProfile.StringSpec) -> Int? {
            var position = index + spec.open.count
            guard position < units.count, units[position] != 10, units[position] != 13 else { return nil }
            if let escape = spec.escape, units[position] == escape {
                position += 1
                let limit = min(units.count, position + 12)
                while position < limit, !matches(spec.close, at: position), units[position] != 10 { position += 1 }
            } else {
                // One scalar: a surrogate pair counts as one character.
                position += (0xD800...0xDBFF).contains(units[position]) ? 2 : 1
            }
            return matches(spec.close, at: position) ? position + spec.close.count : nil
        }

        /// Lua `[[ ]]` / `[==[ ]==]`: the end of the long bracket opening at `start`, or `nil` if none opens there.
        private func longBracketEnd(at start: Int) -> Int? {
            guard start < units.count, units[start] == 91 else { return nil }
            var level = 0
            var position = start + 1
            while position < units.count, units[position] == 61 { level += 1; position += 1 }
            guard position < units.count, units[position] == 91 else { return nil }
            position += 1
            while position < units.count {
                if units[position] == 93 {
                    var close = position + 1
                    var count = 0
                    while close < units.count, units[close] == 61, count < level { count += 1; close += 1 }
                    if count == level, close < units.count, units[close] == 93 { return close + 1 }
                }
                position += 1
            }
            return units.count
        }

        /// Rust `r#"..."#` (quote preceded by the prefix) and Swift `#"..."#`: the end of the string whose
        /// hashes start at `hashStart`, or `nil` when no quote follows the hashes. No escapes apply.
        private func hashDelimitedStringEnd(hashStart: Int) -> Int? {
            var position = hashStart
            var hashes = 0
            while position < units.count, units[position] == 35 { hashes += 1; position += 1 }
            guard position < units.count, units[position] == 34 else { return nil }
            position += 1
            while position < units.count {
                if units[position] == 34 {
                    var close = position + 1
                    var count = 0
                    while close < units.count, units[close] == 35, count < hashes { count += 1; close += 1 }
                    if count == hashes { return close }
                }
                position += 1
            }
            return units.count
        }

        // MARK: Directives, attributes, decorators

        private mutating func tryPreprocessor(_ unit: UInt16) -> Bool {
            switch profile.preprocessor {
            case .none:
                return false
            case .hashAtLineStart, .backtickAtLineStart:
                let marker: UInt16 = profile.preprocessor == .hashAtLineStart ? 35 : 96
                guard unit == marker, !lineHasContent else { return false }
                var position = index + 1
                while position < units.count, units[position] == 32 || units[position] == 9 { position += 1 }
                guard position < units.count, isIdentifierStart(units[position]) else { return false }
                while position < units.count, isIdentifierPart(units[position]) { position += 1 }
                emit(index, position, .keyword)
                index = position
                return true
            case .hashAnywhere:
                guard unit == 35, index + 1 < units.count, isIdentifierStart(units[index + 1]) else { return false }
                var position = index + 1
                while position < units.count, isIdentifierPart(units[position]) { position += 1 }
                emit(index, position, .keyword)
                index = position
                return true
            }
        }

        private mutating func tryRustAttribute() -> Bool {
            var position = index + 1
            if position < units.count, units[position] == 33 { position += 1 }
            guard position < units.count, units[position] == 91 else { return false }
            var depth = 0
            while position < units.count {
                if units[position] == 91 { depth += 1 }
                else if units[position] == 93 { depth -= 1; if depth == 0 { position += 1; break } }
                else if units[position] == 10 && depth <= 0 { break }
                position += 1
            }
            emit(index, position, .tag)
            index = position
            return true
        }

        /// `@name` and Prisma's `@@name`.
        private func isDecoratorStart(_ unit: UInt16) -> Bool {
            guard profile.decorators, unit == 64, index + 1 < units.count else { return false }
            if isIdentifierStart(units[index + 1]) { return true }
            return units[index + 1] == 64 && index + 2 < units.count && isIdentifierStart(units[index + 2])
        }

        private mutating func scanDecorator() {
            let start = index
            while index < units.count, units[index] == 64 { index += 1 }
            while index < units.count, isIdentifierPart(units[index]) || (units[index] == 46 && index + 1 < units.count && isIdentifierStart(units[index + 1])) {
                index += 1
            }
            emit(start, index, .tag)
        }

        // MARK: Numbers

        private func startsNumber(_ unit: UInt16) -> Bool {
            if Self.isDigit(unit) { return true }
            if unit == 46, profile.allowsLeadingDotNumbers, index + 1 < units.count, Self.isDigit(units[index + 1]) {
                return index == 0 || !isIdentifierPart(units[index - 1])
            }
            if unit == 36, profile.dollarHexNumbers, index + 1 < units.count, Self.isHexDigit(units[index + 1]) { return true }
            if unit == 39, profile.basedNumbers, index + 1 < units.count, Self.isBaseLetter(units[index + 1]) { return true }
            return false
        }

        private func numberEnd(from start: Int) -> Int {
            var position = start
            let count = units.count
            if units[position] == 36 {
                position += 1
                while position < count, Self.isHexDigit(units[position]) || units[position] == 95 { position += 1 }
                return position
            }
            if units[position] == 39 { return basedLiteralEnd(from: position) }
            if units[position] == 46 { position += 1 }
            else if units[position] == 48, position + 1 < count {
                let next = units[position + 1] | 0x20
                if next == 120 { // 0x
                    position += 2
                    while position < count, Self.isHexDigit(units[position]) || (units[position] == 95 && profile.allowsUnderscoreInNumbers) { position += 1 }
                    return suffixEnd(position)
                }
                if next == 98 || next == 111 { // 0b, 0o
                    position += 2
                    while position < count, Self.isDigit(units[position]) || (units[position] == 95 && profile.allowsUnderscoreInNumbers) { position += 1 }
                    return suffixEnd(position)
                }
            }
            while position < count, Self.isDigit(units[position]) || (units[position] == 95 && profile.allowsUnderscoreInNumbers) { position += 1 }
            if profile.basedNumbers, position < count, units[position] == 39, position + 1 < count, Self.isBaseLetter(units[position + 1]) {
                return basedLiteralEnd(from: position)
            }
            // A fraction needs a digit after the dot, so `1..5`, `5.times` and `1.` stay integers.
            if position + 1 < count, units[position] == 46, Self.isDigit(units[position + 1]) {
                position += 1
                while position < count, Self.isDigit(units[position]) || (units[position] == 95 && profile.allowsUnderscoreInNumbers) { position += 1 }
            }
            if position < count, units[position] | 0x20 == 101 {
                var exponent = position + 1
                if exponent < count, units[exponent] == 43 || units[exponent] == 45 { exponent += 1 }
                if exponent < count, Self.isDigit(units[exponent]) {
                    while exponent < count, Self.isDigit(units[exponent]) || units[exponent] == 95 { exponent += 1 }
                    position = exponent
                }
            }
            return suffixEnd(position)
        }

        /// Type and unit suffixes such as `u32`, `f`, `L`, `n`, `px`.
        private func suffixEnd(_ start: Int) -> Int {
            var position = start
            while position < units.count, isIdentifierPart(units[position]), units[position] < 0x80 { position += 1 }
            return position
        }

        /// Verilog `4'b1010`, `8'hFF`, `'b0`: digits already consumed; `'` is at `start`.
        private func basedLiteralEnd(from start: Int) -> Int {
            var position = start + 1
            if position < units.count, units[position] | 0x20 == 115 { position += 1 } // signed
            if position < units.count, Self.isBaseLetter(units[position]) { position += 1 }
            while position < units.count, Self.isHexDigit(units[position]) || units[position] == 95 || units[position] | 0x20 == 120
                    || units[position] | 0x20 == 122 || units[position] == 63 { position += 1 }
            return position
        }

        // MARK: Identifiers

        private mutating func scanIdentifier() {
            let start = index
            index += 1
            while index < units.count, isIdentifierPart(units[index]) { index += 1 }
            let length = index - start
            // A short prefix directly before a quote starts a string: `r"..."`, `b'...'`, `f"..."`.
            if index < units.count, length <= 3, let end = prefixedStringEnd(wordStart: start) {
                emit(start, end, .string)
                index = end
                return
            }
            guard length <= 32 else { return }
            if let role = keyRole(after: start) {
                emit(start, index, role)
                return
            }
            let word = String(decoding: units[start..<index], as: UTF16.self)
            let key = profile.caseInsensitive ? word.lowercased() : word
            if profile.literals.contains(key) { emit(start, index, .literal) }
            else if profile.types.contains(key) { emit(start, index, .type) }
            else if profile.keywords.contains(key) { emit(start, index, .keyword) }
            else if profile.capitalizedTypes, Self.looksLikeTypeName(units[start..<index]) { emit(start, index, .type) }
        }

        private func prefixedStringEnd(wordStart: Int) -> Int? {
            guard index < units.count, profile.hashDelimitedStrings || !profile.stringPrefixes.isEmpty else { return nil }
            let next = units[index]
            guard next == 34 || next == 39 || next == 35 || next == 96 else { return nil }
            let word = String(decoding: units[wordStart..<index], as: UTF16.self)
            if profile.hashDelimitedStrings, word == "r" || word == "br", next == 35 || next == 34,
               let end = hashDelimitedStringEnd(hashStart: index) {
                return end
            }
            guard !profile.stringPrefixes.isEmpty, profile.stringPrefixes.contains(word.lowercased()),
                  let candidates = profile.starters[next] else { return nil }
            for candidate in candidates {
                if case .string(let spec) = candidate, !spec.isCharacter, matches(spec.open, at: index) {
                    return stringEnd(spec, from: index)
                }
            }
            return nil
        }

        /// A key when the profile colors `name=`, `name =` or `name: ` identifiers.
        private func keyRole(after start: Int) -> PreviewSyntaxRole? {
            guard profile.keyStyle != .none else { return nil }
            var position = index
            switch profile.keyStyle {
            case .none:
                return nil
            case .immediateEquals:
                guard isAtWordStart(start), position < units.count, units[position] == 61,
                      !(position + 1 < units.count && units[position + 1] == 61) else { return nil }
            case .spacedEquals:
                while position < units.count, units[position] == 32 || units[position] == 9 { position += 1 }
                // `:=`, `?=`, `+=` and `!=` assign in Make and Just files.
                if position + 1 < units.count, [58, 63, 43].contains(units[position]), units[position + 1] == 61 { position += 1 }
                guard position < units.count, units[position] == 61,
                      !(position + 1 < units.count && (units[position + 1] == 61 || units[position + 1] == 62)) else { return nil }
            case .anyColon:
                while position < units.count, units[position] == 32 || units[position] == 9 { position += 1 }
                guard position < units.count, units[position] == 58 else { return nil }
            case .declarationColon:
                while position < units.count, units[position] == 32 || units[position] == 9 { position += 1 }
                guard position < units.count, units[position] == 58,
                      position + 1 >= units.count || units[position + 1] == 32 || units[position + 1] == 10 || units[position + 1] == 13
                        || units[position + 1] == 9 else { return nil }
            }
            return .key
        }

        // MARK: Character classes and helpers

        private func isIdentifierStart(_ unit: UInt16) -> Bool {
            (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 || unit >= 0x80
                || (unit == 36 && profile.identifierExtras.contains(36))
        }

        private func isIdentifierPart(_ unit: UInt16) -> Bool {
            isIdentifierStart(unit) || Self.isDigit(unit) || profile.identifierExtras.contains(unit)
        }

        private func isAtWordStart(_ position: Int) -> Bool {
            guard position > 0 else { return true }
            let previous = units[position - 1]
            return previous == 32 || previous == 9 || previous == 10 || previous == 13
                || previous == 59 || previous == 124 || previous == 38 || previous == 40 || previous == 41
        }

        private func startsComment(at position: Int) -> Bool {
            guard let candidates = profile.starters[units[position]] else { return false }
            return candidates.contains { candidate in
                switch candidate {
                case .lineComment(let spec): matches(spec.marker, at: position)
                case .blockComment(let spec): matches(spec.open, at: position)
                case .string: false
                }
            }
        }

        private func isFollowedByColon(_ position: Int) -> Bool {
            var next = position
            while next < units.count, units[next] == 32 || units[next] == 9 { next += 1 }
            return next < units.count && units[next] == 58
        }

        private func unitAt(_ position: Int) -> UInt16? { position < units.count ? units[position] : nil }

        private func matches(_ pattern: [UInt16], at position: Int) -> Bool {
            guard position + pattern.count <= units.count else { return false }
            for offset in 0..<pattern.count where units[position + offset] != pattern[offset] { return false }
            return true
        }

        static func isDigit(_ unit: UInt16) -> Bool { (48...57).contains(unit) }
        static func isHexDigit(_ unit: UInt16) -> Bool {
            (48...57).contains(unit) || (65...70).contains(unit) || (97...102).contains(unit)
        }
        static func isBaseLetter(_ unit: UInt16) -> Bool {
            switch unit | 0x20 { case 98, 100, 104, 111: true; default: false }
        }
        static func isSymbol(_ unit: UInt16) -> Bool {
            [33, 35, 36, 37, 38, 42, 43, 46, 47, 60, 61, 62, 63, 64, 92, 94, 124, 126, 58].contains(unit)
        }

        /// `Widget`, `HTTPClient` and `URLSession` are types; `A`, `MAX` and `value` are not.
        static func looksLikeTypeName(_ word: ArraySlice<UInt16>) -> Bool {
            guard let first = word.first, (65...90).contains(first), word.count >= 2 else { return false }
            return word.contains { (97...122).contains($0) }
        }

        // MARK: Markup

        mutating func runMarkup() {
            let template = profile.markup == .template
            while index < units.count, !isFull {
                let unit = units[index]
                if template, unit == 123 || unit == 60, let end = templateDelimiterEnd() { emitTemplate(end); continue }
                if unit == 60, matches(Array("<!--".utf16), at: index) {
                    let end = find(Array("-->".utf16), from: index + 4).map { $0 + 3 } ?? units.count
                    emit(index, end, .comment)
                    index = end
                    continue
                }
                if unit == 60, index + 1 < units.count,
                   isMarkupNameStart(units[index + 1]) || units[index + 1] == 47 || units[index + 1] == 33 || units[index + 1] == 63 {
                    scanTag(template: template)
                    continue
                }
                index += 1
            }
        }

        private mutating func scanTag(template: Bool) {
            let start = index
            index += 1
            if index < units.count, units[index] == 47 || units[index] == 33 || units[index] == 63 { index += 1 }
            while index < units.count, isMarkupNameChar(units[index]) { index += 1 }
            emit(start, index, .tag)
            while index < units.count, !isFull {
                let unit = units[index]
                if unit == 62 { emit(index, index + 1, .tag); index += 1; return }
                if unit == 47, index + 1 < units.count, units[index + 1] == 62 { emit(index, index + 2, .tag); index += 2; return }
                if unit == 34 || unit == 39 {
                    let end = find([unit], from: index + 1).map { $0 + 1 } ?? units.count
                    emit(index, end, .string)
                    index = end
                    continue
                }
                if template, unit == 123 || unit == 60, let end = templateDelimiterEnd() { emitTemplate(end); continue }
                if unit == 60 { return } // A new tag begins: the previous one was never closed.
                if isMarkupNameStart(unit) || unit == 64 || unit == 58 || unit == 35 {
                    let attribute = index
                    index += 1
                    while index < units.count, isMarkupNameChar(units[index]) || units[index] == 64 { index += 1 }
                    emit(attribute, index, .key)
                    continue
                }
                index += 1
            }
        }

        /// The end of a `{{ }}`, `{% %}`, `{# #}` or `<% %>` delimiter pair opening at `index`.
        private func templateDelimiterEnd() -> Int? {
            guard index + 1 < units.count else { return nil }
            let pair: (UInt16, UInt16)
            switch (units[index], units[index + 1]) {
            case (123, 123): pair = (125, 125)
            case (123, 37): pair = (37, 125)
            case (123, 35): pair = (35, 125)
            case (60, 37): pair = (37, 62)
            default: return nil
            }
            var position = index + 2
            while position + 1 < units.count {
                if units[position] == pair.0, units[position + 1] == pair.1 { return position + 2 }
                position += 1
            }
            return units.count
        }

        private mutating func emitTemplate(_ end: Int) {
            let isComment = units[index + 1] == 35
            emit(index, end, isComment ? .comment : .keyword)
            index = end
        }

        private func find(_ pattern: [UInt16], from start: Int) -> Int? {
            var position = start
            while position + pattern.count <= units.count {
                if matches(pattern, at: position) { return position }
                position += 1
            }
            return nil
        }

        private func isMarkupNameStart(_ unit: UInt16) -> Bool { (65...90).contains(unit) || (97...122).contains(unit) || unit == 95 }
        private func isMarkupNameChar(_ unit: UInt16) -> Bool {
            isMarkupNameStart(unit) || Self.isDigit(unit) || unit == 45 || unit == 58 || unit == 46
        }
    }
}
