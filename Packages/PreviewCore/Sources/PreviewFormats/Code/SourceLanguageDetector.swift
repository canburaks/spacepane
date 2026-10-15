import Foundation
import PreviewContracts

/// Names the source language of a previewed file from its name alone, or from the interpreter named by
/// a `#!` line when the file has no name that says. It never reads file content beyond the first line
/// the caller already holds, never consults the file system and never decides which format handles a
/// file: format identity comes from the catalog.
///
/// The language is more than a colour. The script-effects lens (decision 029) reads a file as the shell,
/// PowerShell, batch or AppleScript language named here, so a wrong guess can change the findings a file
/// gets as well as its colours. A `.tool` file is named shell here; the lens reads its `#!` line itself,
/// because this name-only lookup cannot see that line.
///
/// Lookup order: exact lowercased file name, then well-known name prefixes (`Dockerfile.dev`), then the
/// final suffix (`app.dockerfile`). Suffixes with several plausible
/// languages (`.h` C or C++, `.m` Objective-C or MATLAB, `.v` Verilog or Coq, `.pl` Perl or Prolog)
/// resolve to the reading that matches the system's type declaration or the larger user base. A wrong
/// guess changes colours and the script lens's reading; it never changes which format handles the file.
public enum SourceLanguageDetector {
    public static func language(for hint: PreviewNameHint?) -> SourceLanguageID? {
        guard let hint else { return nil }
        if let named = names[hint.filename] { return named }
        for (prefix, language) in prefixes where hint.filename.hasPrefix(prefix) { return language }
        guard !hint.suffix.isEmpty else { return nil }
        return suffixes[hint.suffix]
    }

    /// The language named by a `#!` first line such as `#!/usr/bin/env python3` or `#!/bin/bash -e`.
    /// Only the interpreter's file name is used; arguments and paths are ignored. `env` and `-S`
    /// skip to the real interpreter.
    public static func language(forInterpreterLine line: Substring) -> SourceLanguageID? {
        guard line.hasPrefix("#!") else { return nil }
        let words = line.dropFirst(2).split(whereSeparator: { $0 == " " || $0 == "\t" }).prefix(4)
        var candidates = Array(words)
        if let first = candidates.first, first.split(separator: "/").last == "env" {
            candidates.removeFirst()
            candidates.removeAll(where: { $0.hasPrefix("-") })
        }
        guard let program = candidates.first?.split(separator: "/").last else { return nil }
        var name = program.lowercased()
        // Versioned interpreters (python3.12, ruby3.3, perl5) share their family's language.
        while let last = name.last, last.isNumber || last == "." { name.removeLast() }
        return interpreters[name]
    }

    // MARK: Tables

    private static func table(_ rows: [(SourceLanguageID, String)]) -> [String: SourceLanguageID] {
        var result: [String: SourceLanguageID] = [:]
        for (language, words) in rows {
            for word in words.split(separator: " ") { result[String(word)] = language }
        }
        return result
    }

    /// Final suffixes, lowercased and without the dot.
    private static let suffixes: [String: SourceLanguageID] = table([
        (.swift, "swift"),
        (.c, "c"),
        (.cpp, "cpp cc cxx c++ hpp hh hxx h++ h cu cuh ino ipp inl"),
        (.objectiveC, "m"),
        (.objectiveCpp, "mm"),
        (.csharp, "cs csx"),
        (.fsharp, "fs fsx fsi fsscript"),
        (.visualBasic, "vb vbs bas"),
        (.java, "java"),
        (.kotlin, "kt kts"),
        (.scala, "scala sc sbt"),
        (.groovy, "groovy gradle gvy gy"),
        (.go, "go"),
        (.rust, "rs"),
        (.zig, "zig"),
        (.nim, "nim nims nimble"),
        (.crystal, "cr"),
        (.d, "d"),
        (.dart, "dart"),
        (.pascal, "pas dpr lpr"),
        (.ada, "adb ads ada"),
        (.fortran, "f f77 f90 f95 f03 f08 for ftn"),
        (.assembly, "asm s nasm"),
        (.javascript, "js mjs cjs jsx"),
        (.typescript, "ts tsx mts cts"),
        (.python, "py pyw pyi"),
        (.ruby, "rb rake gemspec podspec ru"),
        (.php, "php phtml"),
        (.perl, "pl pm"),
        (.lua, "lua"),
        (.r, "r"),
        (.julia, "jl"),
        (.coffeeScript, "coffee litcoffee"),
        (.awk, "awk"),
        (.haskell, "hs lhs purs"),
        (.ocaml, "ml mli mll mly"),
        (.elixir, "ex exs eex heex leex"),
        (.erlang, "erl hrl"),
        (.elm, "elm"),
        (.clojure, "clj cljs cljc"),
        (.lisp, "lisp lsp rkt scm el"),
        (.shell, "sh bash zsh ksh csh tcsh command tool"),
        (.fish, "fish"),
        (.powerShell, "ps1 psm1 psd1"),
        (.batch, "bat cmd"),
        (.nushell, "nu"),
        (.appleScript, "applescript"),
        (.vhdl, "vhd vhdl"),
        (.verilog, "v vh"),
        (.systemVerilog, "sv svh"),
        (.solidity, "sol"),
        (.sql, "sql psql pgsql"),
        (.graphQL, "graphql gql graphqls"),
        (.protobuf, "proto"),
        (.thrift, "thrift"),
        (.prisma, "prisma"),
        (.hcl, "tf tfvars hcl"),
        (.nix, "nix"),
        (.starlark, "bzl bazel star"),
        (.cmake, "cmake"),
        (.makefile, "mk mak make"),
        (.dockerfile, "dockerfile"),
        (.jsonnet, "jsonnet libsonnet"),
        (.plantUML, "puml plantuml wsd"),
        (.html, "html htm"),
        (.css, "css"),
        (.scss, "scss"),
        (.sass, "sass"),
        (.less, "less"),
        (.stylus, "styl"),
        (.vue, "vue"),
        (.svelte, "svelte"),
        (.astro, "astro"),
        (.template, "ejs hbs handlebars mustache twig liquid njk erb razor cshtml haml slim"),
        (.pug, "pug jade"),
        (.glsl, "glsl vert frag"),
        (.hlsl, "hlsl"),
        (.metal, "metal"),
        (.wgsl, "wgsl"),
        (.webAssemblyText, "wat wast")
    ])

    /// Exact lowercased file names, including extension-free build files and dotfiles.
    private static let names: [String: SourceLanguageID] = table([
        (.shell, ".zshrc .zprofile .zshenv .zlogin .zlogout .bashrc .bash_profile .bash_login .bash_logout .bash_aliases "
            + ".profile .envrc zshrc zprofile zshenv zlogin zlogout bashrc profile"),
        (.makefile, "makefile gnumakefile"),
        (.dockerfile, "dockerfile containerfile"),
        (.ruby, "gemfile rakefile podfile brewfile vagrantfile fastfile appfile matchfile snapfile gymfile scanfile "
            + "guardfile capfile thorfile berksfile puppetfile dangerfile cartfile cartfile.private"),
        (.groovy, "jenkinsfile"),
        (.just, "justfile .justfile"),
        (.cmake, "cmakelists.txt"),
        (.meson, "meson.build meson_options.txt"),
        (.starlark, "build build.bazel workspace workspace.bazel module.bazel"),
        (.ignoreList, ".gitignore .gitattributes .dockerignore .npmignore .eslintignore .prettierignore .hgignore .ignore"),
        (.go, "go.mod go.work")
    ])

    /// Names such as `Dockerfile.dev` or `Containerfile.prod`.
    private static let prefixes: [(String, SourceLanguageID)] = [
        ("dockerfile.", .dockerfile), ("containerfile.", .dockerfile)
    ]

    private static let interpreters: [String: SourceLanguageID] = table([
        (.shell, "sh bash zsh ksh csh tcsh dash ash busybox"),
        (.fish, "fish"),
        (.python, "python pypy"),
        (.ruby, "ruby jruby"),
        (.php, "php"),
        (.perl, "perl"),
        (.lua, "lua luajit"),
        (.r, "rscript"),
        (.javascript, "node nodejs deno bun"),
        (.typescript, "ts-node tsx"),
        (.powerShell, "pwsh powershell"),
        (.nushell, "nu"),
        (.awk, "awk gawk mawk nawk"),
        (.elixir, "elixir"),
        (.groovy, "groovy"),
        (.julia, "julia"),
        (.swift, "swift"),
        (.lisp, "racket guile sbcl scheme")
    ])
}
