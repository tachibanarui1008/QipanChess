import Analysis
import GameCore
import SwiftUI

struct OpeningTreeCanvas: View {
    let tree: OpeningTreeDocument
    let selectedMoves: [Move]
    let selectedFEN: String
    var full = false
    let onSelect: (OpeningTreeNode) -> Void
    var onZoom: ((Double) -> Void)? = nil
    var allNodes: [OpeningTreeNode]? = nil
    var fullLayout: OpeningTreeLayout? = nil
    @State private var zoom: CGFloat = 1
    @State private var focusRequest = 0
    @GestureState private var gestureZoom: CGFloat = 1
    private func context(in all: [OpeningTreeNode]) -> (fen: String, moves: [Move]) {
        let matched = all.filter { $0.initialFEN == selectedFEN && Array(selectedMoves.prefix($0.moves.count)) == $0.moves }.max { $0.moves.count < $1.moves.count }
        if let matched { return (matched.initialFEN, matched.moves) }
        return (all.first(where: { $0.parentID == nil })?.initialFEN ?? selectedFEN, [])
    }
    private func visibleNodes(_ all: [OpeningTreeNode], route: (fen: String, moves: [Move])) -> [OpeningTreeNode] {
        guard !full else { return all }
        let lower = max(0, route.moves.count - 3), upper = route.moves.count + 3
        let prefix = Array(route.moves.prefix(lower))
        let subset = all.filter { $0.initialFEN == route.fen && $0.moves.count >= lower && $0.moves.count <= upper && Array($0.moves.prefix(lower)) == prefix }
        let ids = Set(subset.map(\.id))
        return subset.map { node in var n = node; if n.parentID.map({ !ids.contains($0) }) == true { n.parentID = nil }; n.children = n.children.filter(ids.contains); return n }
    }
    private func focus(_ proxy: ScrollViewProxy, layout: OpeningTreeLayout, id: String, viewport: CGSize) {
        guard let point = layout.points[id] else { return }
        scroll(proxy, layout: layout, center: CGPoint(x: point.x * Double(zoom), y: point.y * Double(zoom)), viewport: viewport)
    }
    private func scroll(_ proxy: ScrollViewProxy, layout: OpeningTreeLayout, center: CGPoint, viewport: CGSize) {
        // Scroll the scaled canvas itself; transformed child frames are unreliable targets.
        let width = layout.width * Double(zoom), height = layout.height * Double(zoom)
        let viewHeight = max(1, Double(viewport.height) - 66)
        func anchor(_ coordinate: Double, extent: Double, visible: Double) -> CGFloat {
            guard extent > visible else { return 0.5 }
            return CGFloat(min(1, max(0, (coordinate - visible / 2) / (extent - visible))))
        }
        proxy.scrollTo("tree-canvas", anchor: UnitPoint(x: anchor(Double(center.x), extent: width, visible: Double(viewport.width)),
                                                       y: anchor(Double(center.y), extent: height, visible: viewHeight)))
    }
    private func nodeButton(_ node: OpeningTreeNode, selected: Bool) -> some View {
        let foreground = node.side == .black ? Color.white : Color(red: 0.22, green: 0.20, blue: 0.17)
        let background = node.side == .black ? AppTheme.treeBlack : AppTheme.treeWhite
        return Button { onSelect(node) } label: {
            HStack(spacing: 5) {
                Text(node.san).font(.system(.caption, design: .rounded, weight: .semibold)).lineLimit(1)
                if node.move != nil {
                    if let annotation = node.annotation { MoveQualityBadge(classification: annotation.review.classification, size: 18) }
                    else { Circle().stroke(.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2])).frame(width: 16, height: 16).help("待分析") }
                }
            }.padding(.horizontal, 9).padding(.vertical, 7)
                .foregroundStyle(foreground).background(background)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(selected ? AppTheme.accent : Color.primary.opacity(0.08), lineWidth: selected ? 2 : 1))
                .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
        }.buttonStyle(.plain)
            .accessibilityLabel((node.side?.displayName ?? "") + node.san + "，" + (node.annotation?.review.classification.title ?? "待分析"))
    }
    var body: some View {
        let all = allNodes ?? tree.nodes()
        let activeRoute = context(in: all)
        let focusedID = OpeningTreeDocument.nodeID(fen: activeRoute.fen, moves: activeRoute.moves)
        let items = visibleNodes(all, route: activeRoute)
        let layout = full ? (fullLayout ?? OpeningTreeLayout(nodes: items)) : OpeningTreeLayout(nodes: items)
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Label(full ? tree.name : "当前分枝", systemImage: "tree.fill").font(.callout.bold()).lineLimit(1)
                    Spacer()
                    Button { zoom = max(0.025, zoom / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }.help("缩小")
                    Button { zoom = min(2.5, zoom * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }.help("放大")
                    Menu {
                        Button("适应全树") { zoom = max(0.025, min(1, min(geometry.size.width / layout.width, (geometry.size.height - 66) / layout.height))); focusRequest += 1 }
                        Button("聚焦当前路线") { zoom = 1; focusRequest += 1 }
                    } label: { Image(systemName: "scope") }
                }.buttonStyle(.plain).padding(12)
                HStack(spacing: 12) {
                    HStack(spacing: 4) { Circle().fill(AppTheme.treeWhite).overlay(Circle().stroke(.secondary.opacity(0.3))).frame(width: 10, height: 10); Text("白方走法") }
                    HStack(spacing: 4) { Circle().fill(AppTheme.treeBlack).frame(width: 10, height: 10); Text("黑方走法") }
                    Spacer()
                }.font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.bottom, 8)
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "leaf").font(.system(size: 30)).foregroundStyle(AppTheme.accent)
                        Text("在棋盘上走出第一步，树就开始生长。").font(.callout).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    #if os(macOS)
                    OpeningTreeNativeCanvas(nodes: items, layout: layout, focusedID: focusedID,
                        activeIDs: Set(items.filter { $0.initialFEN == activeRoute.fen && Array(activeRoute.moves.prefix($0.moves.count)) == $0.moves }.map(\.id)),
                        zoom: zoom, focusRequest: focusRequest, onSelect: onSelect,
                        onMagnify: { zoom = min(2.5, max(0.025, zoom * $0)) })
                        .onAppear { if let saved = tree.savedZoom { zoom = max(0.025, min(2.5, saved)) } }
                    #else
                    ScrollViewReader { proxy in
                        ScrollView([.horizontal, .vertical]) {
                            ZStack(alignment: .topLeading) {
                                Canvas { context, _ in
                                    for node in items {
                                        guard let parent = node.parentID, let a = layout.points[parent], let b = layout.points[node.id] else { continue }
                                        var path = Path(); path.move(to: CGPoint(x: a.x, y: a.y))
                                        let mid = (a.y + b.y) / 2
                                        path.addCurve(to: CGPoint(x: b.x, y: b.y), control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
                                        let active = node.initialFEN == activeRoute.fen && Array(activeRoute.moves.prefix(node.moves.count)) == node.moves
                                        let color = active ? Color(red: 0.70, green: 0.43, blue: 0.19) : Color(red: 0.53, green: 0.57, blue: 0.43).opacity(0.62)
                                        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: active ? 3.5 : min(6, 1.4 + log2(Double(node.count + 1))), lineCap: .round, dash: node.count == 0 ? [4, 5] : []))
                                    }
                                }.frame(width: layout.width, height: layout.height)
                                ForEach(items) { node in
                                    if let point = layout.points[node.id] {
                                        nodeButton(node, selected: node.id == focusedID).frame(width: 112, height: 42).position(x: point.x, y: point.y)

                                    }
                                }
                            }.frame(width: layout.width, height: layout.height)
                                .scaleEffect(zoom * gestureZoom, anchor: .topLeading)
                                .frame(width: layout.width * zoom * gestureZoom, height: layout.height * zoom * gestureZoom, alignment: .topLeading)
                                .id("tree-canvas")
                        }
                        .defaultScrollAnchor(.bottom)
                        .task {
                            if let saved = tree.savedZoom { zoom = max(0.025, min(2.5, saved)) }
                            try? await Task.sleep(for: .milliseconds(100))
                            focus(proxy, layout: layout, id: focusedID, viewport: geometry.size)
                        }
                        .onChange(of: focusedID) { _, value in focus(proxy, layout: layout, id: value, viewport: geometry.size) }
                        .onChange(of: focusRequest) { _, _ in focus(proxy, layout: layout, id: focusedID, viewport: geometry.size) }
                        .simultaneousGesture(MagnifyGesture().updating($gestureZoom) { value, state, _ in state = value.magnification }.onEnded { value in zoom = min(2.5, max(0.025, zoom * value.magnification)) })

                    }
                    #endif
                }
            }
        }
        .task(id: zoom) {
            // Persist after zooming settles instead of writing the whole document for every gesture event.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            onZoom?(Double(zoom))
        }
        .background {
            LinearGradient(colors: [Color(red: 0.79, green: 0.74, blue: 0.60).opacity(0.13), AppTheme.panelBackground], startPoint: .bottom, endPoint: .top)
        }.clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.primary.opacity(0.06)))
    }
}
