import AppKit
import Foundation
import Testing
@testable import PreviewRenderers

/// Decision 027, Q-77 and review DM-31: how the plot frames longitudes across the antimeridian, the 0/360 seam and
/// the poles, so that no line is drawn across the whole map. Pure functions of positions; no view. The expectations
/// are worked out by hand for each case.
@Suite("Q77 plot framing across the antimeridian")
@MainActor
struct Q77DocumentsPlotFramingTests {
    private let english = Locale(identifier: "en_US")
    private func position(_ longitude: Double, _ latitude: Double) -> SafePlot.Position {
        SafePlot.Position(longitude: longitude, latitude: latitude)
    }
    private func plot(_ paths: [[SafePlot.Position]] = [], points: [SafePlot.Position] = []) -> SafePlot {
        SafePlot(paths: paths, points: points, simplified: false)
    }
    private func framing(_ paths: [[SafePlot.Position]] = [], points: [SafePlot.Position] = []) throws -> PlotFraming {
        try #require(PlotFraming.framing(for: plot(paths, points: points)))
    }

    // MARK: Normalizing

    @Test func longitudesNormalizeToMinus180ExclusiveThrough180() {
        let cases: [(Double, Double)] = [(0, 0), (360, 0), (-360, 0), (180, 180), (-180, 180), (540, 180), (181, -179),
                                         (-181, 179), (179, 179), (-179, -179), (350, -10), (720.5, 0.5), (12.5, 12.5)]
        for (input, expected) in cases {
            #expect(PlotFraming.normalized(input) == expected, "\(input)")
        }
        #expect(PlotFraming.normalized(.nan).isNaN)
        #expect(PlotFraming.normalized(.infinity) == .infinity)
    }

    // MARK: Framing

    @Test func aTrackBetweenMinus179And179IsFramedAcrossTheAntimeridianNotAcrossTheWorld() throws {
        let frame = try framing([[position(-179, 10), position(179, 10)]])
        #expect(frame.west == 179 && frame.east == 181 && frame.width == 2)
        #expect(frame.crossesAntimeridian && frame.displayEast == -179)
        #expect(frame.south == 10 && frame.north == 10)
        #expect(frame.unwrapped(179) == 179 && frame.unwrapped(-179) == 181)
        #expect(frame.place(position(-179, 10)) == position(181, 10))
    }

    @Test func theFrameIsTheSameWhicheverWayTheTrackRuns() throws {
        let eastward = try framing([[position(179, 10), position(-179, 10)]])
        let westward = try framing([[position(-179, 10), position(179, 10)]])
        #expect(eastward == westward)
    }

    @Test func anOrdinaryPlotKeepsItsSmallestToLargestSpan() throws {
        let frame = try framing([[position(12.49, 41.89), position(12.51, 41.91)]], points: [position(12.5, 41.9)])
        #expect(frame.west == 12.49 && frame.east == 12.51)
        #expect(frame.south == 41.89 && frame.north == 41.91)
        #expect(!frame.crossesAntimeridian && frame.displayEast == 12.51)
        // Positions on both sides of the prime meridian are an ordinary span, not a crossing.
        let across = try framing([[position(-10, 0), position(10, 0)]])
        #expect(across.west == -10 && across.east == 10 && !across.crossesAntimeridian)
    }

    @Test func aFrameWiderThanHalfTheWorldKeepsTheOrdinarySpan() throws {
        // Three continents: the narrowest arc is 190 degrees, wider than half the world, so the usual orientation stays.
        let frame = try framing([[position(-170, 10), position(0, 20), position(170, 30)]])
        #expect(frame.west == -170 && frame.east == 170 && !frame.crossesAntimeridian)
    }

    @Test func zeroAnd360AreOneMeridian() throws {
        let sameMeridian = try framing([[position(0, 5), position(360, 6)]])
        #expect(sameMeridian.west == 0 && sameMeridian.east == 0 && sameMeridian.width == 0)
        #expect(sameMeridian.place(position(360, 6)) == position(0, 6))
        // 350 to 10 is a 20 degree hop over the prime meridian written in the 0 to 360 convention.
        let hop = try framing([[position(350, 0), position(10, 0)]])
        #expect(hop.west == -10 && hop.east == 10 && hop.width == 20)
        #expect(hop.unwrapped(350) == -10)
        // A track from 359 to 1 stays a 2 degree arc, whichever convention wrote it.
        #expect(try framing([[position(359, 0), position(1, 0)]]).width == 2)
        // And the date line itself: 180 and -180 are one line, kept on the east side.
        let dateLine = try framing([[position(-180, 0), position(180, 5)]])
        #expect(dateLine.west == 180 && dateLine.east == 180)
    }

    @Test func nothingFiniteMeansNoFrame() {
        #expect(PlotFraming.framing(for: plot()) == nil)
        #expect(PlotFraming.framing(for: plot([[position(.nan, 0), position(0, .infinity)]])) == nil)
        // A non-finite position is left out, the rest still frames.
        #expect((try? framing([[position(.nan, 0), position(5, 1), position(7, 2)]]))?.east == 7)
    }

    // MARK: Cutting lines at the seam

    @Test func aCompactFrameDrawsTheCrossingAsOneShortLine() throws {
        let path = [position(-179, 10), position(179, 20), position(178, 30)]
        let frame = try framing([path])
        let lines = frame.pieces(of: path)
        #expect(lines == [[position(181, 10), position(179, 20), position(178, 30)]])
    }

    @Test func aWideFrameCutsTheCrossingStepAtTheEdgesOnItsTrueCourse() throws {
        // Outlying points keep the frame wide: -175 to 175, with a point on the prime meridian.
        let path = [position(170, 0), position(-170, 40)]
        let frame = try framing([path], points: [position(-175, 20), position(175, 20), position(0, 20)])
        #expect(frame.west == -175 && frame.east == 175)
        let lines = frame.pieces(of: path)
        // The short way is 20 degrees east from 170 to 190: a quarter of the way it reaches the east edge at 175
        // (latitude 10) and three quarters of the way it comes back in at the west edge, 185 (latitude 30).
        try #require(lines.count == 2)
        #expect(lines[0] == [position(170, 0), position(175, 10)])
        #expect(lines[1] == [position(-175, 30), position(-170, 40)])
        // Westward is the same cut, the other way round.
        let back = frame.pieces(of: Array(path.reversed()))
        try #require(back.count == 2)
        #expect(back[0] == [position(-170, 40), position(-175, 30)])
        #expect(back[1] == [position(175, 10), position(170, 0)])
    }

    @Test func noStepOfADrawnLineIsLongerThanHalfTheWorld() throws {
        let longitudes: [Double] = [-180, -179, -170, -90, -1, 0, 1, 90, 170, 179, 180, 181, 270, 359, 360]
        for a in longitudes {
            for b in longitudes {
                let path = [position(a, -30), position(b, 40), position(a, 10)]
                for extra in [[position(0, 0)], [position(-175, 0), position(175, 0)], []] {
                    let frame = try framing([path], points: extra)
                    for line in frame.pieces(of: path) {
                        #expect(!line.isEmpty)
                        for (from, to) in zip(line, line.dropFirst()) {
                            #expect(abs(to.longitude - from.longitude) <= PlotFraming.maximumStep + 1e-9, "\(a) \(b)")
                        }
                        for point in line {
                            #expect(point.longitude >= frame.west - 1e-9 && point.longitude <= frame.east + 1e-9, "\(a) \(b)")
                            #expect(point.latitude >= -30 - 1e-9 && point.latitude <= 40 + 1e-9)
                        }
                    }
                }
            }
        }
    }

    @Test func aPathWithoutACrossingIsOneLineAndASinglePositionIsOneDot() throws {
        let path = [position(12.49, 41.89), position(12.5, 41.9), position(12.51, 41.91)]
        let frame = try framing([path])
        #expect(frame.pieces(of: path) == [path])
        let dot = [position(5, 5)]
        #expect(try framing(points: dot).pieces(of: dot) == [dot])
        #expect(frame.pieces(of: []).isEmpty)
    }

    // MARK: The poles

    @Test func positionsAtThePolesFrameAndProjectToFinitePoints() throws {
        let area = CGRect(x: 24, y: 24, width: 352, height: 252)
        let polar = [position(-180, 90), position(0, 90), position(180, 90), position(-90, -90), position(90, -90)]
        let frame = try framing(points: polar)
        #expect(frame.south == -90 && frame.north == 90)
        let project = PlotCanvas.projection(framing: frame, in: area)
        for point in polar {
            let drawn = project(frame.place(point))
            #expect(drawn.x.isFinite && drawn.y.isFinite)
            #expect(area.insetBy(dx: -0.001, dy: -0.001).contains(drawn), "\(point)")
        }
        // North is up: the pole sits on the top edge of the drawing and the other on the bottom.
        #expect(abs(project(frame.place(position(0, 90))).y - project(frame.place(position(0, -90))).y) > 100)
        #expect(project(frame.place(position(0, 90))).y < project(frame.place(position(0, -90))).y)
    }

    @Test func aTrackAroundThePoleAcrossTheAntimeridianStaysCompact() throws {
        // 20 degrees of longitude near the north pole, written either side of the antimeridian.
        let path = [position(-170, 89), position(170, 89)]
        let frame = try framing([path])
        #expect(frame.west == 170 && frame.east == 190 && frame.south == 89 && frame.north == 89)
        let lines = frame.pieces(of: path)
        #expect(lines == [[position(190, 89), position(170, 89)]])
        let project = PlotCanvas.projection(framing: frame, in: CGRect(x: 0, y: 0, width: 200, height: 100))
        for point in lines[0] {
            let drawn = project(point)
            #expect(drawn.x.isFinite && drawn.y.isFinite)
        }
    }

    @Test func aPolarPlotNeverFeedsInfinityToTheDrawing() throws {
        // All positions at one pole, spread over every longitude: zero height, full width, scale clamped, not infinite.
        let frame = try framing(points: [position(-179, 90), position(0, 90), position(179, 90)])
        let drawn = PlotCanvas.projection(framing: frame, in: CGRect(x: 0, y: 0, width: 200, height: 100))(frame.place(position(179, 90)))
        #expect(drawn.x.isFinite && drawn.y.isFinite)
        // The text keeps the real numbers.
        let text = NativePlotPreviewView.extentText(plot(points: [position(-179, 90), position(179, 90)]), locale: english)
        #expect(text.contains("90.0000") && !text.contains("nan") && !text.contains("inf"))
    }

    // MARK: The text

    @Test func theExtentTextReadsWestToEastAcrossTheAntimeridian() {
        let text = NativePlotPreviewView.extentText(plot([[position(-179, 10), position(179, 12)]]), locale: english)
        #expect(text == PreviewStrings.format(.dataPlotExtent, arguments: ["179.0000", "-179.0000", "10.0000", "12.0000"], locale: english))
        let ordinary = NativePlotPreviewView.extentText(plot([[position(10, 1), position(12, 2)]]), locale: english)
        #expect(ordinary == PreviewStrings.format(.dataPlotExtent, arguments: ["10.0000", "12.0000", "1.0000", "2.0000"], locale: english))
        #expect(NativePlotPreviewView.extentText(plot(), locale: english).isEmpty)
    }
}
