import Foundation

/// The iPhone's desktop view: a page laid out at an iPad Pro 13-inch's size,
/// seen through the phone's screen as through a window that follows a
/// cursor, moved by the finger as on a trackpad (Jump Desktop's trackpad
/// mode). For using a web app from the phone now and then, not all the time.
///
/// Two kinds of points: the desktop's, from its top left, and the view's,
/// from the top left of where the page shows on the phone.
public struct DesktopView: Equatable, Sendable {
    /// The size the page is laid out at: the iPad Pro 13-inch's, so a site
    /// looks as it does in the iPad app.
    public static let width = 1376.0
    public static let height = 1032.0
    /// How near the view's edge the cursor comes before the view moves after it.
    public static let margin = 28.0
    /// View points per desktop point, at most: twice the page's size, for a small target.
    public static let maxZoom = 2.0

    public private(set) var viewWidth: Double
    public private(set) var viewHeight: Double
    /// View points per desktop point.
    public private(set) var zoom: Double
    /// The desktop point at the view's top left. Negative on an axis where
    /// the whole desktop fits, so it sits in the middle.
    public private(set) var originX = 0.0
    public private(set) var originY = 0.0
    public private(set) var cursorX: Double
    public private(set) var cursorY: Double
    /// How much of the view's bottom something covers: the keyboard.
    public private(set) var covered = 0.0

    /// At the zoom that fills the view (`fill`), the desktop's top left in
    /// view, where a web app keeps its menus, the cursor in the middle of
    /// what shows.
    public init(viewWidth: Double, viewHeight: Double) {
        self.viewWidth = max(viewWidth, 1)
        self.viewHeight = max(viewHeight, 1)
        zoom = Self.fill(viewWidth: self.viewWidth, viewHeight: self.viewHeight)
        cursorX = 0
        cursorY = 0
        clampOrigin()
        cursorX = min(Self.width, max(0, originX + visibleWidth / 2))
        cursorY = min(Self.height, max(0, originY + visibleHeight / 2))
    }

    /// The zoom at which the desktop covers the view: all of its height on a
    /// phone upright, all of its width on its side, the other way to pan;
    /// never past the page's own size.
    public static func fill(viewWidth: Double, viewHeight: Double) -> Double {
        min(1, max(viewWidth / width, viewHeight / height))
    }

    /// The zoom at which all of the desktop shows.
    public var fitZoom: Double {
        min(viewWidth / Self.width, max(viewHeight - covered, 1) / Self.height)
    }

    /// How much of the desktop shows, in desktop points.
    public var visibleWidth: Double { viewWidth / zoom }
    public var visibleHeight: Double { max(viewHeight - covered, 1) / zoom }

    // MARK: The cursor

    /// The finger moved `dx`, `dy` view points at `speed` view points a
    /// second: the cursor moves as far on screen, further the faster, and
    /// the view follows it when it nears the edge.
    public mutating func moveCursor(dx: Double, dy: Double, speed: Double) {
        let gain = Self.gain(speed: speed)
        cursorX = min(Self.width, max(0, cursorX + dx * gain / zoom))
        cursorY = min(Self.height, max(0, cursorY + dy * gain / zoom))
        follow()
    }

    /// One to one when slow, for aiming; up to a little over twice when
    /// fast, to cross the desktop in a swipe or two, as a trackpad's pointer does.
    public static func gain(speed: Double) -> Double {
        1 + min(max(speed - 150, 0) / 1000, 1.2)
    }

    // MARK: The view

    /// The view's new size: the phone turned, or the bars changed.
    public mutating func resize(viewWidth: Double, viewHeight: Double) {
        self.viewWidth = max(viewWidth, 1)
        self.viewHeight = max(viewHeight, 1)
        zoom = min(Self.maxZoom, max(fitZoom, zoom))
        clampOrigin()
        follow()
    }

    /// The keyboard came, went, or changed: `bottom` view points of the view
    /// are under it, and the cursor stays above it.
    public mutating func cover(bottom: Double) {
        covered = min(max(bottom, 0), viewHeight - 1)
        zoom = min(Self.maxZoom, max(fitZoom, zoom))
        clampOrigin()
        follow()
    }

    /// A pinch by `factor` around a view point: the desktop under it stays
    /// under it. The view isn't pulled back to the cursor; the cursor comes
    /// into view instead, so the pinch goes where the fingers took it.
    public mutating func zoom(by factor: Double, aroundX viewX: Double, y viewY: Double) {
        let x = originX + viewX / zoom
        let y = originY + viewY / zoom
        zoom = min(Self.maxZoom, max(fitZoom, zoom * factor))
        originX = x - viewX / zoom
        originY = y - viewY / zoom
        clampOrigin()
        keepCursorInView()
    }

    /// Shows the desktop around a desktop point (a tap on the minimap), the
    /// cursor brought along.
    public mutating func center(onX x: Double, y: Double) {
        originX = x - visibleWidth / 2
        originY = y - visibleHeight / 2
        clampOrigin()
        keepCursorInView()
    }

    // MARK: Between the two kinds of points

    public func viewPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        ((x - originX) * zoom, (y - originY) * zoom)
    }

    public func desktopPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        (originX + x / zoom, originY + y / zoom)
    }

    /// What shows of the desktop, as fractions of it, for the minimap.
    public var shown: (x: Double, y: Double, width: Double, height: Double) {
        let x = max(0, originX), y = max(0, originY)
        return (x / Self.width, y / Self.height,
                (min(Self.width, originX + visibleWidth) - x) / Self.width,
                (min(Self.height, originY + visibleHeight) - y) / Self.height)
    }

    // MARK: Keeping it all in place

    /// The view moves after the cursor when it comes within `margin` of an edge.
    private mutating func follow() {
        let marginX = min(Self.margin / zoom, visibleWidth / 3)
        let marginY = min(Self.margin / zoom, visibleHeight / 3)
        if cursorX < originX + marginX { originX = cursorX - marginX }
        if cursorX > originX + visibleWidth - marginX { originX = cursorX - visibleWidth + marginX }
        if cursorY < originY + marginY { originY = cursorY - marginY }
        if cursorY > originY + visibleHeight - marginY { originY = cursorY - visibleHeight + marginY }
        clampOrigin()
    }

    private mutating func keepCursorInView() {
        let marginX = min(Self.margin / zoom, visibleWidth / 3)
        let marginY = min(Self.margin / zoom, visibleHeight / 3)
        let left = max(0, originX + marginX), right = min(Self.width, originX + visibleWidth - marginX)
        let top = max(0, originY + marginY), bottom = min(Self.height, originY + visibleHeight - marginY)
        if left <= right { cursorX = min(right, max(left, cursorX)) }
        if top <= bottom { cursorY = min(bottom, max(top, cursorY)) }
    }

    /// Never past the desktop's edges; centred on an axis where all of it shows.
    private mutating func clampOrigin() {
        originX = Self.clamp(originX, visible: visibleWidth, extent: Self.width)
        originY = Self.clamp(originY, visible: visibleHeight, extent: Self.height)
    }

    private static func clamp(_ origin: Double, visible: Double, extent: Double) -> Double {
        visible >= extent ? -(visible - extent) / 2 : min(extent - visible, max(0, origin))
    }
}

/// Which click a tap is: the first, or the second or third of a double or
/// triple click, from how soon and how near it came after the one before.
public struct ClickCount: Equatable, Sendable {
    public static let interval = 0.5
    /// In view points: a finger lands less exactly than a pointer clicks.
    public static let distance = 12.0

    private var last: (time: Double, x: Double, y: Double, count: Int)?

    public init() {}

    public mutating func click(at time: Double, x: Double, y: Double) -> Int {
        var count = 1
        if let last, time - last.time <= Self.interval, hypot(x - last.x, y - last.y) <= Self.distance {
            count = last.count % 3 + 1
        }
        last = (time, x, y, count)
        return count
    }

    public static func == (a: ClickCount, b: ClickCount) -> Bool {
        a.last?.time == b.last?.time && a.last?.count == b.last?.count
    }
}
