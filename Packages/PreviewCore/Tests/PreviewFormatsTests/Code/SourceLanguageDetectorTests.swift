import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Source language detection")
struct SourceLanguageDetectorTests {
    private func language(_ filename: String) -> SourceLanguageID? {
        SourceLanguageDetector.language(for: PreviewNameHint(url: URL(fileURLWithPath: "/tmp/" + filename)))
    }

    @Test(arguments: [
        ("main.swift", SourceLanguageID.swift), ("App.m", .objectiveC), ("App.mm", .objectiveCpp), ("lib.h", .cpp),
        ("util.c", .c), ("Program.cs", .csharp), ("Core.fs", .fsharp), ("Module.vb", .visualBasic), ("Main.java", .java),
        ("Main.kt", .kotlin), ("build.gradle", .groovy), ("Build.sbt", .scala), ("app.dart", .dart), ("init.lua", .lua),
        ("tool.pl", .perl), ("analysis.R", .r), ("model.jl", .julia), ("Main.hs", .haskell), ("main.ml", .ocaml),
        ("server.ex", .elixir), ("server.erl", .erlang), ("core.clj", .clojure), ("main.zig", .zig), ("main.nim", .nim),
        ("main.cr", .crystal), ("main.d", .d), ("solver.f90", .fortran), ("unit.pas", .pascal), ("pkg.adb", .ada),
        ("boot.asm", .assembly), ("alu.vhd", .vhdl), ("alu.sv", .systemVerilog), ("alu.v", .verilog), ("Token.sol", .solidity),
        ("schema.graphql", .graphQL), ("api.proto", .protobuf), ("api.thrift", .thrift), ("main.tf", .hcl),
        ("flake.nix", .nix), ("rules.bzl", .starlark), ("find.cmake", .cmake), ("App.vue", .vue), ("style.scss", .scss),
        ("deploy.ps1", .powerShell), ("run.bat", .batch), ("config.fish", .fish), ("env.nu", .nushell),
        ("tell.applescript", .appleScript), ("schema.prisma", .prisma), ("flow.puml", .plantUML), ("index.html", .html),
        ("query.sql", .sql), ("shader.wgsl", .wgsl), ("page.tsx", .typescript), ("app.mjs", .javascript)
    ]) func suffixesMapToTheirLanguage(filename: String, expected: SourceLanguageID) {
        #expect(language(filename) == expected, "\(filename)")
    }

    @Test(arguments: [
        ("Makefile", SourceLanguageID.makefile), ("GNUmakefile", .makefile), ("Dockerfile", .dockerfile), ("Containerfile", .dockerfile),
        ("Dockerfile.dev", .dockerfile), ("Jenkinsfile", .groovy), ("Vagrantfile", .ruby), ("Gemfile", .ruby), ("Fastfile", .ruby),
        ("Justfile", .just), ("CMakeLists.txt", .cmake), ("meson.build", .meson), ("BUILD", .starlark), ("WORKSPACE", .starlark),
        ("BUILD.bazel", .starlark), (".zshrc", .shell), (".bash_profile", .shell), (".gitignore", .ignoreList),
        (".dockerignore", .ignoreList), ("go.mod", .go)
    ]) func exactNamesMapToTheirLanguage(filename: String, expected: SourceLanguageID) {
        #expect(language(filename) == expected, "\(filename)")
    }

    @Test func unknownAndMissingNamesHaveNoLanguage() {
        #expect(language("notes") == nil)
        #expect(language("data.unknownsuffix") == nil)
        #expect(SourceLanguageDetector.language(for: nil) == nil)
        // A suffix that belongs to another format is not guessed as a language.
        #expect(language("page.md") == nil && language("table.csv") == nil && language("config.json") == nil)
    }

    @Test(arguments: [
        ("#!/bin/bash", SourceLanguageID.shell), ("#!/bin/sh -e", .shell), ("#!/usr/bin/env python3", .python),
        ("#!/usr/bin/env -S node --harmony", .javascript), ("#!/usr/bin/perl -w", .perl), ("#!/usr/bin/ruby3.3", .ruby),
        ("#!/usr/bin/env pwsh", .powerShell), ("#!/usr/bin/env fish", .fish), ("#!/usr/bin/lua5.4", .lua)
    ]) func interpreterLinesNameTheLanguage(line: String, expected: SourceLanguageID) {
        #expect(SourceLanguageDetector.language(forInterpreterLine: Substring(line)) == expected, "\(line)")
    }

    @Test func nonInterpreterLinesAreIgnored() {
        #expect(SourceLanguageDetector.language(forInterpreterLine: "# a comment") == nil)
        #expect(SourceLanguageDetector.language(forInterpreterLine: "#!/usr/bin/unknown-tool") == nil)
        #expect(SourceLanguageDetector.language(forInterpreterLine: "#!") == nil)
        #expect(SourceLanguageDetector.language(forInterpreterLine: "#!/usr/bin/env") == nil)
    }

    @Test func everyLanguageIdentifierCanBeProducedFromAFileName() {
        // The language list and the detector tables must agree: every identifier is reachable by name.
        #expect(SourceLanguageID.all.count >= 60)
        #expect(Set(SourceLanguageID.all.map(\.rawValue)).count == SourceLanguageID.all.count)
        for id in SourceLanguageID.all {
            let file = Self.representativeFiles[id.rawValue]
            #expect(file != nil, "No representative file for \(id.rawValue)")
            if let file { #expect(language(file) == id, "\(file) should be \(id.rawValue)") }
        }
        #expect(Set(Self.representativeFiles.keys) == Set(SourceLanguageID.all.map(\.rawValue)))
    }

    /// One file name per language, written out independently of the production tables.
    private static let representativeFiles: [String: String] = [
        "c": "a.c", "cpp": "a.cpp", "objective-c": "a.m", "objective-cpp": "a.mm", "csharp": "a.cs", "fsharp": "a.fsx",
        "visual-basic": "a.vb", "java": "a.java", "kotlin": "a.kt", "scala": "a.scala", "groovy": "a.groovy", "swift": "a.swift",
        "go": "a.go", "rust": "a.rs", "zig": "a.zig", "nim": "a.nim", "crystal": "a.cr", "d": "a.d", "dart": "a.dart",
        "pascal": "a.pas", "ada": "a.adb", "fortran": "a.f90", "assembly": "a.asm", "javascript": "a.js", "typescript": "a.ts",
        "python": "a.py", "ruby": "a.rb", "php": "a.php", "perl": "a.pl", "lua": "a.lua", "r": "a.r", "julia": "a.jl",
        "coffeescript": "a.coffee", "awk": "a.awk", "haskell": "a.hs", "ocaml": "a.ml", "elixir": "a.ex", "erlang": "a.erl",
        "elm": "a.elm", "clojure": "a.clj", "lisp": "a.lisp", "shell": "a.sh", "fish": "a.fish", "powershell": "a.ps1",
        "batch": "a.bat", "nushell": "a.nu", "applescript": "a.applescript", "vhdl": "a.vhd", "verilog": "a.v",
        "systemverilog": "a.sv", "solidity": "a.sol", "sql": "a.sql", "graphql": "a.graphql", "protobuf": "a.proto",
        "thrift": "a.thrift", "prisma": "a.prisma", "hcl": "a.tf", "nix": "a.nix", "starlark": "a.bzl", "cmake": "a.cmake",
        "meson": "meson.build", "makefile": "Makefile", "dockerfile": "Dockerfile", "just": "Justfile", "jsonnet": "a.jsonnet",
        "plantuml": "a.puml", "ignore": ".gitignore", "html": "a.html", "css": "a.css", "scss": "a.scss", "sass": "a.sass",
        "less": "a.less", "stylus": "a.styl", "vue": "a.vue", "svelte": "a.svelte", "astro": "a.astro", "template": "a.erb",
        "pug": "a.pug", "glsl": "a.glsl", "hlsl": "a.hlsl", "metal": "a.metal", "wgsl": "a.wgsl", "wat": "a.wat"
    ]
}
