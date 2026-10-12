import Foundation

/// Character references for tolerant markup. Only numeric references, the five predefined XML
/// entities and a fixed table of common HTML names are decoded. A DTD or an unknown name is never
/// consulted, so a document cannot declare an entity, expand text exponentially or reach a file.
enum HTMLEntities {
    /// Longest reference body considered, excluding `&` and `;`. Longer runs stay literal text.
    static let maximumReferenceLength = 10

    /// Decodes references in `bytes` (valid UTF-8). Unrecognized references are kept verbatim.
    static func decode(_ bytes: ArraySlice<UInt8>) -> String {
        guard bytes.contains(ampersand) else { return String(decoding: bytes, as: UTF8.self) }
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            guard byte == ampersand else { output.append(byte); index += 1; continue }
            if let (scalar, next) = reference(in: bytes, at: index) {
                output.append(contentsOf: Array(String(Character(scalar)).utf8))
                index = next
            } else {
                output.append(byte)
                index += 1
            }
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static let ampersand: UInt8 = 38
    private static let semicolon: UInt8 = 59

    private static func reference(in bytes: ArraySlice<UInt8>, at start: Int) -> (Unicode.Scalar, Int)? {
        let limit = min(bytes.endIndex, start + maximumReferenceLength + 2)
        var end = start + 1
        while end < limit, bytes[end] != semicolon { end += 1 }
        guard end < limit, bytes[end] == semicolon, end > start + 1 else { return nil }
        let body = bytes[(start + 1)..<end]
        if body.first == 35 {
            // Numeric: decimal `&#65;` or hexadecimal `&#x41;`.
            let isHex = body.count > 1 && (body[body.startIndex + 1] == 120 || body[body.startIndex + 1] == 88)
            let digits = body.dropFirst(isHex ? 2 : 1)
            guard !digits.isEmpty, let value = UInt32(String(decoding: digits, as: UTF8.self), radix: isHex ? 16 : 10),
                  let scalar = Unicode.Scalar(value) else { return nil }
            return (scalar, end + 1)
        }
        guard let scalar = named[String(decoding: body, as: UTF8.self)] else { return nil }
        return (scalar, end + 1)
    }

    /// Latin-1 supplement names in code point order from U+00A0.
    private static let latin1 = ("nbsp iexcl cent pound curren yen brvbar sect uml copy ordf laquo not shy reg macr deg plusmn "
        + "sup2 sup3 acute micro para middot cedil sup1 ordm raquo frac14 frac12 frac34 iquest Agrave Aacute Acirc Atilde "
        + "Auml Aring AElig Ccedil Egrave Eacute Ecirc Euml Igrave Iacute Icirc Iuml ETH Ntilde Ograve Oacute Ocirc Otilde "
        + "Ouml times Oslash Ugrave Uacute Ucirc Uuml Yacute THORN szlig agrave aacute acirc atilde auml aring aelig "
        + "ccedil egrave eacute ecirc euml igrave iacute icirc iuml eth ntilde ograve oacute ocirc otilde ouml divide "
        + "oslash ugrave uacute ucirc uuml yacute thorn yuml").split(separator: " ")

    private static let named: [String: Unicode.Scalar] = {
        var table: [String: Unicode.Scalar] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        for (offset, name) in latin1.enumerated() {
            if let scalar = Unicode.Scalar(0xA0 + UInt32(offset)) { table[String(name)] = scalar }
        }
        let others: [(String, UInt32)] = [
            ("OElig", 0x152), ("oelig", 0x153), ("Scaron", 0x160), ("scaron", 0x161), ("Yuml", 0x178), ("fnof", 0x192),
            ("circ", 0x2C6), ("tilde", 0x2DC), ("ensp", 0x2002), ("emsp", 0x2003), ("thinsp", 0x2009), ("zwnj", 0x200C),
            ("zwj", 0x200D), ("lrm", 0x200E), ("rlm", 0x200F), ("ndash", 0x2013), ("mdash", 0x2014), ("lsquo", 0x2018),
            ("rsquo", 0x2019), ("sbquo", 0x201A), ("ldquo", 0x201C), ("rdquo", 0x201D), ("bdquo", 0x201E),
            ("dagger", 0x2020), ("Dagger", 0x2021), ("bull", 0x2022), ("hellip", 0x2026), ("permil", 0x2030),
            ("prime", 0x2032), ("Prime", 0x2033), ("lsaquo", 0x2039), ("rsaquo", 0x203A), ("oline", 0x203E),
            ("frasl", 0x2044), ("euro", 0x20AC), ("trade", 0x2122), ("larr", 0x2190), ("uarr", 0x2191),
            ("rarr", 0x2192), ("darr", 0x2193), ("harr", 0x2194), ("forall", 0x2200), ("part", 0x2202),
            ("exist", 0x2203), ("empty", 0x2205), ("nabla", 0x2207), ("isin", 0x2208), ("minus", 0x2212),
            ("lowast", 0x2217), ("radic", 0x221A), ("infin", 0x221E), ("asymp", 0x2248), ("ne", 0x2260),
            ("equiv", 0x2261), ("le", 0x2264), ("ge", 0x2265), ("sub", 0x2282), ("sup", 0x2283), ("sdot", 0x22C5),
            ("loz", 0x25CA), ("spades", 0x2660), ("clubs", 0x2663), ("hearts", 0x2665), ("diams", 0x2666),
            ("Alpha", 0x391), ("Beta", 0x392), ("Gamma", 0x393), ("Delta", 0x394), ("Omega", 0x3A9),
            ("alpha", 0x3B1), ("beta", 0x3B2), ("gamma", 0x3B3), ("delta", 0x3B4), ("epsilon", 0x3B5),
            ("lambda", 0x3BB), ("mu", 0x3BC), ("pi", 0x3C0), ("sigma", 0x3C3), ("omega", 0x3C9)
        ]
        for (name, value) in others { if let scalar = Unicode.Scalar(value) { table[name] = scalar } }
        return table
    }()
}
