import Foundation
import Testing
import PreviewContracts
@testable import PreviewFormats

private func comic(_ entries: [TestZIPEntry]) -> Data { TestZIP.make(entries) }
private func page(_ name: String, width: Int, height: Int = 10, deflate: Bool = false) -> TestZIPEntry {
    TestZIPEntry(name: name, data: TestImages.png(width, height), deflate: deflate)
}
private func summary(_ document: ParsedTextDocument) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: Data(document.text.utf8)) as? [String: Any])
}

@Suite("Comic book adapter")
struct ComicBookAdapterTests {
    @Test func pagesAreReadInNaturalNameOrder() throws {
        // The width identifies each page: page2 < page10 numerically, not lexically.
        let data = comic([page("page10.png", width: 30), page("page2.png", width: 20), page("page1.png", width: 10),
                          page("Page3.PNG", width: 25)])
        let document = try parseDocument(ComicBookAdapter(), data)
        #expect(document.images.map(\.pixelWidth) == [10, 20, 25, 30])
        #expect(document.images.allSatisfy { $0.role == .page })
        #expect(document.syntax == .json)
        #expect(document.usesStructuredPrivacy)
    }

    @Test func resourceForksHiddenFilesAndNonImagesAreIgnored() throws {
        let data = comic([
            page("__MACOSX/._page1.png", width: 99), page(".hidden.png", width: 98), page("folder/.DS_Store.png", width: 97),
            TestZIPEntry(name: "notes.txt", data: Data("text".utf8)), TestZIPEntry(name: "Thumbs.db", data: Data("db".utf8)),
            TestZIPEntry(name: "scans/", data: Data()), page("scans/page1.jpg", width: 11),
            TestZIPEntry(name: "scans/page2.jpeg", data: TestImages.jpeg(12, 10)), TestZIPEntry(name: "scans/page3.gif", data: TestImages.gif(13, 10))
        ])
        let document = try parseDocument(ComicBookAdapter(), data)
        // `page1.jpg` holds PNG bytes: the signature, not the suffix, decides the format, so it is still shown.
        #expect(document.images.map(\.pixelWidth) == [11, 12, 13])
        let facts = try summary(document)
        #expect(facts["pageCount"] as? Int == 3)
        #expect(facts["shownPages"] as? Int == 3)
        #expect(facts["partial"] as? Bool == false)
    }

    @Test func aMemberThatIsNotAnImageIsCountedButNotShown() throws {
        let data = comic([page("a.png", width: 10), TestZIPEntry(name: "b.png", data: Data("not an image".utf8)), page("c.png", width: 30)])
        let document = try parseDocument(ComicBookAdapter(), data)
        #expect(document.images.map(\.pixelWidth) == [10, 30])
        let facts = try summary(document)
        #expect(facts["pageCount"] as? Int == 3)
        #expect(facts["shownPages"] as? Int == 2)
        #expect(facts["partial"] as? Bool == true)
    }

    @Test func comicInfoProvidesTheSummaryFields() throws {
        let info = """
        <?xml version="1.0" encoding="utf-8"?>
        <ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Title>Issue &amp; Title</Title><Series>Synthetic Saga</Series>
        <Number>7</Number><Writer>Pat Writer</Writer><PageCount>12</PageCount><Summary>ignored</Summary></ComicInfo>
        """
        let data = comic([TestZIPEntry(name: "ComicInfo.xml", data: Data(info.utf8), deflate: true), page("1.png", width: 10), page("2.png", width: 12)])
        let facts = try summary(try parseDocument(ComicBookAdapter(), data))
        #expect(facts["title"] as? String == "Issue & Title")
        #expect(facts["series"] as? String == "Synthetic Saga")
        #expect(facts["issueNumber"] as? String == "7")
        #expect(facts["writer"] as? String == "Pat Writer")
        #expect(facts["pageCount"] as? Int == 2)
        #expect(facts["declaredPageCount"] as? Int == 12)
        #expect(facts["summary"] == nil)
    }

    @Test func aMissingOrMalformedComicInfoContributesNothing() throws {
        let missing = try summary(try parseDocument(ComicBookAdapter(), comic([page("1.png", width: 10)])))
        #expect(missing["title"] == nil && missing["declaredPageCount"] == nil)
        for broken in ["<ComicInfo><Title>Unclosed", "not xml at all", "<Other><Title>x</Title></Other>", ""] {
            let data = comic([TestZIPEntry(name: "ComicInfo.xml", data: Data(broken.utf8)), page("1.png", width: 10)])
            let document = try parseDocument(ComicBookAdapter(), data)
            #expect(document.images.count == 1)
        }
        let nested = comic([TestZIPEntry(name: "deep/dir/comicinfo.XML", data: Data("<ComicInfo><Title>Nested</Title></ComicInfo>".utf8)),
                            TestZIPEntry(name: "ComicInfo.xml", data: Data("<ComicInfo><Title>Root</Title></ComicInfo>".utf8)),
                            page("1.png", width: 10)])
        #expect(try summary(try parseDocument(ComicBookAdapter(), nested))["title"] as? String == "Root")
    }

    @Test func aSecretInComicInfoIsMarkedForConcealmentInTheSummary() throws {
        let info = "<ComicInfo><Title>password=synthetic-secret-value</Title></ComicInfo>"
        let document = try parseDocument(ComicBookAdapter(), comic([TestZIPEntry(name: "ComicInfo.xml", data: Data(info.utf8)), page("1.png", width: 10)]))
        let bytes = Array(document.text.utf8)
        let hidden = document.sensitiveRanges.map { String(decoding: bytes[$0.utf8Range], as: UTF8.self) }
        #expect(hidden.contains { $0.contains("synthetic-secret-value") })
    }

    // MARK: Limits

    @Test func anOversizedPageEndsTheListInsteadOfBeingSkipped() throws {
        let oversized = Data(TestImages.png().prefix(8)) + Data(repeating: 0, count: DocumentLimits.maximumEncodedImageBytes + 1)
        let data = comic([page("1.png", width: 10), TestZIPEntry(name: "2.png", data: oversized, deflate: true), page("3.png", width: 30)])
        let document = try parseDocument(ComicBookAdapter(), data, budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        #expect(document.images.map(\.pixelWidth) == [10])
        let facts = try summary(document)
        #expect(facts["pageCount"] as? Int == 3)
        #expect(facts["partial"] as? Bool == true)
    }

    @Test func atMostFiveHundredPagesAreCarried() throws {
        let png = TestImages.png(8, 8)
        let entries = (1...501).map { TestZIPEntry(name: String(format: "%03d.png", $0), data: png) }
        let document = try parseDocument(ComicBookAdapter(), comic(entries), budget: PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))
        #expect(document.images.count == 500)
        let facts = try summary(document)
        #expect(facts["pageCount"] as? Int == 501)
        #expect(facts["shownPages"] as? Int == 500)
    }

    @Test func theReadBudgetEndsThePageListAndKeepsEarlierPages() throws {
        let noise = TestImages.noisePNG(40, 40)
        let data = comic((1...8).map { TestZIPEntry(name: "\($0).png", data: noise) })
        let measuring = CountingSource(data)
        _ = try ComicBookAdapter().parse(measuring, context: documentContext(PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000)))
        let document = try parseDocument(ComicBookAdapter(), data,
                                         budget: PreviewBudget(maxInputBytes: measuring.bytesRequested - noise.count - 100, maxMilliseconds: 30_000))
        #expect(!document.images.isEmpty)
        #expect(document.images.count < 8)
        #expect(try summary(document)["partial"] as? Bool == true)
    }

    @Test func theAggregateImageCeilingIsFourTimesTheInputBudget() {
        let limits = DocumentLimits(context: documentContext(PreviewBudget(maxInputBytes: 1_000, maxMilliseconds: 30_000)))
        #expect(limits.totalImageBytes == 4_000)
        #expect(DocumentLimits(context: documentContext(PreviewBudget(maxInputBytes: 16_777_216, maxMilliseconds: 30_000))).totalImageBytes == 48 * 1_048_576)
        var collector = ImageCollector(limits: limits)
        #expect(collector.canAccept(encodedBytes: 4_000))
        #expect(!collector.canAccept(encodedBytes: 4_001))
        collector.append(PreviewImage(data: Data(count: 3_000), pixelWidth: 1, pixelHeight: 1, role: .page))
        #expect(!collector.canAccept(encodedBytes: 1_001))
    }

    // MARK: Failure modes

    @Test func anEncryptedFirstPageFailsAsEncryptedContent() {
        let data = comic([TestZIPEntry(name: "1.png", data: TestImages.png(), encrypted: true), page("2.png", width: 12)])
        #expect(throws: PreviewFailure.encryptedContent) { try parseDocument(ComicBookAdapter(), data) }
    }

    @Test func aLaterEncryptedPageEndsTheList() throws {
        let data = comic([page("1.png", width: 10), TestZIPEntry(name: "2.png", data: TestImages.png(), encrypted: true), page("3.png", width: 30)])
        #expect(try parseDocument(ComicBookAdapter(), data).images.map(\.pixelWidth) == [10])
    }

    @Test func aCorruptPageIsSkippedAndTheRestRemain() throws {
        var data = comic([page("1.png", width: 10), TestZIPEntry(name: "2.png", data: TestImages.png(20, 10)), page("3.png", width: 30)])
        let second = TestImages.png(20, 10)
        let range = try #require(data.range(of: second))
        data[range.lowerBound + 20] ^= 0xFF   // Breaks the member's CRC-32.
        let document = try parseDocument(ComicBookAdapter(), data)
        #expect(document.images.map(\.pixelWidth) == [10, 30])
    }

    @Test func anArchiveWithoutImagesStillGivesASummary() throws {
        let document = try parseDocument(ComicBookAdapter(), comic([TestZIPEntry(name: "readme.txt", data: Data("x".utf8))]))
        #expect(document.images.isEmpty)
        #expect(try summary(document)["pageCount"] as? Int == 0)
    }

    @Test func nonArchivesFailAsMalformed() {
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(ComicBookAdapter(), Data("Rar!".utf8 + [0x1A, 0x07, 0x00])) }
        #expect(throws: PreviewFailure.malformedDocument) { try parseDocument(ComicBookAdapter(), Data()) }
    }

    @Test func cancellationAndDeadlinePrecedeAnySourceRead() async {
        let data = comic([page("1.png", width: 10)])
        let source = CountingSource(data)
        let task = Task.detached { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try ComicBookAdapter().parse(source, context: documentContext()); return false } catch is CancellationError { return true } catch { return false }
        }
        #expect(await task.value)
        #expect(source.reads == 0)
        #expect(throws: PreviewFailure.deadlineExceeded) {
            _ = try ComicBookAdapter().parse(CountingSource(data), context: documentContext(PreviewBudget(maxMilliseconds: 0)))
        }
    }

    /// A page's archive member path is untrusted text that never passes the privacy stage, so no page carries it.
    @Test func pageNamesAreNeverCarriedIntoThePresentation() throws {
        let tokenName = "ghp_" + String(repeating: "a1", count: 18) + ".png"
        let data = comic([page("password-scan.png", width: 10), page(tokenName, width: 12), page("scan.png", width: 14)])
        let document = try parseDocument(ComicBookAdapter(), data)
        #expect(document.images.map(\.pixelWidth).sorted() == [10, 12, 14])
    }
}

@Suite("Natural ordering")
struct NaturalOrderTests {
    @Test func digitRunsCompareNumerically() {
        let sorted = ["page10", "page2", "Page1", "page01", "page 3", "a9", "a10", "b1", "10", "9"]
            .sorted(by: NaturalOrder.areInIncreasingOrder)
        #expect(sorted == ["9", "10", "a9", "a10", "b1", "page 3", "Page1", "page01", "page2", "page10"])
    }

    @Test func orderIsTotalAndDeterministic() {
        let names = ["x/2.png", "x/10.png", "x/1.png", "X/1.PNG", "x/01.png", "y.png", "x/1.png"]
        for left in names { for right in names {
            let forward = NaturalOrder.compare(left, right)
            let backward = NaturalOrder.compare(right, left)
            #expect((forward == .orderedSame) == (backward == .orderedSame))
            if forward == .orderedAscending { #expect(backward == .orderedDescending) }
        } }
        #expect(NaturalOrder.compare("a", "a") == .orderedSame)
        #expect(NaturalOrder.compare("a99999999999999999999", "a100000000000000000000") == .orderedAscending)
    }

    @Test func folderComponentsOrderBeforeTheirContents() {
        let sorted = ["chapter 10/1.jpg", "chapter 2/10.jpg", "chapter 2/2.jpg"].sorted(by: NaturalOrder.areInIncreasingOrder)
        #expect(sorted == ["chapter 2/2.jpg", "chapter 2/10.jpg", "chapter 10/1.jpg"])
    }
}
