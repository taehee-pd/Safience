import PadCore
import SwiftUI
import UIKit

/// What the phone bar's swipe is doing: nothing; drawing the tabs up out of
/// it; sliding the page to the tab beside; or, let go, that slide settling
/// by itself, which a new sideways swipe can catch. One at a time: the tabs
/// don't come up over a page between two tabs.
enum BarGesture { case idle, tabs, sliding, settling }

/// The phone bar's swipe for a Browser: what it is doing, and the page
/// sliding to the tab beside while it goes sideways.
@MainActor
final class PageSlide {
    var gesture = BarGesture.idle

    private let model: WindowModel
    /// Where the pages are, moved with the finger, and the stack it is in,
    /// where the tab beside comes in next to it.
    private let stage: UIView
    private let stack: UIStackView
    /// Shows the tab that came in, in the window's space.
    private let show: (UUID) -> Void

    /// The page coming in beside the one on screen while the bar is dragged
    /// sideways, and the side it is on.
    private var slideCard: SlideCard?
    private var slideSide: CGFloat = 0
    /// The tab and space on screen when that page came in: the slide goes
    /// through only from them, as the new tab past the last has no id of its own.
    private var slideFrom: (tab: UUID?, space: UUID)?
    /// Where a caught slide's page stood when a finger took it again: the drag goes on from there.
    private var slideBase: CGFloat = 0
    /// The settling slide's end, for a finger that catches it (catchSlide),
    /// and its count, so the spring's own ending is ignored once caught.
    private var settling: (target: CGFloat, goes: TabRecord?, count: Int) = (0, nil, 0)
    /// Between two pages side by side, as between Safari's.
    private static let slideGap: CGFloat = 16

    init(model: WindowModel, stage: UIView, stack: UIStackView, show: @escaping (UUID) -> Void) {
        self.model = model
        self.stage = stage
        self.stack = stack
        self.show = show
    }

    /// A sideways swipe beginning: a slide still settling is caught where
    /// it is, and the finger goes on with it. Not where there is no tab on
    /// either side to go to.
    func begin() -> Bool {
        let caught = gesture == .settling ? catchSlide() : 0
        guard caught != 0 || neighbour(on: 1) != nil || neighbour(on: -1) != nil else { return false }
        slideBase = caught
        gesture = .sliding
        return true
    }

    /// The sideways swipe ended without letting go: the page back where it was.
    func cancel() {
        endSlide(velocity: 0, cancelled: true)
    }

    /// A sideways drag on the bar goes to the tab beside, as in Safari: the
    /// page and the address go with the finger, the tab beside coming in
    /// next to them, and letting go carries on at the finger's speed to
    /// whichever of the two it was heading for. At the first and the last
    /// tab the drag gives less and less, and springs back.
    func drag(_ swipe: UIPanGestureRecognizer, in view: UIView) {
        switch swipe.state {
        case .changed:
            slide(to: slideBase + swipe.translation(in: view).x)
        case .ended:
            endSlide(velocity: swipe.velocity(in: view).x)
        case .cancelled, .failed:
            endSlide(velocity: 0, cancelled: true)
        default:
            break
        }
    }

    /// What a sideways drag brings in on that side (1 the right, -1 the
    /// left): the tab beside in its row; or past the last ordinary tab, as
    /// in Safari, a new one (newTabSlide), unless the tab on screen is an
    /// empty new one already. Past the last pinned tab, nothing.
    private func neighbour(on side: CGFloat) -> TabRecord? {
        if let tab = tabBeside(side) { return tab }
        guard side > 0, let found = currentRow(), !found.row[found.index].isPinned,
              found.index == found.row.count - 1, found.row[found.index].url != nil
        else { return nil }
        return newTabSlide
    }

    /// The new tab a drag past the last tab brings in: drawn as an empty tab
    /// is, its card and its address row, and made only once the drag goes through.
    private let newTabSlide = TabRecord(url: nil, title: "New Tab")

    /// The tab next in the row on that side (1 the right, -1 the left), if
    /// this window can show it: no going round, as there is none in the row.
    private func tabBeside(_ side: CGFloat) -> TabRecord? {
        guard let found = currentRow(), found.row.indices.contains(found.index + (side > 0 ? 1 : -1)) else { return nil }
        let tab = found.row[found.index + (side > 0 ? 1 : -1)]
        return Session.shared.browser(showing: tab.id) == nil ? tab : nil
    }

    /// The row the tab on screen is in, and its place there. On the phone
    /// the pinned tabs are a row of their own, the dock's, and the others
    /// another, the grid's: a sideways drag goes along the one the tab is in
    /// and never from one into the other, though the pinned come first in
    /// the space's order, which an iPhone never shows. Without the pinned
    /// tabs this device hides.
    private func currentRow() -> (row: [TabRecord], index: Int)? {
        let session = Session.shared
        guard let current = model.tabID, let space = session.workspace.space(model.spaceID),
              let tab = space.tabs.first(where: { $0.id == current })
        else { return nil }
        // The tab on screen stays in it though this device hides it, as
        // Workspace.neighbour keeps it: there is still a way on from it.
        let row = space.tabs.filter { $0.isPinned == tab.isPinned && ($0.id == current || session.preferences.shows($0)) }
        guard let index = row.firstIndex(where: { $0.id == current }) else { return nil }
        return (row, index)
    }

    private func slide(to distance: CGFloat) {
        guard distance != 0 else { return }
        // A drag to the left brings in the tab on the right.
        let side: CGFloat = distance < 0 ? 1 : -1
        if side != slideSide { meetNeighbour(on: side) }
        // With nothing on that side the page gives less the further it is pulled.
        let width = stage.bounds.width
        let moved = slideCard != nil ? distance : Throw.rubberband(distance, range: width)
        place(slide: moved)
        model.slide.offset = moved
    }

    /// The tab beside on `side` (1 the right, -1 the left) as a card at the
    /// stage's edge, and its address row for the bar; nothing where no tab is.
    private func meetNeighbour(on side: CGFloat) {
        slideSide = side
        slideFrom = (model.tabID, model.spaceID)
        slideCard?.removeFromSuperview()
        slideCard = nil
        guard let tab = neighbour(on: side) else {
            model.slide.coming = nil
            return
        }
        let held = Session.shared.pages.slidePicture(for: tab.id)
        let card = SlideCard(tab: tab, picture: held)
        // From the stage's centre: its frame has the drag's offset in it
        // while it is moved, and the card is moved by the same again.
        card.bounds = stage.bounds
        card.center = CGPoint(x: stage.center.x + side * (stage.bounds.width + Self.slideGap), y: stage.center.y)
        stack.insertSubview(card, aboveSubview: stage)
        slideCard = card
        // A frozen tab's picture may be on disk only: it joins the card when it has been read.
        if held == nil, !Session.shared.pages.isLive(tab.id) {
            Session.shared.pages.readPicture(for: tab.id) { [weak card] picture in
                if let picture { card?.show(picture) }
            }
        }
        let titled = !AddressVisibility.shows(mode: Session.shared.preferences.address, url: tab.url,
                                              passwordField: false, editing: false, failed: false)
        model.slide.coming = SlideNeighbour(tab: tab, side: side, titled: titled)
    }

    private func place(slide distance: CGFloat) {
        let moved = CGAffineTransform(translationX: distance, y: 0)
        stage.transform = moved
        slideCard?.transform = moved
    }

    private func endSlide(velocity: CGFloat, cancelled: Bool = false) {
        let from = stage.transform.tx
        let width = stage.bounds.width + Self.slideGap
        // Where the drag would come to rest by itself, as a scroll's flick does.
        let coming = cancelled ? nil : slideCard.map(\.tab)
        let goes = coming != nil && Throw.slideGoes(offset: from, velocity: velocity, side: slideSide, width: width)
        let target = goes ? -slideSide * width : 0
        guard from != target else {
            finishSlide(to: nil)
            return
        }
        gesture = .settling
        let count = settling.count + 1
        settling = (target, goes ? coming : nil, count)
        // The spring starts at the finger's speed, so letting go has no seam;
        // the address row's too, so it keeps up with the page.
        let start = min(max(velocity / (target - from), 0), 30)
        UIView.animate(springDuration: 0.4, bounce: 0, initialSpringVelocity: start,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.place(slide: target)
        } completion: { _ in
            // Not when a finger caught it on the way (catchSlide), which ended it itself.
            guard self.settling.count == count, self.gesture == .settling else { return }
            self.finishSlide(to: goes ? coming : nil)
        }
        withAnimation(.interpolatingSpring(duration: 0.4, bounce: 0, initialVelocity: start)) { model.slide.offset = target }
    }

    /// A sideways swipe taking a slide that is still settling: it ends where
    /// it was going at once (on the tab beside, if it was going there), and
    /// the page is put back where it showed, for the new drag to go on from.
    /// Returns that place, measured from the page now on screen.
    private func catchSlide() -> CGFloat {
        let shown = stage.layer.presentation()?.affineTransform().tx ?? stage.transform.tx
        let (target, goes, _) = settling
        settling.count += 1
        let card = slideCard
        stage.layer.removeAllAnimations()
        card?.layer.removeAllAnimations()
        finishSlide(to: goes)
        // Its picture would fade where the page was at rest, not where it is now.
        card?.removeFromSuperview()
        // finishSlide put the stage at rest: where it showed, relative to it,
        // with the page beside it back at once, as it was showing, not on
        // the finger's next move.
        let base = shown - target
        if base != 0 { meetNeighbour(on: base < 0 ? 1 : -1) }
        place(slide: base)
        model.slide.offset = base
        return base
    }

    private func finishSlide(to tab: TabRecord?) {
        let card = slideCard
        // Only from the tab it began on, and if it is still the tab beside:
        // not when that tab was closed, or another tab or space gone to,
        // while the slide settled.
        let from = slideFrom.map { $0.tab == model.tabID && $0.space == model.spaceID } ?? false
        let tab = tab.flatMap { from && neighbour(on: slideSide)?.id == $0.id ? $0 : nil }
        slideCard = nil
        slideSide = 0
        slideFrom = nil
        gesture = .idle
        if let tab {
            if tab.id == newTabSlide.id {
                // Past the last tab: a new one at the end of the row, on its start page.
                if let made = Session.shared.change({ $0.openTab(nil, in: model.spaceID, after: model.tabID) }) {
                    show(made)
                }
            } else {
                show(tab.id)
            }
        }
        // The stage is back where it was, now with the tab that came in, and
        // the bar with it, in one step: nothing to see move.
        stage.transform = .identity
        card?.transform = .identity
        card?.frame = stage.frame
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            model.slide.offset = 0
            model.slide.coming = nil
        }
        guard let card else { return }
        guard tab != nil else {
            card.removeFromSuperview()
            return
        }
        // Its picture stays a moment over the page it stood for, then fades,
        // so the page's first frame never shows as a flash.
        UIView.animate(withDuration: 0.18, delay: 0.06, options: [.allowUserInteraction]) {
            card.alpha = 0
        } completion: { _ in
            card.removeFromSuperview()
        }
    }
}

/// The tab beside, as it comes in while the phone bar is dragged sideways:
/// the picture it was last seen as, or its site's icon on the page's ground
/// where there is none yet.
private final class SlideCard: UIView {
    let tab: TabRecord

    init(tab: TabRecord, picture: UIImage?) {
        self.tab = tab
        super.init(frame: .zero)
        backgroundColor = Palette.UI.ground
        clipsToBounds = true
        isUserInteractionEnabled = false
        if let picture {
            show(picture)
        } else if tab.url == nil {
            // An empty tab, or the new one past the last: a plus, as New Tab's button has.
            let plus = UIImageView(image: UIImage(systemName: "plus",
                                                  withConfiguration: UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)))
            plus.tintColor = Palette.UI.muted
            plus.sizeToFit()
            plus.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            addSubview(plus)
            self.icon = plus
        } else {
            let icon = SiteIconUIView()
            icon.size = 44
            icon.url = tab.url
            icon.bounds = CGRect(x: 0, y: 0, width: 44, height: 44)
            icon.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin, .flexibleTopMargin, .flexibleBottomMargin]
            addSubview(icon)
            self.icon = icon
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    private var icon: UIView?

    /// The tab's picture, over the icon that stood in for it.
    /// The picture, read from disk while the finger drags: it fades in over
    /// the site's icon rather than replacing it in one frame mid-gesture.
    func show(_ picture: UIImage) {
        let image = UIImageView(image: picture)
        image.contentMode = .scaleAspectFill
        image.frame = bounds
        image.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        image.alpha = 0
        addSubview(image)
        let icon = icon
        self.icon = nil
        UIView.animate(withDuration: 0.15, delay: 0, options: [.allowUserInteraction]) {
            image.alpha = 1
        } completion: { _ in
            icon?.removeFromSuperview()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A little above the middle, where the page's own content would start to show.
        icon?.center = CGPoint(x: bounds.midX, y: bounds.height * 0.4)
    }
}
