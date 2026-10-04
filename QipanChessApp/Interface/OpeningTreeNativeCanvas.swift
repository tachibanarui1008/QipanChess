#if os(macOS)
import AppKit
import SwiftUI
import Analysis

struct OpeningTreeNativeCanvas: NSViewRepresentable {
    let nodes: [OpeningTreeNode]
    let layout: OpeningTreeLayout
    let focusedID: String
    let activeIDs: Set<String>
    let zoom: CGFloat
    let focusRequest: Int
    let onSelect: (OpeningTreeNode) -> Void
    let onMagnify: (CGFloat) -> Void
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = TreeScrollView()
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true; scroll.drawsBackground = false
        scroll.documentView = TreeDrawingView()
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? TreeDrawingView else { return }
        let center = view.logicalCenter()
        let focus = view.focusedID != focusedID || view.focusRequest != focusRequest || view.nodes.isEmpty
        view.nodes = nodes; view.layout = layout; view.activeIDs = activeIDs
        view.focusedID = focusedID; view.focusRequest = focusRequest; view.onSelect = onSelect; view.onMagnify = onMagnify
        let changedZoom = view.zoom != zoom
        view.zoom = zoom; view.resize()
        if focus { view.focus() } else if changedZoom { view.center(on: center) }
        view.needsDisplay = true
    }
}
final class TreeScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let view = documentView as? TreeDrawingView else { return }
        let first = view.frame.width == 0 || view.frame.height == 0
        view.resize()
        if first || view.pendingFocus { view.focus() }
    }
}
final class TreeDrawingView: NSView {
    override var isFlipped: Bool { true }
    var nodes: [OpeningTreeNode] = []
    var layout = OpeningTreeLayout(nodes: [])
    var focusedID = ""
    var activeIDs: Set<String> = []
    var focusRequest = 0
    var pendingFocus = true
    var zoom: CGFloat = 1
    var onSelect: ((OpeningTreeNode) -> Void)?
    var onMagnify: ((CGFloat) -> Void)?
    override func magnify(with event: NSEvent) { onMagnify?(1 + event.magnification) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    private var dragStart: NSPoint?
    private var scrollStart = NSPoint.zero
    private var dragged = false
    private var badges: [String: NSImage] = [:]
    var offset: NSPoint {
        NSPoint(x: max(0, (frame.width - layout.width * zoom) / 2), y: max(0, (frame.height - layout.height * zoom) / 2))
    }
    func resize() {
        let viewport = enclosingScrollView?.contentView.bounds.size ?? .zero
        let size = NSSize(width: max(viewport.width, layout.width * zoom), height: max(viewport.height, layout.height * zoom))
        if frame.size != size { setFrameSize(size) }
    }
    func logicalCenter() -> NSPoint {
        let visible = enclosingScrollView?.contentView.bounds ?? .zero
        return NSPoint(x: (visible.midX - offset.x) / zoom, y: (visible.midY - offset.y) / zoom)
    }
    func center(on point: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let visible = scroll.contentView.bounds.size
        pan(to: NSPoint(x: point.x * zoom + offset.x - visible.width / 2, y: point.y * zoom + offset.y - visible.height / 2))
    }
    func focus() {
        guard let scroll = enclosingScrollView, scroll.contentView.bounds.width > 20, let point = layout.points[focusedID] else { pendingFocus = true; return }
        pendingFocus = false; center(on: NSPoint(x: point.x, y: point.y))
    }
    func pan(to point: NSPoint) {
        guard let scroll = enclosingScrollView else { return }
        let size = scroll.contentView.bounds.size
        scroll.contentView.scroll(to: NSPoint(x: min(max(0, point.x), max(0, frame.width - size.width)), y: min(max(0, point.y), max(0, frame.height - size.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    override func mouseDown(with event: NSEvent) {
        dragStart = event.locationInWindow
        scrollStart = enclosingScrollView?.contentView.bounds.origin ?? .zero
        dragged = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let dx = event.locationInWindow.x - start.x, dy = event.locationInWindow.y - start.y
        if hypot(dx, dy) > 3 { dragged = true }
        if dragged { pan(to: NSPoint(x: scrollStart.x - dx, y: scrollStart.y + dy)) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        guard !dragged else { return }
        let p = convert(event.locationInWindow, from: nil)
        let point = NSPoint(x: (p.x - offset.x) / zoom, y: (p.y - offset.y) / zoom)
        if let node = nodes.first(where: { node in
            guard let p = layout.points[node.id] else { return false }
            return NSRect(x: p.x - 56, y: p.y - 21, width: 112, height: 42).contains(point)
        }) { onSelect?(node) }
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? { "开局树画布" }
    override func accessibilityChildren() -> [Any]? {
        guard let window else { return [] }
        return nodes.compactMap { node -> TreeAccessibleNode? in
            guard let point = layout.points[node.id] else { return nil }
            let rect = NSRect(x: point.x * zoom + offset.x - 56 * zoom, y: point.y * zoom + offset.y - 21 * zoom, width: 112 * zoom, height: 42 * zoom)
            guard visibleRect.intersects(rect) else { return nil }
            let element = TreeAccessibleNode()
            element.setAccessibilityRole(.button)
            element.setAccessibilityLabel((node.side?.displayName ?? "") + node.san + "，" + (node.annotation?.review.classification.title ?? "待分析"))
            element.setAccessibilityParent(self)
            element.setAccessibilityFrame(window.convertToScreen(convert(rect, to: nil)))
            element.press = { [weak self] in self?.onSelect?(node) }
            return element
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState(); defer { context.restoreGState() }
        context.translateBy(x: offset.x, y: offset.y); context.scaleBy(x: zoom, y: zoom)
        let visible = NSRect(x: (visibleRect.minX - offset.x) / zoom, y: (visibleRect.minY - offset.y) / zoom, width: visibleRect.width / zoom, height: visibleRect.height / zoom).insetBy(dx: -60, dy: -24)
        for node in nodes {
            guard let parent = node.parentID, let a = layout.points[parent], let b = layout.points[node.id] else { continue }
            let bounds = NSRect(x: min(a.x,b.x)-8, y: min(a.y,b.y)-8, width: abs(a.x-b.x)+16, height: abs(a.y-b.y)+16)
            guard visible.intersects(bounds) else { continue }
            let path = NSBezierPath(); path.move(to: NSPoint(x:a.x,y:a.y))
            path.curve(to: NSPoint(x:b.x,y:b.y), controlPoint1: NSPoint(x:a.x,y:(a.y+b.y)/2), controlPoint2: NSPoint(x:b.x,y:(a.y+b.y)/2))
            let active = activeIDs.contains(node.id)
            (active ? NSColor(red:0.70,green:0.43,blue:0.19,alpha:1) : NSColor(red:0.53,green:0.57,blue:0.43,alpha:0.62)).setStroke()
            path.lineWidth = active ? 3.5 : min(6,1.4+log2(Double(node.count+1)))
            if node.count == 0 { path.setLineDash([4,5], count:2, phase:0) }
            path.stroke()
        }
        for node in nodes {
            guard let p = layout.points[node.id], visible.contains(NSPoint(x:p.x,y:p.y)) else { continue }
            let dark = node.side == .black
            let text = node.san
            let attributes: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:12,weight:.semibold),.foregroundColor:dark ? NSColor.white : NSColor(red:0.22,green:0.20,blue:0.17,alpha:1)]
            let string = NSAttributedString(string:text,attributes:attributes)
            let badgeSpace: CGFloat = node.move == nil ? 0 : 23
            let width = min(112,max(58,string.size().width+20+badgeSpace))
            let rect = NSRect(x:p.x-width/2,y:p.y-17,width:width,height:34)
            let shape = NSBezierPath(roundedRect:rect,xRadius:17,yRadius:17)
            (dark ? NSColor(red:0.23,green:0.25,blue:0.27,alpha:1) : NSColor(red:0.97,green:0.94,blue:0.86,alpha:1)).setFill(); shape.fill()
            (node.id == focusedID ? NSColor.systemOrange : NSColor.gray.withAlphaComponent(0.2)).setStroke()
            shape.lineWidth = node.id == focusedID ? 2 : 1; shape.stroke()
            string.draw(at:NSPoint(x:p.x-(string.size().width+badgeSpace)/2,y:p.y-string.size().height/2))
            if node.move != nil {
                let badgeRect = NSRect(x: rect.maxX - 26, y: p.y - 9, width: 18, height: 18)
                if let quality = node.annotation?.review.classification {
                    let name = "MoveBadge-" + quality.rawValue
                    let image = badges[name] ?? NSImage(named: name)
                    if let image { badges[name] = image; image.draw(in: badgeRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
                    else {
                        let value = UInt32(quality.colorHex, radix: 16) ?? 0x81b64c
                        NSColor(red: Double((value >> 16) & 255)/255, green: Double((value >> 8) & 255)/255, blue: Double(value & 255)/255, alpha: 1).setFill()
                        NSBezierPath(ovalIn: badgeRect).fill()
                        let label = NSAttributedString(string: quality.symbol, attributes: [.font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white])
                        label.draw(at: NSPoint(x: badgeRect.midX-label.size().width/2, y: badgeRect.midY-label.size().height/2))
                    }
                } else {
                    NSColor.secondaryLabelColor.setStroke()
                    let path = NSBezierPath(ovalIn: badgeRect.insetBy(dx: 1, dy: 1)); path.setLineDash([2,2], count: 2, phase: 0); path.stroke()
                }
            }
        }
    }
}
final class TreeAccessibleNode: NSAccessibilityElement {
    var press: (() -> Void)?
    override func accessibilityPerformPress() -> Bool { press?(); return true }
}
#endif
