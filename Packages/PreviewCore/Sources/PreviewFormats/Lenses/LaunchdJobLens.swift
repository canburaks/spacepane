import Foundation
import PreviewContracts

/// launchd job lens: what a LaunchAgent or LaunchDaemon property list makes macOS run, and when
/// (decision 029). It reads the property list as the adapter displays it, pretty-printed JSON converted
/// from the XML or binary list, so the lines are the gutter's.
///
/// A launchd job is recognized by its structure alone: a string `Label` and either a `Program` or a
/// non-empty `ProgramArguments` array. Nothing runs and nothing is resolved. A finding states a fact
/// about the job (it starts at load, it repeats every N seconds, it runs from a hidden or temporary
/// folder, it hands a script to an interpreter); it never carries the program path or any argument.
public struct LaunchdJobLens: PreviewTextLens {
    public init() {}

    public func findings(in text: String, request: PreviewLensRequest, context: RequestContext) throws -> [PreviewFinding] {
        try context.checkpoint()
        guard let root = try LensJSON.parse(text, context: context), let job = LaunchdJob(root: root) else { return [] }
        return job.findings
    }
}

private struct LaunchdJob {
    /// The executable launchd starts, as the job states it, and the line of the key that states it.
    /// `Program` wins over the first argument, as in launchd.
    private struct Executable {
        let path: String
        let line: Int
    }

    private let root: LensJSONNode
    private let label: LensJSONMember
    private let executable: Executable?
    private let argumentsKey: LensJSONMember?

    init?(root: LensJSONNode) {
        guard let label = root.member("Label"), let name = label.value.string, !name.isEmpty else { return nil }
        let program = root.member("Program")
        let arguments = root.member("ProgramArguments")
        let argumentList = arguments?.value.elements ?? []
        let programPath = program?.value.string.flatMap { $0.isEmpty ? nil : $0 }
        let first = argumentList.first
        guard programPath != nil || first?.string != nil || first?.isConcealed == true else { return nil }
        self.root = root
        self.label = label
        self.argumentsKey = arguments
        if let programPath, let program {
            executable = Executable(path: programPath, line: program.line)
        } else if let path = first?.string, let arguments {
            executable = Executable(path: path, line: arguments.line)
        } else {
            executable = nil
        }
    }

    var findings: [PreviewFinding] {
        var found = [PreviewFinding(kind: .launchJob, count: 1, lines: [label.line])]
        if let key = root.member("RunAtLoad"), key.value.bool == true {
            found.append(PreviewFinding(kind: .launchAtLoad, count: 1, lines: [key.line]))
        }
        if let key = root.member("KeepAlive"), keepsAlive(key.value) {
            found.append(PreviewFinding(kind: .launchKeepAlive, count: 1, lines: [key.line]))
        }
        if let key = root.member("StartInterval"), let seconds = Self.seconds(key.value) {
            found.append(PreviewFinding(kind: .launchInterval, count: 1, lines: [key.line], detail: .seconds(seconds)))
        }
        if let key = root.member("StartCalendarInterval"), key.value.hasContent, key.value.members != nil || key.value.elements != nil {
            found.append(PreviewFinding(kind: .launchSchedule, count: 1, lines: [key.line]))
        }
        let watched = ["WatchPaths", "QueueDirectories"].compactMap { name in
            root.member(name).map { (key: $0, entries: ($0.value.elements ?? []).filter { $0.string != nil || $0.isConcealed }.count) }
        }.filter { $0.entries > 0 }
        if !watched.isEmpty {
            found.append(PreviewFinding(kind: .launchWatchPaths, count: watched.reduce(0) { $0 + $1.entries },
                                        lines: watched.map(\.key.line)))
        }
        if let executable, ProgramLocation.isHiddenOrTemporary(executable.path) {
            found.append(PreviewFinding(kind: .launchHiddenLocation, count: 1, lines: [executable.line]))
        }
        if let executable, let argumentsKey, runsInlineScript(executable.path, arguments: argumentsKey) {
            found.append(PreviewFinding(kind: .launchInlineScript, count: 1, lines: [argumentsKey.line]))
        }
        return found
    }

    private func keepsAlive(_ value: LensJSONNode) -> Bool {
        value.bool == true || value.members?.isEmpty == false
    }

    /// A positive whole number of seconds, clamped to launchd's 32-bit interval.
    private static func seconds(_ value: LensJSONNode) -> Int? {
        guard let number = value.number, number.isFinite else { return nil }
        let whole = Int(min(number.rounded(.down), Double(UInt32.max)))
        return whole >= 1 ? whole : nil
    }

    /// Whether the executable is an interpreter that the job hands inline code, for example `bash -c`.
    /// Argument zero is the process name and is skipped. Only the leading options are examined, so a
    /// script followed by its own `-c` option is not an inline script.
    private func runsInlineScript(_ path: String, arguments key: LensJSONMember) -> Bool {
        guard let interpreter = Interpreter(executablePath: path), let list = key.value.elements else { return false }
        for argument in list.dropFirst() {
            guard let option = argument.string, option.utf8.count > 1, option.utf8.first == UInt8(ascii: "-") else { return false }
            if option.equalsExactly("--") { return false }
            if interpreter.isInlineOption(option) { return true }
        }
        return false
    }
}

/// Where a job's executable lives, judged from the path text alone.
private enum ProgramLocation {
    /// macOS volumes are case-insensitive by default, so `/TMP/run` is `/tmp/run`.
    private static let temporaryPrefixes = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/users/shared/"]

    static func isHiddenOrTemporary(_ path: String) -> Bool {
        let bytes = Array(path.utf8)
        if temporaryPrefixes.contains(where: { hasPrefixIgnoringASCIICase(bytes, $0) }) { return true }
        // A component such as `.cache` is hidden; `.` and `..` only navigate.
        let dot = UInt8(ascii: ".")
        return bytes.split(separator: UInt8(ascii: "/")).contains { component in
            guard component.first == dot else { return false }
            return !(component.count == 1 || component.count == 2 && component.last == dot)
        }
    }

    private static func hasPrefixIgnoringASCIICase(_ bytes: [UInt8], _ prefix: String) -> Bool {
        let expected = Array(prefix.utf8)
        guard bytes.count >= expected.count else { return false }
        return zip(bytes, expected).allSatisfy { lowercased($0) == $1 }
    }

    static func lowercased(_ byte: UInt8) -> UInt8 { (65...90).contains(byte) ? byte + 32 : byte }
}

private enum Interpreter {
    case shell, python, perl, ruby, node, osascript

    private static let shells: Set<String> = ["sh", "bash", "zsh", "dash", "ksh", "csh", "tcsh", "fish"]

    init?(executablePath path: String) {
        guard let component = path.utf8.split(separator: UInt8(ascii: "/")).last else { return nil }
        let name = String(decoding: component.map(ProgramLocation.lowercased), as: UTF8.self)
        if Self.shells.contains(name) { self = .shell }
        else if name == "python" || name.hasPrefix("python") && name.utf8.dropFirst(6).allSatisfy({ $0 == UInt8(ascii: ".") || (48...57).contains($0) }) {
            self = .python
        } else {
            switch name {
            case "perl": self = .perl
            case "ruby": self = .ruby
            case "node": self = .node
            case "osascript": self = .osascript
            default: return nil
            }
        }
    }

    /// An option that makes the next argument the code to run: `-c` for shells and Python, `-e` for
    /// Perl, Ruby and AppleScript, `-e` and `-p` (or their long forms) for Node. Short options may be
    /// clustered (`-lc`, `-pe`); the code-taking letter comes last.
    func isInlineOption(_ option: String) -> Bool {
        let bytes = Array(option.utf8)
        if bytes.count > 2, bytes[1] == UInt8(ascii: "-") {
            return self == .node && (option.equalsExactly("--eval") || option.equalsExactly("--print"))
        }
        let letters = bytes.dropFirst()
        guard let last = letters.last, letters.allSatisfy({ ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) }) else { return false }
        switch self {
        case .shell, .python: return last == UInt8(ascii: "c")
        case .perl: return last == UInt8(ascii: "e") || last == UInt8(ascii: "E")
        case .ruby, .osascript: return last == UInt8(ascii: "e")
        case .node: return last == UInt8(ascii: "e") || last == UInt8(ascii: "p")
        }
    }
}
