import Foundation

/// A bounded Unicode approximation of common TeX math.
///
/// This is not typesetting. It maps Greek letters, operators, relations, arrows, simple
/// accents and `^`/`_` scripts that have Unicode forms, writes `\frac{a}{b}` as `a⁄b` and
/// `\sqrt{x}` as `√x`, and leaves everything it does not know as visible source (`\name`).
/// Input is bounded, nesting is bounded and every step consumes input, so cost is linear.
enum MarkupMath {
    /// Longer spans are shown as written, unconverted.
    static let maximumSourceCharacters = 4_096
    static let maximumNesting = 24

    /// Approximates `tex`. `multiline` turns `\\` into line breaks, as in `align` and `gather`.
    static func approximate(_ tex: String, multiline: Bool = false) -> String {
        guard tex.count <= maximumSourceCharacters else { return tex }
        var converter = Converter(characters: Array(tex), multiline: multiline)
        let result = converter.sequence(stopAtBrace: false)
        return collapse(result)
    }

    /// Collapses runs of spaces left by dropped commands, trims the ends of every line and removes the
    /// space before a closing mark or comma and after an opening parenthesis.
    private static func collapse(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character == " " { pendingSpace = true; continue }
            if character == "\n" { pendingSpace = false; result.append(character); continue }
            if pendingSpace, let last = result.last, last != "\n", last != "(", ![",", ";", ")"].contains(character) { result.append(" ") }
            pendingSpace = false
            result.append(character)
        }
        return result
    }

    // MARK: Tables

    private static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ϵ", "varepsilon": "ε", "zeta": "ζ",
        "eta": "η", "theta": "θ", "vartheta": "ϑ", "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν",
        "xi": "ξ", "omicron": "ο", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ", "sigma": "σ",
        "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "ϕ", "varphi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ", "Pi": "Π", "Sigma": "Σ",
        "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "⋅", "ast": "∗", "star": "⋆", "circ": "∘",
        "bullet": "∙", "oplus": "⊕", "ominus": "⊖", "otimes": "⊗", "odot": "⊙", "cup": "∪", "cap": "∩",
        "setminus": "∖", "wedge": "∧", "land": "∧", "vee": "∨", "lor": "∨", "neg": "¬", "lnot": "¬",
        "sum": "∑", "prod": "∏", "coprod": "∐", "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮",
        "partial": "∂", "nabla": "∇", "infty": "∞", "emptyset": "∅", "varnothing": "∅", "forall": "∀",
        "exists": "∃", "nexists": "∄", "angle": "∠", "perp": "⊥", "parallel": "∥", "mid": "∣", "prime": "′",
        "hbar": "ℏ", "ell": "ℓ", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ", "wp": "℘", "degree": "°",
        "top": "⊤", "bot": "⊥", "therefore": "∴", "because": "∵", "square": "□", "triangle": "△",
        // Relations
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥", "ne": "≠", "neq": "≠", "approx": "≈", "sim": "∼",
        "simeq": "≃", "cong": "≅", "equiv": "≡", "propto": "∝", "ll": "≪", "gg": "≫", "in": "∈", "notin": "∉",
        "ni": "∋", "subset": "⊂", "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "nsubseteq": "⊈",
        "prec": "≺", "succ": "≻", "doteq": "≐",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "gets": "←", "leftrightarrow": "↔", "uparrow": "↑",
        "downarrow": "↓", "Rightarrow": "⇒", "Leftarrow": "⇐", "Leftrightarrow": "⇔", "iff": "⟺",
        "implies": "⟹", "impliedby": "⟸", "mapsto": "↦", "longrightarrow": "⟶", "longleftarrow": "⟵",
        "hookrightarrow": "↪", "rightharpoonup": "⇀",
        // Dots, delimiters
        "ldots": "…", "dots": "…", "cdots": "⋯", "vdots": "⋮", "ddots": "⋱", "langle": "⟨", "rangle": "⟩",
        "lceil": "⌈", "rceil": "⌉", "lfloor": "⌊", "rfloor": "⌋", "lbrace": "{", "rbrace": "}", "vert": "|",
        "Vert": "‖", "backslash": "\\", "colon": ":",
        // Spacing
        "quad": "\u{2003}", "qquad": "\u{2003}\u{2003}", ",": "\u{2009}", ":": "\u{2005}", ";": "\u{2004}",
        " ": " ", "!": "", "|": "‖", "{": "{", "}": "}", "%": "%", "$": "$", "#": "#", "&": "&", "_": "_"
    ]

    /// Symbols TeX sets with space on both sides: relations, arrows and binary operators.
    private static let spaced: Set<String> = [
        "le", "leq", "ge", "geq", "ne", "neq", "approx", "sim", "simeq", "cong", "equiv", "propto", "ll", "gg",
        "in", "notin", "ni", "subset", "supset", "subseteq", "supseteq", "nsubseteq", "prec", "succ", "doteq",
        "to", "rightarrow", "leftarrow", "gets", "leftrightarrow", "Rightarrow", "Leftarrow", "Leftrightarrow",
        "iff", "implies", "impliedby", "mapsto", "longrightarrow", "longleftarrow", "hookrightarrow",
        "rightharpoonup", "pm", "mp", "times", "div", "cdot", "ast", "star", "circ", "bullet", "oplus", "ominus",
        "otimes", "odot", "cup", "cap", "setminus", "wedge", "land", "vee", "lor", "perp", "parallel", "mid"
    ]

    /// Commands that only affect layout; they and their delimiters' sizing disappear.
    private static let ignored: Set<String> = [
        "left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr", "Bigl", "Bigr", "displaystyle",
        "textstyle", "scriptstyle", "limits", "nolimits", "nonumber", "notag", "hfill", "relax", "middle"
    ]

    /// Operators written upright: the command is replaced by its name.
    private static let functionNames: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc", "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth",
        "log", "ln", "lg", "exp", "lim", "limsup", "liminf", "max", "min", "sup", "inf", "det", "dim", "ker",
        "deg", "gcd", "arg", "Pr", "hom", "mod", "bmod", "var", "cov"
    ]

    /// Commands whose single argument is shown as is: font changes and boxes.
    private static let transparent: Set<String> = [
        "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathnormal", "mathcal", "mathscr", "mathfrak",
        "boldsymbol", "bm", "textrm", "textit", "textbf", "textsf", "texttt", "emph", "mbox", "hbox",
        "operatorname", "mathop", "mathrel", "mathbin", "mathord", "displaylines", "boxed", "cancel",
        "phantom", "vphantom", "hphantom", "mathstrut", "pmb"
    ]

    /// Commands whose single argument is raw text, not math.
    private static let rawArgument: Set<String> = ["text", "textnormal", "intertext", "mbox", "hbox", "operatorname", "mathrm"]

    private static let combining: [String: Character] = [
        "hat": "\u{0302}", "widehat": "\u{0302}", "check": "\u{030C}", "tilde": "\u{0303}", "widetilde": "\u{0303}",
        "acute": "\u{0301}", "grave": "\u{0300}", "dot": "\u{0307}", "ddot": "\u{0308}", "breve": "\u{0306}",
        "bar": "\u{0304}", "vec": "\u{20D7}", "overline": "\u{0305}", "underline": "\u{0332}"
    ]

    private static let doubleStruck: [Character: String] = [
        "C": "ℂ", "H": "ℍ", "N": "ℕ", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "Z": "ℤ"
    ]

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
        "+": "⁺", "-": "⁻", "−": "⁻", "=": "⁼", "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ", "h": "ʰ", "i": "ⁱ", "j": "ʲ",
        "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ", "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ",
        "v": "ᵛ", "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ",
        "A": "ᴬ", "B": "ᴮ", "D": "ᴰ", "E": "ᴱ", "G": "ᴳ", "H": "ᴴ", "I": "ᴵ", "J": "ᴶ", "K": "ᴷ", "L": "ᴸ",
        "M": "ᴹ", "N": "ᴺ", "O": "ᴼ", "P": "ᴾ", "R": "ᴿ", "T": "ᵀ", "U": "ᵁ", "V": "ⱽ", "W": "ᵂ",
        "β": "ᵝ", "γ": "ᵞ", "δ": "ᵟ", "φ": "ᵠ", "χ": "ᵡ", "′": "′", "∗": "*"
    ]

    private static let subscripts: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
        "+": "₊", "-": "₋", "−": "₋", "=": "₌", "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ", "m": "ₘ", "n": "ₙ", "o": "ₒ",
        "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ", "u": "ᵤ", "v": "ᵥ", "x": "ₓ",
        "β": "ᵦ", "γ": "ᵧ", "ρ": "ᵨ", "φ": "ᵩ", "χ": "ᵪ"
    ]

    private static func script(_ text: String, table: [Character: Character]) -> String? {
        var result = ""
        for character in text {
            guard let mapped = table[character] else { return nil }
            result.append(mapped)
        }
        return result.isEmpty ? nil : result
    }

    // MARK: Conversion

    private struct Converter {
        let characters: [Character]
        let multiline: Bool
        var index = 0
        var depth = 0
        /// Innermost matrix-like environment, which changes what `&` and `\\` mean.
        var environments: [String] = []

        init(characters: [Character], multiline: Bool) {
            self.characters = characters
            self.multiline = multiline
        }

        private var isAtEnd: Bool { index >= characters.count }

        mutating func sequence(stopAtBrace: Bool) -> String {
            var output = ""
            while !isAtEnd {
                let character = characters[index]
                if character == "}" {
                    if stopAtBrace { return output }
                    index += 1
                    output.append("}")
                    continue
                }
                output += item()
            }
            return output
        }

        /// One syntactic item followed by any scripts attached to it.
        private mutating func item() -> String {
            let character = characters[index]
            var base: String
            switch character {
            case "\\": base = command()
            case "{": base = group()
            case "^", "_":
                // A script with no base: attach to nothing and show it as written.
                base = ""
            case "&":
                index += 1
                let inMatrix = environments.last.map { MarkupMath.matrixEnvironments.contains($0) } == true
                base = inMatrix ? "," + (isAtEnd || characters[index] == " " ? "" : " ") : " "
            case "~": index += 1; base = " "
            case "'": index += 1; base = "′"
            case "-": index += 1; base = "−"
            case "%":
                while !isAtEnd, characters[index] != "\n" { index += 1 }
                base = ""
            case " ", "\t", "\n", "\r":
                index += 1
                base = " "
                while !isAtEnd, characters[index] == " " || characters[index] == "\t" || characters[index] == "\n" || characters[index] == "\r" { index += 1 }
            default: index += 1; base = String(character)
            }
            // Scripts follow their base: x^2_i, e^{i\pi}.
            while !isAtEnd, characters[index] == "^" || characters[index] == "_" {
                let isSuperscript = characters[index] == "^"
                index += 1
                let argument = atom()
                let mapped = MarkupMath.script(argument, table: isSuperscript ? MarkupMath.superscripts : MarkupMath.subscripts)
                if let mapped { base += mapped }
                else { base += (isSuperscript ? "^" : "_") + wrapped(argument) }
            }
            return base
        }

        /// Wraps multi-character arguments so a fallback script stays readable.
        private func wrapped(_ text: String) -> String { text.count > 1 ? "(" + text + ")" : text }

        private mutating func group() -> String {
            guard depth < MarkupMath.maximumNesting else { index += 1; return "{" }
            index += 1
            depth += 1
            let inner = sequence(stopAtBrace: true)
            depth -= 1
            if !isAtEnd, characters[index] == "}" { index += 1 }
            return inner
        }

        private mutating func skipSpaces() {
            while !isAtEnd, characters[index] == " " || characters[index] == "\t" || characters[index] == "\n" || characters[index] == "\r" { index += 1 }
        }

        /// A braced group, a command or one character: the unit `^`, `_` and `\frac` operate on.
        private mutating func atom() -> String {
            skipSpaces()
            guard !isAtEnd else { return "" }
            switch characters[index] {
            case "{": return group()
            case "\\": return command()
            case "}": return ""
            default:
                let character = characters[index]
                index += 1
                switch character {
                case "-": return "−"
                case "'": return "′"
                default: return String(character)
                }
            }
        }

        /// The raw text of a braced group (balanced), or one character.
        private mutating func rawGroup() -> String {
            skipSpaces()
            guard !isAtEnd else { return "" }
            guard characters[index] == "{" else {
                let character = characters[index]
                index += 1
                return String(character)
            }
            index += 1
            var nesting = 1
            var raw = ""
            while !isAtEnd {
                let character = characters[index]
                index += 1
                if character == "{" { nesting += 1 }
                else if character == "}" { nesting -= 1; if nesting == 0 { break } }
                raw.append(character)
            }
            return raw
        }

        private mutating func command() -> String {
            index += 1   // the backslash
            guard !isAtEnd else { return "\\" }
            var name = ""
            if characters[index].isASCII, characters[index].isLetter {
                while !isAtEnd, characters[index].isASCII, characters[index].isLetter { name.append(characters[index]); index += 1 }
            } else {
                name = String(characters[index])
                index += 1
            }
            if name == "\\" {
                if let environment = environments.last, MarkupMath.matrixEnvironments.contains(environment) {
                    return ";" + (isAtEnd || characters[index] == " " ? "" : " ")
                }
                return multiline ? "\n" : " "
            }
            if name == "begin" || name == "end" { return environment(isBegin: name == "begin") }
            if let symbol = MarkupMath.symbols[name] {
                // Relations, arrows and binary operators get the space TeX would typeset around them.
                if name == "quad" || name == "qquad" { skipSpaces() }
                return MarkupMath.spaced.contains(name) ? " " + symbol + " " : symbol
            }
            if MarkupMath.ignored.contains(name) {
                if name == "left" || name == "right" || name == "middle" || name.hasPrefix("big") || name.hasPrefix("Big"),
                   !isAtEnd, characters[index] == "." { index += 1 }
                return ""
            }
            if MarkupMath.functionNames.contains(name) { return name }
            switch name {
            case "frac", "dfrac", "tfrac", "cfrac":
                let numerator = atom()
                let denominator = atom()
                return wrapped(numerator) + "⁄" + wrapped(denominator)
            case "binom", "dbinom", "tbinom":
                let top = atom()
                let bottom = atom()
                return "C(" + top + ", " + bottom + ")"
            case "sqrt":
                var root: String?
                skipSpaces()
                if !isAtEnd, characters[index] == "[" {
                    index += 1
                    var raw = ""
                    while !isAtEnd, characters[index] != "]" { raw.append(characters[index]); index += 1 }
                    if !isAtEnd { index += 1 }
                    root = raw
                }
                let radicand = atom()
                let sign: String
                switch root {
                case nil, "2": sign = "√"
                case "3": sign = "∛"
                case "4": sign = "∜"
                case let value?: sign = (MarkupMath.script(value, table: MarkupMath.superscripts) ?? "") + "√"
                }
                return sign + wrapped(radicand)
            case "mathbb":
                let content = rawGroup()
                return content.count == 1 ? (MarkupMath.doubleStruck[content.first!] ?? content) : content
            case "label", "tag", "ref", "eqref", "nonumber_":
                _ = rawGroup()
                return ""
            case "color", "textcolor":
                _ = rawGroup()
                return name == "textcolor" ? atom() : ""
            case "substack", "underset", "overset", "stackrel":
                let first = atom()
                if name == "substack" { return first }
                let second = atom()
                return name == "underset" ? second + "_" + wrapped(first) : second + "^" + wrapped(first)
            default: break
            }
            if let mark = MarkupMath.combining[name] {
                let content = atom()
                return accent(content, mark: mark, name: name)
            }
            if MarkupMath.rawArgument.contains(name) { return rawGroup() }
            if MarkupMath.transparent.contains(name) { return atom() }
            // Unknown command: keep it visible, with its immediate braced arguments.
            var literal = "\\" + name
            while !isAtEnd, characters[index] == "{" { literal += "{" + group() + "}" }
            return literal
        }

        private func accent(_ content: String, mark: Character, name: String) -> String {
            let graphemes = Array(content)
            if graphemes.count == 1 { return content + String(mark) }
            if name == "overline" || name == "underline" || name == "widehat" || name == "widetilde" {
                return graphemes.map { String($0) + String(mark) }.joined()
            }
            return name + "(" + content + ")"
        }

        private mutating func environment(isBegin: Bool) -> String {
            let name = rawGroup()
            if isBegin {
                if environments.count < MarkupMath.maximumNesting { environments.append(name) }
                if name.hasPrefix("cases") || name.hasPrefix("dcases") { return "{ " }
                switch name {
                case "pmatrix": return "("
                case "bmatrix": return "["
                case "Bmatrix": return "{"
                case "vmatrix": return "|"
                case "Vmatrix": return "‖"
                default: return ""
                }
            }
            if let last = environments.last, last == name { environments.removeLast() }
            switch name {
            case "pmatrix": return ")"
            case "bmatrix": return "]"
            case "Bmatrix": return "}"
            case "vmatrix": return "|"
            case "Vmatrix": return "‖"
            default: return ""
            }
        }
    }

    fileprivate static let matrixEnvironments: Set<String> = [
        "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "smallmatrix", "array", "cases"
    ]
}
