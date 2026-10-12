import AppKit
import Foundation
import Testing
import PreviewContracts
@testable import PreviewRenderers

private func decorated(_ source: String, _ syntax: TextSyntax, units: Int = 262_144, tokens: Int = 20_000) -> [Piece] {
    let text = source as NSString
    return SourceSyntaxTokens.tokens(in: source, syntax: syntax, maximumUTF16Units: units, maximumTokens: tokens)
        .map { Piece(text.substring(with: $0.range), $0.role) }
}

@Suite("Log decoration")
struct LogSyntaxTokensTests {
    @Test(arguments: [
        ("2026-10-05T14:03:22.123Z INFO started", "2026-10-05T14:03:22.123Z"),
        ("2026-10-05 14:03:22,456 INFO started", "2026-10-05 14:03:22,456"),
        ("2026-10-05T14:03:22+02:00 INFO x", "2026-10-05T14:03:22+02:00"),
        ("2026/10/05 14:03:22 INFO x", "2026/10/05 14:03:22"),
        ("Oct  5 14:03:22 host sshd[1]: info", "Oct  5 14:03:22"),
        ("14:03:22.123 INFO x", "14:03:22.123"),
        ("[2026-10-05 14:03:22] INFO x", "2026-10-05 14:03:22"),
        ("127.0.0.1 - - [05/Oct/2026:14:03:22 +0000] \"GET /\" 200", "05/Oct/2026:14:03:22 +0000")
    ]) func timestampsInEveryCommonFormatAreNumbers(line: String, expected: String) {
        let result = decorated(line, .log)
        #expect(result.contains(Piece(expected, .number)), "\(line) → \(result)")
    }

    @Test func severitiesMapToRoles() {
        let source = """
        2026-10-05 TRACE a
        2026-10-05 DEBUG b
        2026-10-05 INFO c
        2026-10-05 WARN d
        2026-10-05 WARNING e
        2026-10-05 ERROR f
        2026-10-05 FATAL g
        2026-10-05 CRITICAL h
        2026-10-05 PANIC i
        [error] j
        level=warn k
        """
        let levels = decorated(source, .log).filter { $0.text.first?.isNumber != true }
        #expect(levels == [Piece("TRACE", .comment), Piece("DEBUG", .comment), Piece("INFO", .addition), Piece("WARN", .number),
                           Piece("WARNING", .number), Piece("ERROR", .deletion), Piece("FATAL", .deletion), Piece("CRITICAL", .deletion),
                           Piece("PANIC", .deletion), Piece("error", .deletion), Piece("warn", .number)])
    }

    @Test func ordinaryWordsAreNotSeverities() {
        let result = decorated("2026-10-05 the terror of information: an error occurred in the alerting service\n", .log)
        #expect(result == [Piece("2026-10-05", .number)])
    }

    @Test func stackFramesAndExceptionHeadlinesAreDimmedOrFlagged() {
        let source = """
        2026-10-05 ERROR failed
        java.lang.IllegalStateException: boom
        \tat com.example.Service.run(Service.java:42)
        \tat com.example.Main.main(Main.java:7)
        \t... 12 more
        Caused by: java.io.IOException: nested
        \tat node:internal/main:1
        Traceback (most recent call last):
          File "app.py", line 3, in <module>
            raise ValueError("x")
        ValueError: x
        panic: runtime error
        goroutine 1 [running]:
        main.main()
        \t/work/main.go:12 +0x1d

        0   libswiftCore.dylib            0x0000000180a1b2c4 swift_unexpectedError + 12
        """
        let result = decorated(source, .log)
        #expect(result.contains(Piece("at com.example.Service.run(Service.java:42)", .comment)))
        #expect(result.contains(Piece("at com.example.Main.main(Main.java:7)", .comment)))
        #expect(result.contains(Piece("... 12 more", .comment)))
        #expect(result.contains(Piece("Caused by: java.io.IOException: nested", .deletion)))
        #expect(result.contains(Piece("Traceback (most recent call last):", .deletion)))
        #expect(result.contains(Piece("File \"app.py\", line 3, in <module>", .comment)))
        #expect(result.contains(Piece("raise ValueError(\"x\")", .comment)))
        #expect(result.contains(Piece("panic: runtime error", .deletion)) && result.contains(Piece("goroutine 1 [running]:", .deletion)))
        #expect(result.contains(Piece("main.main()", .comment)) && result.contains(Piece("/work/main.go:12 +0x1d", .comment)))
        #expect(result.contains(Piece("0   libswiftCore.dylib            0x0000000180a1b2c4 swift_unexpectedError + 12", .comment)))
    }

    @Test func swiftCrashFramesAfterABlankLineAreStillFrames() {
        let result = decorated("1   libsystem_kernel.dylib\t0x00000001a2b3c4d5 mach_msg + 8\n", .log)
        #expect(result.count == 1 && result[0].role == .comment)
    }

    @Test func tokensStayOrderedBoundedAndPrefixLimited() {
        let source = String(repeating: "2026-10-05 ERROR x\n", count: 50)
        let all = SourceSyntaxTokens.tokens(in: source, syntax: .log)
        #expect(all.count == 100)
        var end = 0
        for token in all { #expect(token.range.location >= end); end = NSMaxRange(token.range) }
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .log, maximumTokens: 7).count == 7)
        #expect(SourceSyntaxTokens.tokens(in: source, syntax: .log, maximumUTF16Units: 20).count <= 2)
        #expect(SourceSyntaxTokens.tokens(in: "", syntax: .log).isEmpty)
    }
}

@Suite("INI, JSONC and caption decoration")
struct ConfigurationAndCaptionTokenTests {
    @Test func iniSectionsKeysCommentsAndValues() {
        let source = "; comment\n[server]\nhost = \"localhost\"\nport : 8080\nenabled=true\n# other\nname value\n  continued\n"
        let result = decorated(source, .ini)
        #expect(result.contains(Piece("; comment", .comment)) && result.contains(Piece("[server]", .heading)) && result.contains(Piece("# other", .comment)))
        #expect(result.contains(Piece("host", .key)) && result.contains(Piece("\"localhost\"", .string)))
        #expect(result.contains(Piece("port", .key)) && result.contains(Piece("8080", .number)))
        #expect(result.contains(Piece("enabled", .key)) && result.contains(Piece("true", .literal)))
        #expect(result.contains(Piece("name", .key)))
    }

    @Test func jsoncKeysCommentsLiteralsAndJson5Numbers() {
        let source = "{ // c\n  \"a\": 1, 'b': 'x', unquoted: true, /* n */ hex: 0xFF, half: .5, neg: -Infinity, list: [null, NaN,],\n}"
        let result = decorated(source, .jsonWithComments)
        #expect(result.contains(Piece("// c", .comment)) && result.contains(Piece("/* n */", .comment)))
        #expect(result.contains(Piece("\"a\"", .key)) && result.contains(Piece("'b'", .key)) && result.contains(Piece("unquoted", .key)))
        #expect(result.contains(Piece("'x'", .string)) && result.contains(Piece("true", .literal)) && result.contains(Piece("null", .literal)))
        #expect(result.contains(Piece("0xFF", .number)) && result.contains(Piece(".5", .number)) && result.contains(Piece("Infinity", .literal)))
        #expect(result.contains(Piece("NaN", .literal)))
    }

    @Test func subStationAlphaSectionsKeysTimesAndOverrides() {
        let source = "; c\n[Script Info]\nTitle: x\n[Events]\nDialogue: 0,0:00:01.00,0:00:04.00,Default,,0,0,0,,{\\i1}Hi{\\i0} there\n[Fonts]\nfontname: a.ttf\n"
        let result = decorated(source, .subStationAlpha)
        #expect(result.contains(Piece("; c", .comment)) && result.contains(Piece("[Script Info]", .heading)) && result.contains(Piece("[Events]", .heading)))
        #expect(result.contains(Piece("Title", .key)) && result.contains(Piece("Dialogue", .key)))
        #expect(result.contains(Piece("0:00:01.00", .number)) && result.contains(Piece("0:00:04.00", .number)))
        #expect(result.contains(Piece("{\\i1}", .tag)) && result.contains(Piece("{\\i0}", .tag)))
        // Lines of the data sections carry no decoration.
        #expect(!result.contains(Piece("fontname", .key)))
    }

    @Test func otherCaptionDialectsColorTimesAndTags() {
        #expect(decorated("0:00:01.000,0:00:04.500\ntext\n", .subViewer) == [Piece("0:00:01.000", .number), Piece("0:00:04.500", .number)])
        let lyrics = decorated("[ti:Song]\n[00:12.00][01:20.50]Line <00:12.30>word\n", .lyrics)
        #expect(lyrics == [Piece("ti", .key), Piece("00:12.00", .number), Piece("01:20.50", .number), Piece("<00:12.30>", .comment)])
        let dvd = decorated("{25}{100}Hello|world {y:i}x\n", .microDVD)
        #expect(dvd == [Piece("25", .number), Piece("100", .number), Piece("|", .operator), Piece("{y:i}", .tag)])
        let ttml = decorated("<tt><p begin=\"1s\">x</p><!-- c --></tt>", .timedText)
        #expect(ttml.contains(Piece("<p", .tag)) && ttml.contains(Piece("begin", .key)) && ttml.contains(Piece("\"1s\"", .string)) && ttml.contains(Piece("<!-- c -->", .comment)))
    }

    @Test(arguments: [TextSyntax.ini, .log, .jsonWithComments, .subStationAlpha, .timedText, .subViewer, .lyrics, .microDVD])
    func everySyntaxIsWellFormedOnHostileInput(syntax: TextSyntax) {
        let samples = ["", "[", "]", "[x", "{", "<", "<a", "=", ":", ";", "\u{0}", "😀", "[00:1", "{1}{", "Dialogue:", "\n\n\n", "/*", "'", "\"",
                       String(repeating: "[", count: 300), String(repeating: "<a ", count: 200), "2026-10-05T", "2026-10-05T14:03", "0:00:01.000,"]
        for sample in samples {
            let length = sample.utf16.count
            var end = 0
            for token in SourceSyntaxTokens.tokens(in: sample + "\n" + sample, syntax: syntax) {
                #expect(token.range.length > 0 && token.range.location >= end && NSMaxRange(token.range) <= length * 2 + 1, "\(syntax) \(sample)")
                end = NSMaxRange(token.range)
            }
        }
    }
}
