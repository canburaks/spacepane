import Foundation
import Testing
import UniformTypeIdentifiers
import PreviewContracts
@testable import PreviewFormats

@Suite("Document format catalog and registration")
struct DocumentCatalogTests {
    private let ids: [FormatID] = [.comicBook, .epub, .fictionBook, .webArchive]

    @Test func stableIdentifiersAreExactlyTheAgreedValues() {
        #expect(ids.map(\.rawValue) == ["archive.comic-book", "document.epub", "document.fictionbook", "document.web-archive"])
    }

    @Test func everyFormatIsCatalogedRegisteredAndUsesContentThumbnails() throws {
        for id in ids {
            let descriptor = try #require(FormatCatalog.standard.descriptor(for: id), "\(id.rawValue)")
            #expect(descriptor.thumbnail == .content)
            #expect(descriptor.defaultEnabled)
            #expect(descriptor.presentation == .text)
            #expect(StandardFormatAdapters.registrations.contains { $0.formatID == id })
            #expect(DocumentFormatAdapters.registrations.contains { $0.formatID == id })
        }
        #expect(Set(StandardFormatAdapters.registrations.map(\.formatID)).count == StandardFormatAdapters.registrations.count)
    }

    @Test func suffixesClassifyToTheirFormatBeforeAnyTypeFallback() {
        let expected: [(String, FormatID)] = [("comic.cbz", .comicBook), ("COMIC.CBZ", .comicBook), ("book.epub", .epub), ("story.fb2", .fictionBook),
                                              ("page.mht", .webArchive), ("page.mhtml", .webArchive)]
        for (name, id) in expected { #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/\(name)")) == id, "\(name)") }
        // A plain ZIP, an unrelated XML file and a notebook keep their own formats.
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/a.zip")) == .zip)
        #expect(FormatCatalog.standard.classify(url: URL(fileURLWithPath: "/tmp/a.xml")) == .xml)
    }

    @Test func canonicalTypesAreSystemOrImportedNeverRoot() throws {
        let epub = try #require(FormatCatalog.standard.descriptor(for: .epub))
        #expect(epub.canonicalContentType.identifier == "org.idpf.epub-container")
        let web = try #require(FormatCatalog.standard.descriptor(for: .webArchive))
        #expect(web.canonicalContentType.identifier == "org.ietf.mhtml")
        let comic = try #require(FormatCatalog.standard.descriptor(for: .comicBook))
        #expect(comic.canonicalContentType.identifier == "org.webmeister.spacepane.type.comic-book-zip")
        let fiction = try #require(FormatCatalog.standard.descriptor(for: .fictionBook))
        #expect(fiction.canonicalContentType.identifier == "org.webmeister.spacepane.type.fictionbook")
        for id in ids {
            let types = try #require(FormatCatalog.standard.descriptor(for: id)).contentTypes
            #expect(!types.contains(.data) && !types.contains(.item) && !types.contains(.content))
        }
    }

    @Test func everyAdapterRefusesToReadAfterCancellationOrAnExpiredDeadline() async {
        let task = Task.detached { () -> [String] in
            withUnsafeCurrentTask { $0?.cancel() }
            var misses: [String] = []
            for registration in DocumentFormatAdapters.registrations {
                guard case .randomAccess(let make) = registration.inputPath else { misses.append("path \(registration.formatID.rawValue)"); continue }
                let source = CountingSource(Data(repeating: 0, count: 64))
                do { _ = try make().parse(source, context: documentContext()); misses.append("returned \(registration.formatID.rawValue)") }
                catch is CancellationError {}
                catch { misses.append("error \(registration.formatID.rawValue)") }
                if source.reads != 0 { misses.append("read \(registration.formatID.rawValue)") }
            }
            return misses
        }
        #expect(await task.value.isEmpty)
        for registration in DocumentFormatAdapters.registrations {
            guard case .randomAccess(let make) = registration.inputPath else { continue }
            let source = CountingSource(Data(repeating: 0, count: 64))
            #expect(throws: PreviewFailure.deadlineExceeded, "\(registration.formatID.rawValue)") {
                _ = try make().parse(source, context: documentContext(PreviewBudget(maxMilliseconds: 0)))
            }
            #expect(source.reads == 0)
        }
    }
}
