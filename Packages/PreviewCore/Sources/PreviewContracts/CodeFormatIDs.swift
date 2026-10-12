import Foundation

/// Stable identifiers of the code, configuration and caption formats. They are persisted in
/// file-type choices, so the raw values never change with the display name or this file's layout.
public extension FormatID {
    /// INI-family configuration: `.ini`, `.cfg`, `.conf`, `.properties`, `.xcconfig` and well-known dotfiles.
    static let iniConfiguration = FormatID(rawValue: "config.ini")
    /// Plain-text logs with timestamps, severities and stack frames.
    static let log = FormatID(rawValue: "text.log")
    /// JSON with comments and trailing commas (JSONC) and the JSON5 superset.
    static let jsonWithComments = FormatID(rawValue: "data.jsonc")
    static let subStationAlpha = FormatID(rawValue: "text.substation-alpha")
    static let timedText = FormatID(rawValue: "text.ttml")
    static let subViewer = FormatID(rawValue: "text.sbv")
    static let lyrics = FormatID(rawValue: "text.lrc")
    static let microDVD = FormatID(rawValue: "text.microdvd")
}

/// Semantic language hints used by `text.source-code`. A language only chooses lexical decoration
/// rules in the renderer; it is never a format identity, a parser selector or a file-type choice.
/// The raw values are stable lowercase identifiers shared by the name detector and the
/// renderer's profile table; `all` lists every identifier either side may produce.
public extension SourceLanguageID {
    // Systems and compiled languages.
    static let c = SourceLanguageID(rawValue: "c")
    static let cpp = SourceLanguageID(rawValue: "cpp")
    static let objectiveC = SourceLanguageID(rawValue: "objective-c")
    static let objectiveCpp = SourceLanguageID(rawValue: "objective-cpp")
    static let csharp = SourceLanguageID(rawValue: "csharp")
    static let fsharp = SourceLanguageID(rawValue: "fsharp")
    static let visualBasic = SourceLanguageID(rawValue: "visual-basic")
    static let java = SourceLanguageID(rawValue: "java")
    static let kotlin = SourceLanguageID(rawValue: "kotlin")
    static let scala = SourceLanguageID(rawValue: "scala")
    static let groovy = SourceLanguageID(rawValue: "groovy")
    static let swift = SourceLanguageID(rawValue: "swift")
    static let go = SourceLanguageID(rawValue: "go")
    static let rust = SourceLanguageID(rawValue: "rust")
    static let zig = SourceLanguageID(rawValue: "zig")
    static let nim = SourceLanguageID(rawValue: "nim")
    static let crystal = SourceLanguageID(rawValue: "crystal")
    static let d = SourceLanguageID(rawValue: "d")
    static let dart = SourceLanguageID(rawValue: "dart")
    static let pascal = SourceLanguageID(rawValue: "pascal")
    static let ada = SourceLanguageID(rawValue: "ada")
    static let fortran = SourceLanguageID(rawValue: "fortran")
    static let assembly = SourceLanguageID(rawValue: "assembly")
    // Scripting languages.
    static let javascript = SourceLanguageID(rawValue: "javascript")
    static let typescript = SourceLanguageID(rawValue: "typescript")
    static let python = SourceLanguageID(rawValue: "python")
    static let ruby = SourceLanguageID(rawValue: "ruby")
    static let php = SourceLanguageID(rawValue: "php")
    static let perl = SourceLanguageID(rawValue: "perl")
    static let lua = SourceLanguageID(rawValue: "lua")
    static let r = SourceLanguageID(rawValue: "r")
    static let julia = SourceLanguageID(rawValue: "julia")
    static let coffeeScript = SourceLanguageID(rawValue: "coffeescript")
    static let awk = SourceLanguageID(rawValue: "awk")
    // Functional languages.
    static let haskell = SourceLanguageID(rawValue: "haskell")
    static let ocaml = SourceLanguageID(rawValue: "ocaml")
    static let elixir = SourceLanguageID(rawValue: "elixir")
    static let erlang = SourceLanguageID(rawValue: "erlang")
    static let elm = SourceLanguageID(rawValue: "elm")
    static let clojure = SourceLanguageID(rawValue: "clojure")
    static let lisp = SourceLanguageID(rawValue: "lisp")
    // Shells and command languages.
    static let shell = SourceLanguageID(rawValue: "shell")
    static let fish = SourceLanguageID(rawValue: "fish")
    static let powerShell = SourceLanguageID(rawValue: "powershell")
    static let batch = SourceLanguageID(rawValue: "batch")
    static let nushell = SourceLanguageID(rawValue: "nushell")
    static let appleScript = SourceLanguageID(rawValue: "applescript")
    // Hardware description and smart contracts.
    static let vhdl = SourceLanguageID(rawValue: "vhdl")
    static let verilog = SourceLanguageID(rawValue: "verilog")
    static let systemVerilog = SourceLanguageID(rawValue: "systemverilog")
    static let solidity = SourceLanguageID(rawValue: "solidity")
    // Queries and interface definitions.
    static let sql = SourceLanguageID(rawValue: "sql")
    static let graphQL = SourceLanguageID(rawValue: "graphql")
    static let protobuf = SourceLanguageID(rawValue: "protobuf")
    static let thrift = SourceLanguageID(rawValue: "thrift")
    static let prisma = SourceLanguageID(rawValue: "prisma")
    // Build, infrastructure and configuration languages.
    static let hcl = SourceLanguageID(rawValue: "hcl")
    static let nix = SourceLanguageID(rawValue: "nix")
    static let starlark = SourceLanguageID(rawValue: "starlark")
    static let cmake = SourceLanguageID(rawValue: "cmake")
    static let meson = SourceLanguageID(rawValue: "meson")
    static let makefile = SourceLanguageID(rawValue: "makefile")
    static let dockerfile = SourceLanguageID(rawValue: "dockerfile")
    static let just = SourceLanguageID(rawValue: "just")
    static let jsonnet = SourceLanguageID(rawValue: "jsonnet")
    static let plantUML = SourceLanguageID(rawValue: "plantuml")
    static let ignoreList = SourceLanguageID(rawValue: "ignore")
    // Web languages and templates.
    static let html = SourceLanguageID(rawValue: "html")
    static let css = SourceLanguageID(rawValue: "css")
    static let scss = SourceLanguageID(rawValue: "scss")
    static let sass = SourceLanguageID(rawValue: "sass")
    static let less = SourceLanguageID(rawValue: "less")
    static let stylus = SourceLanguageID(rawValue: "stylus")
    static let vue = SourceLanguageID(rawValue: "vue")
    static let svelte = SourceLanguageID(rawValue: "svelte")
    static let astro = SourceLanguageID(rawValue: "astro")
    static let template = SourceLanguageID(rawValue: "template")
    static let pug = SourceLanguageID(rawValue: "pug")
    // Shader languages and WebAssembly text.
    static let glsl = SourceLanguageID(rawValue: "glsl")
    static let hlsl = SourceLanguageID(rawValue: "hlsl")
    static let metal = SourceLanguageID(rawValue: "metal")
    static let wgsl = SourceLanguageID(rawValue: "wgsl")
    static let webAssemblyText = SourceLanguageID(rawValue: "wat")

    /// Every language the detector can name and the renderer has a lexical profile for.
    static let all: [SourceLanguageID] = [
        .c, .cpp, .objectiveC, .objectiveCpp, .csharp, .fsharp, .visualBasic, .java, .kotlin, .scala, .groovy,
        .swift, .go, .rust, .zig, .nim, .crystal, .d, .dart, .pascal, .ada, .fortran, .assembly,
        .javascript, .typescript, .python, .ruby, .php, .perl, .lua, .r, .julia, .coffeeScript, .awk,
        .haskell, .ocaml, .elixir, .erlang, .elm, .clojure, .lisp,
        .shell, .fish, .powerShell, .batch, .nushell, .appleScript,
        .vhdl, .verilog, .systemVerilog, .solidity,
        .sql, .graphQL, .protobuf, .thrift, .prisma,
        .hcl, .nix, .starlark, .cmake, .meson, .makefile, .dockerfile, .just, .jsonnet, .plantUML, .ignoreList,
        .html, .css, .scss, .sass, .less, .stylus, .vue, .svelte, .astro, .template, .pug,
        .glsl, .hlsl, .metal, .wgsl, .webAssemblyText
    ]
}
