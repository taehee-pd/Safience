import XCTest
@testable import PadCore

final class DesktopViewTests: XCTestCase {
    // Points: an iPhone 17 Pro Max's page area upright and on its side.
    private let upright = (width: 440.0, height: 760.0)
    private let sideways = (width: 874.0, height: 330.0)

    func testAssistiveTechnologyUsesNativeBrowsingInsteadOfTheTrackpad() {
        XCTAssertTrue(DesktopView.supportsTrackpad(voiceOver: false, switchControl: false))
        XCTAssertFalse(DesktopView.supportsTrackpad(voiceOver: true, switchControl: false))
        XCTAssertFalse(DesktopView.supportsTrackpad(voiceOver: false, switchControl: true))
        XCTAssertFalse(DesktopView.supportsTrackpad(voiceOver: true, switchControl: true))
    }

    func testZoomResetFitsTheAvailableViewAndKeepsTheCursorVisible() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        view.cover(bottom: 300)
        view.zoom(by: 4, aroundX: 300, y: 200)
        view.resetZoom()
        XCTAssertEqual(view.zoom, DesktopView.fill(viewWidth: upright.width, viewHeight: upright.height - 300), accuracy: 1e-9)
        let point = view.viewPoint(x: view.cursorX, y: view.cursorY)
        XCTAssertTrue((0...view.viewWidth).contains(point.x))
        XCTAssertTrue((0...(view.viewHeight - view.covered)).contains(point.y))
    }

    func testItFillsTheViewOneWayAndPansTheOther() {
        let up = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        XCTAssertEqual(up.zoom, 760.0 / 1032.0, accuracy: 1e-9, "all of the height upright")
        XCTAssertEqual(up.originX, 0, "from the left, where a web app keeps its menus")
        XCTAssertEqual(up.originY, 0)
        XCTAssertLessThan(up.visibleWidth, DesktopView.width)
        let side = DesktopView(viewWidth: sideways.width, viewHeight: sideways.height)
        XCTAssertEqual(side.zoom, 874.0 / 1376.0, accuracy: 1e-9, "all of the width on its side")
        XCTAssertEqual(DesktopView.fill(viewWidth: 2000, viewHeight: 2000), 1, "never past the page's own size")
    }

    func testTheViewFollowsTheCursorToTheEdge() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        for _ in 0..<40 { view.moveCursor(dx: 30, dy: 0, speed: 100) }
        XCTAssertEqual(view.cursorX, DesktopView.width, "the cursor stops at the desktop's edge")
        XCTAssertEqual(view.originX + view.visibleWidth, DesktopView.width, accuracy: 1e-9, "and the view with it")
        let (x, _) = view.viewPoint(x: view.cursorX, y: view.cursorY)
        XCTAssertLessThanOrEqual(x, view.viewWidth)
        for _ in 0..<40 { view.moveCursor(dx: -30, dy: 0, speed: 100) }
        XCTAssertEqual(view.cursorX, 0)
        XCTAssertEqual(view.originX, 0)
    }

    func testTheCursorStaysAMarginFromTheEdgeWhileTheViewCanMove() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        view.moveCursor(dx: 300, dy: 0, speed: 100)
        let (x, _) = view.viewPoint(x: view.cursorX, y: view.cursorY)
        XCTAssertEqual(x, view.viewWidth - DesktopView.margin, accuracy: 1e-6)
    }

    func testFastIsFartherAndSlowIsOneToOne() {
        XCTAssertEqual(DesktopView.gain(speed: 50), 1)
        XCTAssertGreaterThan(DesktopView.gain(speed: 900), DesktopView.gain(speed: 400))
        XCTAssertLessThanOrEqual(DesktopView.gain(speed: 1e6), 2.2)
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        let before = view.cursorY
        view.moveCursor(dx: 0, dy: 10, speed: 50)
        XCTAssertEqual((view.cursorY - before) * view.zoom, 10, accuracy: 1e-9, "as far on screen as the finger went")
    }

    func testPastTheDesktopsTopOrBottomTheRestOfAMoveIsAPush() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        // A move that stays on the desktop pushes nothing.
        XCTAssertEqual(view.moveCursor(dx: 0, dy: 20, speed: 50), 0)
        XCTAssertEqual(view.cursorEnd, 0)
        // To the bottom and 40 view points on: what the cursor couldn't go, in the desktop's points.
        let room = (DesktopView.height - view.cursorY) * view.zoom
        XCTAssertEqual(view.moveCursor(dx: 0, dy: room + 40, speed: 50), 40 / view.zoom, accuracy: 1e-9)
        XCTAssertEqual(view.cursorY, DesktopView.height)
        XCTAssertEqual(view.cursorEnd, 1)
        // Against the bottom, all of a move down is push, and a fast one pushes further.
        XCTAssertEqual(view.moveCursor(dx: 0, dy: 10, speed: 50), 10 / view.zoom, accuracy: 1e-9)
        XCTAssertEqual(view.moveCursor(dx: 0, dy: 10, speed: 900), 10 * view.travel(speed: 900), accuracy: 1e-9)
        XCTAssertGreaterThan(view.travel(speed: 900), view.travel(speed: 50))
        // Along the bottom pushes nothing, and neither does the way back up.
        XCTAssertEqual(view.moveCursor(dx: 50, dy: 0, speed: 50), 0)
        XCTAssertEqual(view.moveCursor(dx: 0, dy: -5, speed: 50), 0)
        XCTAssertEqual(view.cursorEnd, 0)
        // The top, the other way.
        XCTAssertLessThan(view.moveCursor(dx: 0, dy: -5000, speed: 50), 0)
        XCTAssertEqual(view.cursorY, 0)
        XCTAssertEqual(view.cursorEnd, -1)
        XCTAssertEqual(view.moveCursor(dx: 0, dy: -12, speed: 50), -12 / view.zoom, accuracy: 1e-9)
    }

    func testOnlyTheDesktopsEndIsPushedNotTheViews() {
        // On its side about half the desktop's height shows: the view follows the cursor down first.
        var view = DesktopView(viewWidth: sideways.width, viewHeight: sideways.height)
        XCTAssertEqual(view.moveCursor(dx: 0, dy: 200, speed: 50), 0)
        XCTAssertGreaterThan(view.originY, 0)
        XCTAssertEqual(view.cursorEnd, 0)
        XCTAssertGreaterThan(view.moveCursor(dx: 0, dy: 2000, speed: 50), 0)
        XCTAssertEqual(view.originY + view.visibleHeight, DesktopView.height, accuracy: 1e-9)
    }

    func testAPinchKeepsThePointUnderTheFingersAndBringsTheCursorAlong() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        let under = view.desktopPoint(x: 300, y: 200)
        view.zoom(by: 2, aroundX: 300, y: 200)
        let after = view.desktopPoint(x: 300, y: 200)
        XCTAssertEqual(after.x, under.x, accuracy: 1e-6)
        XCTAssertEqual(after.y, under.y, accuracy: 1e-6)
        let (x, y) = view.viewPoint(x: view.cursorX, y: view.cursorY)
        XCTAssertTrue((0...view.viewWidth).contains(x) && (0...view.viewHeight).contains(y), "the cursor is in view")
        view.zoom(by: 0.01, aroundX: 0, y: 0)
        XCTAssertEqual(view.zoom, view.fitZoom, accuracy: 1e-9, "no smaller than all of it")
        XCTAssertLessThan(view.originY, 0, "which sits in the middle")
        view.zoom(by: 100, aroundX: 0, y: 0)
        XCTAssertEqual(view.zoom, DesktopView.maxZoom)
    }

    func testTheKeyboardCoversTheBottomAndTheCursorStaysAboveIt() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        for _ in 0..<20 { view.moveCursor(dx: 0, dy: 40, speed: 100) }
        view.cover(bottom: 336)
        let (_, y) = view.viewPoint(x: view.cursorX, y: view.cursorY)
        XCTAssertLessThanOrEqual(y, view.viewHeight - 336, "above the keyboard")
        view.cover(bottom: 0)
        XCTAssertEqual(view.covered, 0)
    }

    func testTheMinimapShowsWhatShows() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        let shown = view.shown
        XCTAssertEqual(shown.x, 0)
        XCTAssertEqual(shown.height, 1, accuracy: 1e-9, "all of the height")
        XCTAssertEqual(shown.width, view.visibleWidth / DesktopView.width, accuracy: 1e-9)
        view.center(onX: DesktopView.width, y: DesktopView.height / 2)
        XCTAssertEqual(view.shown.x + view.shown.width, 1, accuracy: 1e-9, "a tap at the right edge shows the right edge")
    }

    func testTurningThePhoneKeepsAZoomThatFits() {
        var view = DesktopView(viewWidth: upright.width, viewHeight: upright.height)
        view.resize(viewWidth: sideways.width, viewHeight: sideways.height)
        XCTAssertGreaterThanOrEqual(view.zoom, view.fitZoom)
        XCTAssertGreaterThanOrEqual(view.originX, 0)
        XCTAssertLessThanOrEqual(view.originX + view.visibleWidth, DesktopView.width + 1e-9)
    }

    func testTapsSoonAndNearAreDoubleAndTripleClicks() {
        var clicks = ClickCount()
        XCTAssertEqual(clicks.click(at: 0, x: 100, y: 100), 1)
        XCTAssertEqual(clicks.click(at: 0.3, x: 105, y: 102), 2)
        XCTAssertEqual(clicks.click(at: 0.6, x: 104, y: 101), 3)
        XCTAssertEqual(clicks.click(at: 0.8, x: 104, y: 101), 1, "a fourth starts again")
        XCTAssertEqual(clicks.click(at: 2, x: 104, y: 101), 1, "too late")
        XCTAssertEqual(clicks.click(at: 2.2, x: 200, y: 101), 1, "too far")
    }

    func testCursorSpeedScalesTheWholeCurveWithinItsRange() {
        var slow = DesktopView(viewWidth: 400, viewHeight: 800)
        var usual = slow
        var fast = slow
        let start = usual.cursorX
        slow.moveCursor(dx: 10, dy: 0, speed: 100, scale: 0.5)
        usual.moveCursor(dx: 10, dy: 0, speed: 100)
        fast.moveCursor(dx: 10, dy: 0, speed: 100, scale: 9)
        XCTAssertEqual(slow.cursorX - start, (usual.cursorX - start) / 2, accuracy: 0.001)
        XCTAssertEqual(fast.cursorX - start, (usual.cursorX - start) * DesktopView.cursorSpeeds.upperBound, accuracy: 0.001,
                       "past the fastest is the fastest")
    }
}
