import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Decision 030 shared helpers")
struct Sl3SharedHelpersTests {
    private let context = RequestContext(budget: .standard)

    // MARK: Native code

    @Test(arguments: [
        ("build/Release/addon.node", true), ("lib/libfoo.dylib", true), ("libssl.so", true), ("libz.so.1.2.13", true),
        ("bin/tool.EXE", true), ("ext/_speedups.cpython-312-darwin.so", true), ("pkg/mod.pyd", true),
        ("README.md", false), ("index.js", false), ("so", false), ("notes.so.txt", false), ("libx.so.beta", false),
        ("node", false), ("folder.node/readme", false)
    ])
    func nativeSuffixes(path: String, expected: Bool) {
        #expect(NativeCodeSignature.hasNativeSuffix(path) == expected, "\(path)")
    }

    @Test func machOAndELFAreNative() {
        #expect(NativeCodeSignature.isNativeBinary(prefix: Data([0xCF, 0xFA, 0xED, 0xFE, 7, 0, 0, 1])))
        #expect(NativeCodeSignature.isNativeBinary(prefix: Data([0xFE, 0xED, 0xFA, 0xCE])))
        #expect(NativeCodeSignature.isNativeBinary(prefix: Data([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0])))
    }

    @Test func universalBinaryIsNativeButAJavaClassIsNot() {
        #expect(NativeCodeSignature.isNativeBinary(prefix: Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])))
        // A Java class file: minor version 0, major version 65.
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 65])))
    }

    @Test func portableExecutableNeedsItsSignature() {
        var pe = [UInt8](repeating: 0, count: 0x90)
        pe[0] = 0x4D; pe[1] = 0x5A
        pe[0x3C] = 0x80
        pe[0x80] = 0x50; pe[0x81] = 0x45
        #expect(NativeCodeSignature.isNativeBinary(prefix: Data(pe)))
        pe[0x80] = 0x51
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data(pe)))
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data("MZ is also how a text file may start".utf8)))
    }

    @Test func shortOrTextPrefixesAreNotNative() {
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data()))
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data([0x7F, 0x45])))
        #expect(!NativeCodeSignature.isNativeBinary(prefix: Data("#!/bin/sh\n".utf8)))
    }

    // MARK: Python startup lines

    @Test func importLinesRunAndOtherLinesArePaths() throws {
        let text = "# comment\n/opt/lib/python\nimport sys; sys.path.insert(0, '/x')\n\nimport\tos\n  import os\nimportlib\nimport"
        #expect(try PythonStartupLines.lines(in: text, context: context) == [3, 5])
    }

    @Test func linesFollowLogicalLineNumbering() throws {
        #expect(try PythonStartupLines.lines(in: "a\r\nimport x\rimport y\n", context: context) == [2, 3])
        #expect(try PythonStartupLines.lines(in: "\u{FEFF}import x\n", context: context) == [1])
        #expect(try PythonStartupLines.lines(in: "", context: context).isEmpty)
    }
}
