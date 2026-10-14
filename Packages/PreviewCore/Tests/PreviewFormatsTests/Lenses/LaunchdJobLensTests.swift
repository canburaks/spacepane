import Foundation
import Testing
import PreviewContracts
import PreviewFormats

private func request(fileName: String = "com.example.job.plist") -> PreviewLensRequest {
    PreviewLensRequest(formatID: .propertyList, fileName: fileName, parentDirectoryName: "LaunchAgents", origin: .converted)
}

private func findings(_ text: String, fileName: String = "com.example.job.plist") throws -> [PreviewFinding] {
    try LaunchdJobLens().findings(in: text, request: request(fileName: fileName), context: RequestContext(budget: .standard))
}

private func found(_ kind: PreviewFindingKind, in findings: [PreviewFinding]) -> PreviewFinding? {
    findings.first { $0.kind == kind }
}

/// A job whose program is `program`, in the layout the property-list adapter writes: sorted keys,
/// escaped slashes and a space before each colon.
private func job(program: String, arguments: [String] = []) -> String {
    let rest = arguments.map { ",\n    \"\($0)\"" }.joined()
    return """
    {
      "Label" : "com.example.job",
      "ProgramArguments" : [
        "\(program)"\(rest)
      ]
    }
    """
}

@Suite("launchd job lens")
struct LaunchdJobLensTests {
    // MARK: Positives

    @Test func reportsEveryFactWithItsLine() throws {
        let text = #"""
        {
          "KeepAlive" : true,
          "Label" : "com.example.sync",
          "ProgramArguments" : [
            "\/usr\/local\/bin\/sync",
            "--quiet"
          ],
          "RunAtLoad" : true,
          "StartCalendarInterval" : {
            "Hour" : 3
          },
          "StartInterval" : 300,
          "WatchPaths" : [
            "\/var\/data\/a",
            "\/var\/data\/b"
          ]
        }
        """#
        let result = try findings(text)
        #expect(Set(result.map(\.kind)) == [.launchJob, .launchKeepAlive, .launchAtLoad, .launchSchedule, .launchInterval, .launchWatchPaths])
        #expect(found(.launchJob, in: result)?.lines == [3])
        #expect(found(.launchKeepAlive, in: result)?.lines == [2])
        #expect(found(.launchAtLoad, in: result)?.lines == [8])
        #expect(found(.launchSchedule, in: result)?.lines == [9])
        let interval = try #require(found(.launchInterval, in: result))
        #expect(interval.lines == [12])
        #expect(interval.detail == .seconds(300))
        let watch = try #require(found(.launchWatchPaths, in: result))
        #expect((watch.count, watch.lines) == (2, [13]))
    }

    @Test func aProgramKeyAloneMakesAJob() throws {
        let result = try findings(#"{ "Label" : "com.example.job", "Program" : "\/usr\/local\/bin\/tool" }"#)
        #expect(result.map(\.kind) == [.launchJob])
        #expect(result.first?.lines == [1])
        #expect(result.first?.detail == PreviewFindingDetail.none)
    }

    @Test func keepAliveTrueOrANonEmptyDictionaryCounts() throws {
        for value in ["true", #"{ "SuccessfulExit" : false }"#, #"{ "PathState" : { "\/tmp\/flag" : true } }"#] {
            let result = try findings("{ \"Label\" : \"a\", \"Program\" : \"\\/bin\\/x\", \"KeepAlive\" : \(value) }")
            #expect(found(.launchKeepAlive, in: result) != nil, "\(value)")
        }
        for value in ["false", "{}", "1", "\"yes\""] {
            let result = try findings("{ \"Label\" : \"a\", \"Program\" : \"\\/bin\\/x\", \"KeepAlive\" : \(value) }")
            #expect(found(.launchKeepAlive, in: result) == nil, "\(value)")
        }
    }

    @Test func runAtLoadCountsOnlyWhenTrue() throws {
        let base = "{ \"Label\" : \"a\", \"Program\" : \"\\/bin\\/x\", \"RunAtLoad\" : "
        #expect(found(.launchAtLoad, in: try findings(base + "true }")) != nil)
        #expect(found(.launchAtLoad, in: try findings(base + "false }")) == nil)
        #expect(found(.launchAtLoad, in: try findings(base + "1 }")) == nil)
    }

    @Test func startIntervalReportsSecondsWhenPositive() throws {
        let base = "{ \"Label\" : \"a\", \"Program\" : \"\\/bin\\/x\", \"StartInterval\" : "
        #expect(found(.launchInterval, in: try findings(base + "3600 }"))?.detail == .seconds(3600))
        #expect(found(.launchInterval, in: try findings(base + "0 }")) == nil)
        #expect(found(.launchInterval, in: try findings(base + "-5 }")) == nil)
        #expect(found(.launchInterval, in: try findings(base + "\"60\" }")) == nil)
        #expect(found(.launchInterval, in: try findings(base + "99999999999 }"))?.detail == .seconds(Int(UInt32.max)))
    }

    @Test func calendarIntervalAsDictionaryOrNonEmptyArrayIsASchedule() throws {
        let base = "{ \"Label\" : \"a\", \"Program\" : \"\\/bin\\/x\", \"StartCalendarInterval\" : "
        #expect(found(.launchSchedule, in: try findings(base + "{ \"Minute\" : 5 } }")) != nil)
        #expect(found(.launchSchedule, in: try findings(base + "[ { \"Hour\" : 1 }, { \"Hour\" : 2 } ] }")) != nil)
        #expect(found(.launchSchedule, in: try findings(base + "[] }")) == nil)
        #expect(found(.launchSchedule, in: try findings(base + "{} }")) == nil)
    }

    @Test func watchPathsAndQueueDirectoriesAreCountedTogether() throws {
        let text = """
        {
          "Label" : "a",
          "Program" : "x",
          "QueueDirectories" : [
            "q"
          ],
          "WatchPaths" : [
            "w1",
            "w2"
          ]
        }
        """
        let watch = try #require(found(.launchWatchPaths, in: try findings(text)))
        #expect((watch.count, watch.lines) == (3, [4, 7]))
        #expect(found(.launchWatchPaths, in: try findings("{ \"Label\" : \"a\", \"Program\" : \"x\", \"WatchPaths\" : [] }")) == nil)
    }

    // MARK: Program location

    @Test(arguments: [
        "/tmp/run", "/private/tmp/run", "/var/tmp/run", "/private/var/tmp/run", "/Users/Shared/run", "/TMP/run",
        "/Users/me/.hidden/run", "/Users/me/.run", "/opt/.cache/bin/run"
    ])
    func hiddenOrTemporaryProgramLocationsAreReported(path: String) throws {
        let result = try findings(job(program: path.replacingOccurrences(of: "/", with: "\\/")))
        let finding = try #require(found(.launchHiddenLocation, in: result), "\(path)")
        #expect(finding.lines == [3])
        #expect(finding.detail == PreviewFindingDetail.none)
    }

    @Test(arguments: [
        "/usr/local/bin/run", "/Applications/Tool.app/Contents/MacOS/Tool", "/Users/me/Library/Application Support/Tool/run",
        "/opt/tmp/run", "/tmpfiles/run", "/var/tmpx/run", "/Users/SharedFolder/run", "/usr/local/./bin/run",
        "/usr/local/../bin/run", "/Users/me/bin/run.sh", "run"
    ])
    func ordinaryProgramLocationsStaySilent(path: String) throws {
        #expect(found(.launchHiddenLocation, in: try findings(job(program: path.replacingOccurrences(of: "/", with: "\\/")))) == nil)
    }

    @Test func theProgramKeyWinsOverTheFirstArgument() throws {
        let text = """
        {
          "Label" : "a",
          "Program" : "\\/tmp\\/real",
          "ProgramArguments" : [
            "\\/usr\\/bin\\/ordinary"
          ]
        }
        """
        #expect(found(.launchHiddenLocation, in: try findings(text))?.lines == [3])
        let swapped = text.replacingOccurrences(of: "\\/tmp\\/real", with: "\\/usr\\/bin\\/real")
            .replacingOccurrences(of: "\\/usr\\/bin\\/ordinary", with: "\\/tmp\\/ordinary")
        #expect(found(.launchHiddenLocation, in: try findings(swapped)) == nil)
    }

    // MARK: Inline scripts

    @Test(arguments: [
        ("/bin/bash", ["-c", "echo hi"]), ("/bin/sh", ["-c", "echo hi"]), ("/bin/zsh", ["-lc", "echo hi"]),
        ("/bin/bash", ["-l", "-c", "echo hi"]), ("/bin/bash", ["--login", "-c", "echo hi"]),
        ("/usr/bin/osascript", ["-e", "beep"]), ("/usr/bin/python3", ["-c", "print(1)"]),
        ("/usr/bin/python", ["-c", "print(1)"]), ("/usr/bin/perl", ["-e", "print 1"]), ("/usr/bin/perl", ["-pe", "s/a/b/"]),
        ("/usr/bin/ruby", ["-e", "puts 1"]), ("/usr/local/bin/node", ["-e", "console.log(1)"]),
        ("/bin/FISH", ["-c", "echo hi"])
    ])
    func interpretersRunningAnInlineScriptAreReported(program: String, arguments: [String]) throws {
        let result = try findings(job(program: program.replacingOccurrences(of: "/", with: "\\/"), arguments: arguments))
        let finding = try #require(found(.launchInlineScript, in: result), "\(program)")
        #expect(finding.lines == [3])
        #expect(finding.detail == PreviewFindingDetail.none)
    }

    @Test(arguments: [
        ("/bin/sh", ["/Users/me/run.sh"]), ("/bin/bash", ["-e", "/Users/me/run.sh"]), ("/bin/bash", ["-x", "run.sh", "-c"]),
        ("/usr/bin/python3", ["/Users/me/run.py", "-c", "config"]), ("/usr/local/bin/mytool", ["-c", "config"]),
        ("/usr/bin/env", ["bash", "-c", "echo hi"]), ("/bin/bash", []), ("/usr/bin/perl", ["-c", "script.pl"]),
        ("/usr/bin/python3", ["-e", "x"]), ("/bin/bash", ["--", "-c"]), ("/bin/bash", ["-"])
    ])
    func scriptsAndOrdinaryToolsStaySilent(program: String, arguments: [String]) throws {
        let result = try findings(job(program: program.replacingOccurrences(of: "/", with: "\\/"), arguments: arguments))
        #expect(found(.launchInlineScript, in: result) == nil, "\(program) \(arguments)")
    }

    @Test func theProgramKeyNamesTheInterpreterAndArgumentZeroIsSkipped() throws {
        let text = """
        {
          "Label" : "a",
          "Program" : "\\/bin\\/bash",
          "ProgramArguments" : [
            "bash",
            "-c",
            "echo hi"
          ]
        }
        """
        #expect(found(.launchInlineScript, in: try findings(text))?.lines == [4])
        // Argument zero is the process name, never an option: "-c" there is not an inline script.
        let named = text.replacingOccurrences(of: "\"bash\",\n    \"-c\"", with: "\"-c\",\n    \"x\"")
        #expect(found(.launchInlineScript, in: try findings(named)) == nil)
    }

    // MARK: Near misses and malformed input

    @Test(arguments: [
        #"{ "Program" : "\/bin\/x", "RunAtLoad" : true }"#,
        #"{ "Label" : "a", "RunAtLoad" : true }"#,
        #"{ "Label" : "a", "ProgramArguments" : [], "RunAtLoad" : true }"#,
        #"{ "Label" : "a", "Program" : "", "RunAtLoad" : true }"#,
        #"{ "Label" : 7, "Program" : "\/bin\/x", "RunAtLoad" : true }"#,
        #"{ "Label" : "", "Program" : "\/bin\/x", "RunAtLoad" : true }"#,
        #"{ "Label" : "a", "ProgramArguments" : "\/bin\/x", "RunAtLoad" : true }"#,
        #"{ "Label" : "a", "ProgramArguments" : [ 5 ], "RunAtLoad" : true }"#,
        #"[ { "Label" : "a", "Program" : "x" } ]"#,
        #"{ "CFBundleIdentifier" : "com.example.app", "RunAtLoad" : true }"#
    ])
    func anythingButALaunchdJobStaysSilent(text: String) throws {
        #expect(try findings(text).isEmpty)
    }

    @Test(arguments: ["", "{", "{ \"Label\" : \"a\", \"Program\" : }", "not json", "{ \"Label\" : \"a\" \"Program\" : \"x\" }"])
    func malformedTextProducesNothingAndDoesNotThrow(text: String) throws {
        #expect(try findings(text).isEmpty)
    }

    @Test func aLookAlikeKeyDoesNotMatch() throws {
        // U+212A KELVIN SIGN: canonically equal to "K" in Swift, a different key in the file.
        let text = "{ \"Label\" : \"a\", \"Program\" : \"x\", \"\u{212A}eepAlive\" : true }"
        #expect(found(.launchKeepAlive, in: try findings(text)) == nil)
    }

    // MARK: Concealment

    @Test func concealedValuesDoNotHideTheJob() throws {
        let token = SecretFieldPolicy.concealmentToken
        let text = """
        {
          "EnvironmentVariables" : {
            "API_TOKEN" : \(token)
          },
          "Label" : "com.example.job",
          "ProgramArguments" : [
            "\\/tmp\\/tool",
            \(token)
          ],
          "RunAtLoad" : true
        }
        """
        let result = try findings(text)
        #expect(Set(result.map(\.kind)) == [.launchJob, .launchHiddenLocation, .launchAtLoad])
        #expect(found(.launchJob, in: result)?.lines == [5])
        #expect(found(.launchHiddenLocation, in: result)?.lines == [6])
    }

    @Test func aConcealedProgramPathIsNotJudged() throws {
        let token = SecretFieldPolicy.concealmentToken
        let text = "{ \"Label\" : \"a\", \"ProgramArguments\" : [ \(token), \"-c\", \"x\" ] }"
        #expect(try findings(text).map(\.kind) == [.launchJob])
    }

    // MARK: Cancellation

    @Test func cancellationStopsAnActiveRead() async throws {
        var text = "{\n  \"Label\" : \"com.example.job\",\n  \"ProgramArguments\" : [\n    \"\\/bin\\/x\"\n  ],\n  \"WatchPaths\" : [\n"
        for index in 0..<500 { text += "    \"\\/var\\/watch\\/\(index)\",\n" }
        text += "    \"last\"\n  ]\n}\n"
        let source = text
        let completed = try await CancellationTest.expectStopsActiveParse(budget: .standard) { context in
            let result = try LaunchdJobLens().findings(in: source, request: request(), context: context)
            return ParsedTextDocument(text: "\(result.count)")
        }
        #expect(completed.text == "2")
    }
}
