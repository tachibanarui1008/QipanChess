import XCTest
@testable import Analysis
import Engine
import GameCore

final class AnalysisResponsivenessTests: XCTestCase {
    @MainActor func testRapidPositionsOnlySearchLatestAndDuplicateRequestsCoalesce() async throws {
        let engine = CountingCandidateEngine()
        let coordinator = AnalysisCoordinator(engine: engine)
        coordinator.refreshSelectedStrategy(for: .starting, strategy: .balanced, depth: 14)
        var next = GamePosition.starting
        next.make(Move(uci: "e2e4")!)
        coordinator.refreshSelectedStrategy(for: next, strategy: .balanced, depth: 14)
        coordinator.refreshSelectedStrategy(for: next, strategy: .balanced, depth: 14)
        for _ in 0..<100 {
            if coordinator.snapshot.state == .ready { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let requests = await engine.positions
        XCTAssertEqual(requests, [next.fen])
        XCTAssertEqual(coordinator.snapshot.state, .ready)
    }

    @MainActor func testWarmTreeRemainsCorrectAfterRouteAndVisibilityChanges() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "缓存回归")
        let first = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *")
        let second = try PGN.decode("1. e4 e5 2. Nf3 Nf6 *")
        store.synchronize(record: first, kind: .game, treeID: id)
        _ = store.nodes(for: id); _ = store.nodes(for: id, includeHidden: true)
        store.synchronize(record: second, kind: .research, treeID: id)
        XCTAssertEqual(store.nodes(for: id), store.tree(id)!.nodes())
        let branch = OpeningTreeDocument.nodeID(fen: first.initialFEN, moves: first.moves)
        store.update(id) { $0.hidden.insert(branch) }
        XCTAssertEqual(store.nodes(for: id), store.tree(id)!.nodes())
        XCTAssertEqual(store.nodes(for: id, includeHidden: true), store.tree(id)!.nodes(includeHidden: true))
        store.update(id) { $0.hidden.remove(branch); $0.maxPlies = 2 }
        XCTAssertEqual(store.nodes(for: id), store.tree(id)!.nodes())
        store.update(id) { $0.maxPlies = 40 }
        XCTAssertEqual(store.nodes(for: id), store.tree(id)!.nodes())
    }

    func testTimelineFollowsSelectedSide() {
        let point = AdvantagePoint(ply: 4, advantage: .side(.white, magnitude: 2.5))
        XCTAssertEqual(point.magnitude(from: .white), 2.5)
        XCTAssertEqual(point.magnitude(from: .black), -2.5)
        let mate = AdvantagePoint(ply: 5, advantage: .mate(.black, moves: 3))
        XCTAssertEqual(mate.magnitude(from: .black), 8)
        XCTAssertEqual(mate.magnitude(from: .white), -8)
    }

    @MainActor func testManualOnlyReviewDoesNotSearchUntilRequestedAndIncludesFutureMoves() async throws {
        let engine = CountingCandidateEngine()
        let review = GameReviewCoordinator()
        var record = try PGN.decode("1. e4 e5 2. Nf3 *")
        record.cursor = 1
        review.updateLive(record: record, cursor: 1, engine: engine, allowAnalysis: false)
        try await Task.sleep(for: .milliseconds(50))
        let automatic = await engine.positions
        XCTAssertTrue(automatic.isEmpty)
        XCTAssertFalse(review.isRunning)
        review.start(record: record, preset: .deep, engine: engine)
        // Browsing during a manual review must not cancel the explicitly requested job.
        review.updateLive(record: record, cursor: 2, engine: engine, allowAnalysis: false)
        for _ in 0..<200 {
            if !review.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(review.report?.moves.count, 3)
        XCTAssertEqual(review.report?.analysisKey, record.analysisKey)
        XCTAssertEqual(review.report?.depth, 18)
        let completed = await engine.positions.count
        record.moves.append(Move(uci: "b8c6")!); record.cursor = 4
        review.updateLive(record: record, cursor: 4, engine: engine, allowAnalysis: false)
        try await Task.sleep(for: .milliseconds(50))
        let afterEdit = await engine.positions.count
        XCTAssertEqual(afterEdit, completed)
        XCTAssertFalse(review.isRunning)
    }

    @MainActor func testLiveReviewUpdatesMissingSavedStepsAndBranchChangesWithoutRegradingCache() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let treeID = store.create(name: "落子评价回归")
        let engine = CountingCandidateEngine()
        let coordinator = GameReviewCoordinator()
        let first = try PGN.decode("1. e4 *")
        coordinator.updateLive(record: first, cursor: 1, engine: engine)
        for _ in 0..<200 {
            if !coordinator.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let firstReport = try XCTUnwrap(coordinator.report)
        store.synchronize(record: first, kind: .research, report: firstReport, treeID: treeID)
        var next = first
        next.moves.append(Move(uci: "e7e5")!); next.cursor = 2
        store.synchronize(record: next, kind: .research, treeID: treeID)
        XCTAssertTrue(store.nodes(for: treeID).contains { $0.moves == next.moves && $0.annotation == nil })
        let cached = try XCTUnwrap(store.cachedReview(for: next, engine: engine.name))
        XCTAssertEqual(cached.moves.map(\.index), [1])
        let before = await engine.positions.count
        coordinator.updateLive(record: next, cursor: 2, engine: engine, cached: cached)
        for _ in 0..<200 {
            if !coordinator.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(coordinator.moves.first { $0.index == 2 }?.move, next.moves[1])
        XCTAssertEqual(coordinator.moves.first { $0.index == 1 }, firstReport.moves.first)
        let after = await engine.positions.count
        XCTAssertGreaterThan(after, before)
        coordinator.updateLive(record: next, cursor: 2, engine: engine, cached: cached)
        try await Task.sleep(for: .milliseconds(50))
        let duplicate = await engine.positions.count
        XCTAssertEqual(duplicate, after)
        next.moves[1] = Move(uci: "c7c5")!
        coordinator.updateLive(record: next, cursor: 2, engine: engine)
        XCTAssertNil(coordinator.moves.first { $0.index == 2 })
        for _ in 0..<200 {
            if !coordinator.isRunning { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(coordinator.moves.first { $0.index == 2 }?.move.uci, "c7c5")
        XCTAssertEqual(coordinator.report?.analysisKey, next.analysisKey)
    }

    #if os(macOS)
    func testCancelledUCISearchStopsAndNextSearchReadsItsOwnResult() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        // The first search deliberately never finishes until it receives stop.
        let script = """
        #!/bin/sh
        count=0
        while IFS= read -r line; do
          case "$line" in
            uci) echo uciok ;;
            isready) echo readyok ;;
            go*) count=$((count+1)); echo 'info depth 14 score cp 42 pv e2e4'; if [ "$count" -gt 1 ]; then echo 'bestmove e2e4'; fi ;;
            stop) echo 'bestmove d2d4' ;;
            quit) exit 0 ;;
          esac
        done
        """
        try script.write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
        let engine = StockfishProcessEngine(executableURL: file)
        try await engine.start()
        let stopped = expectation(description: "cancelled UCI search drains promptly")
        let first = Task {
            do { _ = try await engine.analyze(position: .starting, limit: AnalysisLimit(depth: 14)); XCTFail("Cancelled search must not publish") }
            catch { XCTAssertTrue(error is CancellationError) }
            stopped.fulfill()
        }
        try await Task.sleep(for: .milliseconds(100))
        first.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        // Always release the process even if cancellation regresses.
        let finished = expectation(description: "next request succeeds")
        let second = Task {
            do {
                let result = try await engine.analyze(position: .starting, limit: AnalysisLimit(depth: 14))
                XCTAssertEqual(result.bestMove?.uci, "e2e4")
            } catch { XCTFail("\(error)") }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2)
        second.cancel()
        await engine.stop()
        await first.value; await second.value
    }
    #endif
}

private actor CountingCandidateEngine: ChessEngine {
    nonisolated let name = "counting"
    var positions: [String] = []
    func start() async throws {}
    func stop() async {}
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        positions.append(position.fen)
        try await Task.sleep(for: .milliseconds(30))
        let move = MoveGenerator.allLegalMoves(for: position.sideToMove, in: position).first!
        return EngineResult(score: .centipawns(0), depth: limit.depth, bestMove: move,
                            principalVariation: [move], elapsedMilliseconds: 30, nodes: 1)
    }
}
