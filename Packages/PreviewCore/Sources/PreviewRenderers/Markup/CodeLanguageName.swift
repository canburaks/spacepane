import Foundation
import PreviewContracts

/// The name a code language is shown under. Languages are proper names (Swift, C++, PowerShell), written as their
/// communities write them, so a name is never translated: the same text appears in every app language. Only the
/// finite canonical identifiers of `SourceLanguageID.all` have a name; a raw label from a document never reaches the
/// screen (decision 027, Q-73).
enum CodeLanguageName {
    /// The name of a canonical language, or nil for no language or an identifier outside the finite set.
    static func text(for language: SourceLanguageID?) -> String? {
        guard let language, SourceLanguageID.all.contains(language) else { return nil }
        return names[language.rawValue] ?? language.rawValue
    }

    private static let names: [String: String] = [
        "c": "C", "cpp": "C++", "objective-c": "Objective-C", "objective-cpp": "Objective-C++", "csharp": "C#",
        "fsharp": "F#", "visual-basic": "Visual Basic", "java": "Java", "kotlin": "Kotlin", "scala": "Scala",
        "groovy": "Groovy", "swift": "Swift", "go": "Go", "rust": "Rust", "zig": "Zig", "nim": "Nim",
        "crystal": "Crystal", "d": "D", "dart": "Dart", "pascal": "Pascal", "ada": "Ada", "fortran": "Fortran",
        "assembly": "Assembly", "javascript": "JavaScript", "typescript": "TypeScript", "python": "Python",
        "ruby": "Ruby", "php": "PHP", "perl": "Perl", "lua": "Lua", "r": "R", "julia": "Julia",
        "coffeescript": "CoffeeScript", "awk": "AWK", "haskell": "Haskell", "ocaml": "OCaml", "elixir": "Elixir",
        "erlang": "Erlang", "elm": "Elm", "clojure": "Clojure", "lisp": "Lisp", "shell": "Shell", "fish": "fish",
        "powershell": "PowerShell", "batch": "Batch", "nushell": "Nushell", "applescript": "AppleScript",
        "vhdl": "VHDL", "verilog": "Verilog", "systemverilog": "SystemVerilog", "solidity": "Solidity",
        "sql": "SQL", "graphql": "GraphQL", "protobuf": "Protocol Buffers", "thrift": "Thrift", "prisma": "Prisma",
        "hcl": "HCL", "nix": "Nix", "starlark": "Starlark", "cmake": "CMake", "meson": "Meson",
        "makefile": "Makefile", "dockerfile": "Dockerfile", "just": "Just", "jsonnet": "Jsonnet",
        "plantuml": "PlantUML", "ignore": "gitignore", "html": "HTML", "css": "CSS", "scss": "SCSS", "sass": "Sass",
        "less": "Less", "stylus": "Stylus", "vue": "Vue", "svelte": "Svelte", "astro": "Astro",
        "template": "Template", "pug": "Pug", "glsl": "GLSL", "hlsl": "HLSL", "metal": "Metal", "wgsl": "WGSL",
        "wat": "WebAssembly"
    ]
}

/// How the language label sits on a code card. The card keeps a band of this height above its first line for the
/// label, so the label never covers code; both follow the size of the code.
enum CodeLanguageLabelMetrics {
    /// Distance from the card's side edge to the label, in points.
    static let inset: CGFloat = 8
    /// Distance from the card's top edge to the label, inside the card's own top padding.
    static let top: CGFloat = 6

    /// The label's point size: three quarters of the code size, never below 9 or above 14 points.
    static func fontSize(forCodeSize code: CGFloat) -> CGFloat {
        guard code.isFinite, code > 0 else { return 9 }
        return min(max((code * 0.75).rounded(), 9), 14)
    }

    /// The height of the band the card keeps above its first line for the label.
    static func bandHeight(forCodeSize code: CGFloat) -> CGFloat {
        (fontSize(forCodeSize: code) * 1.4).rounded(.up)
    }
}
