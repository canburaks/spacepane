import Foundation
import Synchronization
import Testing
import PreviewContracts
@testable import PreviewFormats

@Suite("Python path file lens")
struct PythonPathFileLensTests {
    private func findings(_ text: String, file: String = "extra.pth", origin: TextOrigin = .source,
                          context: RequestContext = RequestContext(budget: .standard)) throws -> [PreviewFinding] {
        let request = PreviewLensRequest(formatID: .pickle, fileName: file, parentDirectoryName: "site-packages", origin: origin)
        return try PythonPathFileLens().findings(in: text, request: request, context: context)
    }

    @Test func importLinesAreReportedWithTheirLineNumbers() throws {
        let text = """
        # added by an installer
        /opt/lib/python3/site-packages
        import sys; sys.path.insert(0, '/opt/lib')

        import\tos; os.environ.setdefault('X', '1')
        /opt/other
        """
        let result = try findings(text)
        #expect(result == [PreviewFinding(kind: .installStartupCode, count: 2, lines: [3, 5])])
        #expect(result.first?.severity == .warning)
        #expect(result.first?.detail == PreviewFindingDetail.none)
    }

    @Test(arguments: [
        "", "# a comment\n", "/opt/lib/python3\n/opt/other\n", "\n\n", "importlib.util\n", "import\n", "import\u{00A0}sys\n",
        "  import sys\n", "# import sys; evil()\n", "/opt/import sys\n", "Import sys\n", "imports sys\n"
    ])
    func commentsPathsAndNearMissesAreSilent(text: String) throws {
        #expect(try findings(text).isEmpty, "\(text.debugDescription)")
    }

    @Test func lineNumbersFollowTheLogicalLineCountOfTheShownText() throws {
        #expect(try findings("a\r\nimport x\rimport y\n").first?.lines == [2, 3])
        #expect(try findings("\u{FEFF}import x\n").first?.lines == [1])
    }

    @Test func aLongRunOfImportLinesKeepsTheCountAndBoundsTheLines() throws {
        let text = String(repeating: "import sys\n", count: 100)
        let finding = try #require(try findings(text).first)
        #expect(finding.count == 100 && finding.lines == Array(1...PreviewFinding.maximumLines))
    }

    @Test func onlySourceTextOfAPathFileIsRead() throws {
        let text = "import sys\n"
        #expect(try findings(text, file: "EXTRA.PTH").count == 1)
        for file in ["extra.pt", "extra.pth.txt", "pth", "extra.pickle", ".pt"] {
            #expect(try findings(text, file: file).isEmpty, "\(file)")
        }
        for origin in [TextOrigin.summary, .converted, .reformatted] {
            #expect(try findings(text, origin: origin).isEmpty, "\(origin)")
        }
    }

    @Test func theLensStopsWhenCancelled() async throws {
        let text = String(repeating: "/opt/lib\n", count: 50_000)
        let observed = Mutex(0)
        let task = Task.detached { () -> Bool in
            var context = RequestContext(budget: .standard)
            context.checkpointObserver = {
                if observed.withLock({ $0 += 1; return $0 }) == 3 { withUnsafeCurrentTask { $0?.cancel() } }
            }
            do { _ = try PythonPathFileLens().findings(in: text, request: PreviewLensRequest(formatID: .pickle, fileName: "x.pth"), context: context); return false }
            catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
    }
}
