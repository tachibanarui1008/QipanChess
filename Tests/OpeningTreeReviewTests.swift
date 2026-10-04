import XCTest
@testable import Analysis
import Engine
import GameCore

final class OpeningTreeReviewTests: XCTestCase {
    @MainActor func testFillAndRecomputeCoverSharedHiddenBranchesAndPersist() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "分枝计算")
        let first = try PGN.decode("1. e4 e5 2. Nf3 *")
        let second = try PGN.decode("1. e4 c5 *")
        store.synchronize(record: first, kind: .research, treeID: id)
        store.synchronize(record: second, kind: .research, treeID: id)
        let hidden = OpeningTreeDocument.nodeID(fen: second.initialFEN, moves: second.moves)
        store.update(id) { $0.hidden.insert(hidden); $0.notes[hidden] = "保留备注" }
        let original = store.tree(id)!
        let engine = TreeReviewTestEngine()
        let coordinator = OpeningTreeReviewCoordinator()
        coordinator.start(treeID: id, store: store, recomputeAll: false, engine: engine)
        await finish(coordinator)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.total, 4) // e4 is shared by both sources.
        XCTAssertEqual(coordinator.completed, 4)
        XCTAssertEqual(store.tree(id)?.annotations.count, 4)
        XCTAssertEqual(store.tree(id)?.sources, original.sources)
        XCTAssertEqual(store.tree(id)?.hidden, original.hidden)
        XCTAssertEqual(store.tree(id)?.notes, original.notes)
        let calls = await engine.calls
        coordinator.start(treeID: id, store: store, recomputeAll: false, engine: engine)
        await finish(coordinator)
        XCTAssertEqual(coordinator.total, 0)
        let noNewCalls = await engine.calls
        XCTAssertEqual(noNewCalls, calls)
        await engine.setScore(80)
        coordinator.start(treeID: id, store: store, recomputeAll: true, engine: engine)
        await finish(coordinator)
        XCTAssertEqual(coordinator.completed, 4)
        XCTAssertEqual(store.tree(id)?.annotations[hidden]?.review.after.centipawns, 80)
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertEqual(restored.tree(id)?.annotations, store.tree(id)?.annotations)
    }

    @MainActor func testStoppingSavesCompletedBatchAndEqualDepthCacheRefreshes() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "停止计算")
        let record = try PGN.decode("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *")
        store.synchronize(record: record, kind: .research, treeID: id)
        let engine = TreeReviewTestEngine(delay: 40_000_000)
        let coordinator = OpeningTreeReviewCoordinator()
        coordinator.start(treeID: id, store: store, recomputeAll: false, engine: engine)
        for _ in 0..<300 {
            if coordinator.completed >= 1 { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        coordinator.cancel()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertGreaterThan(store.tree(id)!.annotations.count, 0)
        XCTAssertLessThan(store.tree(id)!.annotations.count, 6)
        let cached = store.cachedReview(for: record, engine: engine.name)!
        let live = GameReviewCoordinator()
        live.updateLive(record: record, cursor: 1, cached: cached, allowAnalysis: false)
        let key = OpeningTreeDocument.nodeID(fen: record.initialFEN, moves: Array(record.moves.prefix(1)))
        var changed = store.tree(id)!.annotations[key]!
        let before = try GamePosition(fen: record.initialFEN)
        var after = before; after.make(record.moves[0])
        await engine.setScore(99)
        changed.review = try await GameReviewCoordinator.review(move: record.moves[0], index: 0,
            position: before, after: after, depth: 14, previous: nil, engine: engine)
        store.update(id) { $0.annotations[key] = changed }
        live.updateLive(record: record, cursor: 1, cached: store.cachedReview(for: record, engine: engine.name), allowAnalysis: false)
        XCTAssertEqual(live.moves.first?.after.centipawns, 99)
    }

    @MainActor func testDesktopAndIPadShareExistingGrades() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "跨设备标注")
        let record = try PGN.decode("1. e4 e5 *")
        store.synchronize(record: record, kind: .research, treeID: id)
        let desktop = TreeReviewTestEngine(name: "Stockfish 18")
        let coordinator = OpeningTreeReviewCoordinator()
        coordinator.start(treeID: id, store: store, recomputeAll: false, engine: desktop)
        await finish(coordinator)
        let iPad = TreeReviewTestEngine(name: "Stockfish 18（内嵌）")
        coordinator.start(treeID: id, store: store, recomputeAll: false, engine: iPad)
        await finish(coordinator)
        XCTAssertEqual(coordinator.total, 0)
        let calls = await iPad.calls
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(store.cachedReview(for: record, engine: iPad.name)?.moves.count, 2)
        XCTAssertNil(store.cachedReview(for: record, engine: "Stockfish 17"))
        XCTAssertFalse(ReviewEngineIdentity.matches("Stockfish 17", iPad.name))
    }

    @MainActor private func finish(_ coordinator: OpeningTreeReviewCoordinator) async {
        for _ in 0..<500 {
            if !coordinator.isRunning { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Tree calculation did not finish")
    }
}

private actor TreeReviewTestEngine: ChessEngine {
    nonisolated let name: String
    var calls = 0
    var score = 0
    let delay: UInt64
    init(delay: UInt64 = 0, name: String = "tree-test") { self.delay = delay; self.name = name }
    func start() async throws {}
    func stop() async {}
    func setScore(_ value: Int) { score = value }
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        calls += 1
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        let move = limit.rootMoves.first ?? MoveGenerator.allLegalMoves(for: position.sideToMove, in: position).first!
        return EngineResult(score: .centipawns(score), depth: limit.depth, bestMove: move,
            principalVariation: [move], elapsedMilliseconds: 0, nodes: 1)
    }
}
