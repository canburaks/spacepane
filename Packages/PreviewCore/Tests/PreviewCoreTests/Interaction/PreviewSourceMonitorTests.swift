import Foundation
import Testing
@testable import PreviewCore

extension LiveReload {
    @Suite("Source monitor")
    struct Monitor {
        @Test func modifyingTheFileInPlaceIsReportedOnce() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            try overwrite(file, with: "two\n")
            #expect(await eventually { collector.events == [.modified] })
            await settle()
            #expect(collector.events == [.modified])
            await monitor.stopAndWait()
        }

        @Test func appendingAndAttributeChangesAreReported() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            try append(file, "more\n")
            #expect(await eventually { collector.events.count == 1 })
            await settle()
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            #expect(await eventually { collector.events.count == 2 })
            #expect(collector.events == [.modified, .modified])
            await monitor.stopAndWait()
        }

        @Test func anAtomicSaveIsFollowedToTheNewFileAndWatchingContinues() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            // Foundation writes a temporary file and renames it over the original.
            try "replaced\n".write(to: file, atomically: true, encoding: .utf8)
            #expect(await eventually { collector.events == [.replaced] })
            await settle()
            // The monitor now watches the new file: an in-place edit of it is seen.
            try append(file, "edited\n")
            #expect(await eventually { collector.events == [.replaced, .modified] })
            await monitor.stopAndWait()
        }

        @Test func repeatedAtomicSavesKeepBeingFollowed() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            for round in 1...5 {
                try "save \(round)\n".write(to: file, atomically: true, encoding: .utf8)
                #expect(await eventually { collector.events.count == round }, "save \(round)")
            }
            #expect(collector.events == Array(repeating: .replaced, count: 5))
            await monitor.stopAndWait()
        }

        @Test func renamingTheFileAwayEndsTheMonitorWithRemoved() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            try FileManager.default.moveItem(at: file, to: scratch.url.appendingPathComponent("moved.txt"))
            #expect(await eventually { collector.isFinished })
            #expect(collector.events == [.removed])
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
        }

        @Test func deletingTheFileEndsTheMonitorWithRemoved() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            try FileManager.default.removeItem(at: file)
            #expect(await eventually { collector.isFinished })
            #expect(collector.events == [.removed])
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
            withExtendedLifetime(monitor) {}
        }

        @Test func aFileRecreatedSoonAfterDeletionIsAReplacementNotARemoval() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            try FileManager.default.removeItem(at: file)
            try await Task.sleep(for: .milliseconds(30))
            try Data("again\n".utf8).write(to: file)
            #expect(await eventually { collector.events == [.replaced] })
            await settle()
            #expect(collector.events == [.replaced] && !collector.isFinished)
            await monitor.stopAndWait()
        }

        @Test func aBurstOfChangesIsOneReport() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            for index in 0..<60 { try append(file, "line \(index)\n") }
            #expect(await eventually { !collector.events.isEmpty })
            await settle(.milliseconds(400))
            #expect(collector.events == [.modified])
            await monitor.stopAndWait()
        }

        @Test func endlessChangesAreStillReportedWithinTheMaximumDelay() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let timing = PreviewSourceMonitor.Timing(debounce: .milliseconds(200), maximumDelay: .milliseconds(400),
                                                     reopenDelays: [])
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: timing))
            let collector = EventCollector(monitor)
            // A change every 40 ms never leaves a 200 ms quiet period, yet reports must still arrive.
            for index in 0..<30 {
                try append(file, "tick \(index)\n")
                try await Task.sleep(for: .milliseconds(40))
            }
            #expect(collector.events.count >= 2)
            await monitor.stopAndWait()
        }

        @Test func aQuietFileProducesNoReports() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            await settle(.milliseconds(500))
            #expect(collector.events.isEmpty && !collector.isFinished)
            await monitor.stopAndWait()
        }

        @Test func aFolderIsWatchedThroughItsOwnVnode() async throws {
            let scratch = try ScratchDirectory()
            let folder = scratch.url.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let monitor = try #require(PreviewSourceMonitor(watching: folder, timing: quickTiming))
            let collector = EventCollector(monitor)
            try Data("new".utf8).write(to: folder.appendingPathComponent("entry.txt"))
            #expect(await eventually { collector.events == [.modified] })
            try FileManager.default.moveItem(at: folder, to: scratch.url.appendingPathComponent("elsewhere"))
            #expect(await eventually { collector.isFinished })
            #expect(collector.events == [.modified, .removed])
            withExtendedLifetime(monitor) {}
        }

        @Test func onlyRegularFilesAndFoldersCanBeWatched() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            #expect(PreviewSourceMonitor(watching: scratch.url.appendingPathComponent("missing.txt")) == nil)
            let pipe = scratch.url.appendingPathComponent("pipe")
            #expect(mkfifo(pipe.path, 0o600) == 0)
            #expect(PreviewSourceMonitor(watching: pipe) == nil)
            #expect(PreviewSourceMonitor(watching: URL(fileURLWithPath: "/dev/null")) == nil)
            #expect(PreviewSourceMonitor.openDescriptorCount == baseline)
        }

        @Test func stoppingClosesTheDescriptorAndSilencesEverything() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            #expect(PreviewSourceMonitor.openDescriptorCount == baseline + 1)
            await monitor.stopAndWait()
            #expect(PreviewSourceMonitor.openDescriptorCount == baseline)
            #expect(await eventually { collector.isFinished })
            try overwrite(file, with: "after stop\n")
            await settle()
            #expect(collector.events.isEmpty)
            // Stopping again is harmless.
            monitor.stop()
            await monitor.stopAndWait()
        }

        @Test func aPendingReportIsDroppedWhenTheMonitorStops() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let timing = PreviewSourceMonitor.Timing(debounce: .milliseconds(300), maximumDelay: .seconds(2), reopenDelays: [])
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: timing))
            let collector = EventCollector(monitor)
            try overwrite(file, with: "changed\n")
            try await Task.sleep(for: .milliseconds(50))
            await monitor.stopAndWait()
            await settle(.milliseconds(450))
            #expect(collector.events.isEmpty)
        }

        @Test func cancellingTheConsumerReleasesTheDescriptor() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            let collector = EventCollector(monitor)
            #expect(PreviewSourceMonitor.openDescriptorCount == baseline + 1)
            collector.cancel()
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
            withExtendedLifetime(monitor) {}
        }

        @Test func droppingTheMonitorReleasesTheDescriptor() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            let file = try scratch.file()
            do {
                let monitor = PreviewSourceMonitor(watching: file, timing: quickTiming)
                #expect(monitor != nil)
                #expect(PreviewSourceMonitor.openDescriptorCount == baseline + 1)
            }
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
        }

        @Test func noDescriptorLeaksAcrossManyLifecycles() async throws {
            let baseline = await drainedDescriptors()
            let scratch = try ScratchDirectory()
            for round in 0..<20 {
                let file = try scratch.file("round-\(round).txt")
                let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
                let collector = EventCollector(monitor)
                switch round % 4 {
                case 0: try overwrite(file, with: "edit\n")
                case 1: try "atomic\n".write(to: file, atomically: true, encoding: .utf8)
                case 2: try FileManager.default.removeItem(at: file)
                default: break
                }
                if round % 4 != 3 { #expect(await eventually(timeout: .seconds(5)) { !collector.events.isEmpty }, "round \(round)") }
                await monitor.stopAndWait()
            }
            #expect(await eventually { PreviewSourceMonitor.openDescriptorCount == baseline })
        }

        @Test func watchingNeverTouchesTheItem() async throws {
            let scratch = try ScratchDirectory()
            let file = try scratch.file(contents: "unchanged\n")
            let before = try FileManager.default.attributesOfItem(atPath: file.path)
            let listing = try FileManager.default.contentsOfDirectory(atPath: scratch.url.path)
            let monitor = try #require(PreviewSourceMonitor(watching: file, timing: quickTiming))
            await settle(.milliseconds(200))
            await monitor.stopAndWait()
            let after = try FileManager.default.attributesOfItem(atPath: file.path)
            #expect(before[.modificationDate] as? Date == after[.modificationDate] as? Date)
            #expect(before[.size] as? Int == after[.size] as? Int)
            #expect(try Data(contentsOf: file) == Data("unchanged\n".utf8))
            #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.url.path) == listing)
        }
    }
}
