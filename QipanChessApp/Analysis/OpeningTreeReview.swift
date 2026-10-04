import Combine
import Engine
import Foundation
import GameCore

/// Reviews each distinct tree edge once, preserving routes and personal metadata.
@MainActor
public final class OpeningTreeReviewCoordinator: ObservableObject {
    @Published public private(set) var isRunning = false
    @Published public private(set) var completed = 0
    @Published public private(set) var total = 0
    @Published public private(set) var message: String?
    @Published public private(set) var revision = 0
    private var task: Task<Void, Never>?
    private var generation = UUID()

    public init() {}

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        isRunning = false
        message = "已停止，已完成的标注已保存。"
    }

    public func start(treeID: UUID, store: OpeningTreeStore, recomputeAll: Bool,
                      depth: Int = 14, engine: (any ChessEngine)? = PlatformEngineFactory.makeDefaultEngine()) {
        cancel()
        guard let document = store.tree(treeID) else { message = "请先选择开局树。"; return }
        guard let engine else { message = "分析引擎不可用。"; return }
        let token = UUID()
        generation = token
        completed = 0; total = 0; isRunning = true; message = "正在整理待计算的走法…"
        task = Task { [weak self] in
            // Large imported trees must not block the UI while enumerating nodes.
            let nodes = await Task.detached { document.nodes(includeHidden: true).sorted {
                $0.moves.count == $1.moves.count ? $0.id < $1.id : $0.moves.count < $1.moves.count
            } }.value
            guard let self, self.generation == token, !Task.isCancelled else { await engine.stop(); return }
            let jobs = nodes.filter { node in
                guard node.move != nil else { return false }
                guard !recomputeAll else { return true }
                return node.annotation == nil || node.annotation.map { !ReviewEngineIdentity.matches($0.engine, engine.name) } == true
            }
            self.total = jobs.count
            var grades = document.annotations
            var batch: [String: TreeAnnotation] = [:]
            @MainActor func flush() {
                guard !batch.isEmpty, store.tree(treeID) != nil else { batch = [:]; return }
                let known = Set(store.nodes(for: treeID, includeHidden: true).map(\.id))
                store.update(treeID) { current in
                    for (key, value) in batch where known.contains(key) { current.annotations[key] = value }
                }
                batch = [:]
                self.revision += 1
            }
            do {
                for node in jobs {
                    try Task.checkCancellation()
                    guard self.generation == token, store.tree(treeID) != nil else { break }
                    var before = try GamePosition(fen: node.initialFEN)
                    for move in node.moves.dropLast() { before.make(move) }
                    guard let move = node.move else { continue }
                    var after = before; after.make(move)
                    let item = try await GameReviewCoordinator.review(move: move, index: node.moves.count - 1,
                        position: before, after: after, depth: max(depth, node.annotation?.review.depth ?? depth),
                        previous: node.parentID.flatMap { grades[$0]?.review }, engine: engine,
                        history: EnginePositionHistory(initialFEN: node.initialFEN, moves: Array(node.moves.dropLast())))
                    try Task.checkCancellation()
                    guard self.generation == token else { break }
                    let annotation = TreeAnnotation(review: item, version: GameReviewReport.currentVersion, engine: engine.name)
                    grades[node.id] = annotation; batch[node.id] = annotation
                    self.completed += 1
                    self.message = "已计算 \(self.completed) / \(self.total) 步"
                    if batch.count >= 8 { flush() }
                }
                flush()
                if self.generation == token {
                    self.isRunning = false
                    self.message = jobs.isEmpty ? "所有走法已有标注，无需补算。" : "计算完成，标注已保存。"
                }
            } catch {
                // Persist finished edges even when stopped halfway through a branch.
                flush()
                if self.generation == token {
                    self.isRunning = false
                    self.message = error is CancellationError ? "已停止，已完成的标注已保存。" : "计算失败：\(error.localizedDescription)"
                }
            }
            await engine.stop()
        }
    }
}
