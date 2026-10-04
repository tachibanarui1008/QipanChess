import XCTest
import GameCore
import Analysis
import Engine

final class ChessFeaturesTests: XCTestCase {
    func testFENRoundTripAndValidation() throws {
        let start = GamePosition.starting
        XCTAssertEqual(try GamePosition(fen: start.fen), start)
        XCTAssertThrowsError(try GamePosition(fen: "8/8/8/8/8/8/8/8 w - - 0 1"))
        XCTAssertThrowsError(try GamePosition(fen: "8/8/8/8/8/8/4k3/4K3 w - - 0 1"))
        let imported = try GamePosition(fen: "4k3/8/8/8/8/8/8/4K3 b - - 0 37")
        XCTAssertEqual(imported.plyCount, 73)
        XCTAssertEqual(imported.fen, "4k3/8/8/8/8/8/8/4K3 b - - 0 37")
    }
    func testPGNVariationsCommentsAndRoundTrip() throws {
        let pgn = """
        [White "学习者"]
        [Black "Stockfish"]
        [Result "*"]

        1.e4 {争夺中心} e5 2.Nf3 (2.Bc4 Nf6 (2...Bc5) 3.d3) Nc6 3.Bb5 a6 *
        """
        let record = try PGN.decode(pgn)
        XCTAssertEqual(record.moves.count, 6)
        XCTAssertEqual(record.branches.count, 2)
        XCTAssertEqual(record.comments[1], "争夺中心")
        let again = try PGN.decode(PGN.encode(record))
        XCTAssertEqual(again.moves, record.moves)
        XCTAssertEqual(again.branches.count, record.branches.count)
        XCTAssertEqual(Set(again.branches.map { $0.moves.map(\.uci).joined(separator: " ") }),
                       Set(record.branches.map { $0.moves.map(\.uci).joined(separator: " ") }))
        XCTAssertThrowsError(try PGN.decode("1. e4 e5 2. Bh6 *"))
        XCTAssertThrowsError(try PGN.decode("1. e4 (1. d4 *"))
        XCTAssertThrowsError(try PGN.decode("1. e4 1-0 1. d4 *"))
    }
    func testSpecialMovesNotation() throws {
        let pgn = try PGN.decode("1. e4 a6 2. e5 d5 3. exd6 exd6 4. Nf3 Nf6 5. Bc4 Be7 6. O-O O-O *")
        XCTAssertEqual(pgn.moves.count, 12)
        XCTAssertEqual(try PGN.decode(PGN.encode(pgn)).positions().last, try pgn.positions().last)
        let promotion = try GamePosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(MoveGenerator.legalMoves(from: Square("a7")!, in: promotion).count, 4)
        let knight = try SAN.move("a8=N", in: promotion)
        XCTAssertEqual(knight.promotion, .knight)
        let fenPGN = "[FEN \"\(promotion.fen)\"]\n[SetUp \"1\"]\n1. a8=N *"
        XCTAssertEqual(try PGN.decode(PGN.encode(PGN.decode(fenPGN))).moves.first?.promotion, .knight)
    }
    func testSANDisambiguation() throws {
        let position = try GamePosition(fen: "4k3/8/8/8/8/8/8/1N2KN2 w - - 0 1")
        XCTAssertEqual(try SAN.move("Nbd2", in: position).from, Square("b1"))
        XCTAssertEqual(try SAN.move("Nfd2", in: position).from, Square("f1"))
        XCTAssertThrowsError(try SAN.move("Nd2", in: position))
    }
    @MainActor func testReplayBranchesAndPersistence() throws {
        let session = GameSession()
        let record = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *")
        try session.load(record)
        session.seek(to: 2)
        XCTAssertEqual(session.record.moves.count, 4)
        XCTAssertTrue(session.make(try SAN.move("Bc4", in: session.position)))
        XCTAssertEqual(session.record.branches.first?.moves, record.moves)
        let again = try PGN.decode(PGN.encode(session.record))
        XCTAssertEqual(again.branches.first?.moves, record.moves)
        try session.selectBranch(session.record.branches[0].id)
        XCTAssertEqual(session.record.moves, record.moves)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder)
        XCTAssertTrue(library.save(session.record))
        let restored = GameLibrary(directory: folder)
        XCTAssertEqual(restored.games.first, session.record)
    }
    @MainActor func testDrawClaimsAndAutomaticDraws() throws {
        let session = GameSession()
        for _ in 0..<2 {
            for token in ["Nf3", "Nf6", "Ng1", "Ng8"] { XCTAssertTrue(session.make(try SAN.move(token, in: session.position))) }
        }
        XCTAssertTrue(session.canClaimDraw)
        XCTAssertNil(session.outcome)
        session.claimDraw()
        XCTAssertEqual(session.record.tags["Result"], "1/2-1/2")
        XCTAssertNotNil(session.outcome)
        let bare = try GamePosition(fen: "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertTrue(bare.hasInsufficientMaterial)
    }
    func testReviewThresholdsAndScorePerspective() {
        XCTAssertEqual(ReviewQuality.classify(loss: 0, isBest: true), .best)
        XCTAssertEqual(ReviewQuality.classify(loss: 0.01, isBest: false), .excellent)
        XCTAssertEqual(ReviewQuality.classify(loss: 3, isBest: false), .blunder)
        XCTAssertEqual(ReviewScore(.centipawns(-150), inverted: true).value, 1.5)
        XCTAssertEqual(ReviewScore(.mate(3), inverted: true).mate, -3)
    }
}

private actor ReviewFixtureEngine: ChessEngine {
    nonisolated let name = "Review fixture"
    let delay: Bool
    private(set) var calls: [(GamePosition, AnalysisLimit)] = []
    init(delay: Bool = false) { self.delay = delay }
    func start() async throws {}
    func stop() async {}
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        calls.append((position, limit))
        if delay { try await Task.sleep(for: .milliseconds(120)) }
        let legal = MoveGenerator.allLegalMoves(for: position.sideToMove, in: position)
        let best = limit.rootMoves.first ?? (try? SAN.move("e4", in: position)) ?? legal.first
        let score: EngineScore = limit.rootMoves.isEmpty ? .centipawns(80) : .centipawns(-220)
        return EngineResult(score: score, depth: limit.depth, bestMove: best, principalVariation: best.map { [$0] } ?? [],
                            elapsedMilliseconds: 1, nodes: 1,
                            variations: best.map { [EngineVariation(rank: 1, score: score, depth: limit.depth, principalVariation: [$0], wdl: EngineWDL(wins: limit.rootMoves.isEmpty ? 700 : 100, draws: 200, losses: limit.rootMoves.isEmpty ? 100 : 700))] } ?? [])
    }
}

extension ChessFeaturesTests {
    @MainActor func testWholeGameReviewPerspectiveAndCache() async throws {
        let coordinator = GameReviewCoordinator()
        let game = try PGN.decode("1. d4 *")
        coordinator.start(record: game, preset: .quick, engine: ReviewFixtureEngine())
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        let report = try XCTUnwrap(coordinator.report)
        XCTAssertEqual(report.moves.count, 1)
        XCTAssertEqual(report.moves[0].after.centipawns, -220)
        XCTAssertEqual(report.moves[0].quality, .blunder)
        XCTAssertEqual(report.moves[0].bestSAN, "e4")
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder)
        library.saveReview(report, for: game.id)
        XCTAssertEqual(library.review(for: game), report)
        var changed = game; changed.moves = []
        XCTAssertNil(library.review(for: changed))
    }
    @MainActor func testCancelledReviewDoesNotPublishStaleResults() async throws {
        let coordinator = GameReviewCoordinator()
        coordinator.start(record: try PGN.decode("1. d4 *"), preset: .quick, engine: ReviewFixtureEngine(delay: true))
        coordinator.cancel()
        coordinator.start(record: try PGN.decode("1. e4 *"), preset: .quick, engine: ReviewFixtureEngine())
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(coordinator.report?.moves.first?.san, "e4")
        XCTAssertEqual(coordinator.report?.moves.first?.quality, .book)
    }
    func testExportPreservesContinuationOfShorterMainLine() throws {
        var game = try PGN.decode("1. e4 *")
        game.branches = [GameBranch(name: "完整原局", moves: try PGN.decode("1. e4 e5 2. Nf3 *").moves)]
        let restored = try PGN.decode(PGN.encode(game))
        XCTAssertEqual(restored.branches.first?.moves, game.branches.first?.moves)
    }
    func testInvalidDecodedSquareIsRejected() {
        XCTAssertThrowsError(try JSONDecoder().decode(Square.self, from: Data("{\"file\":99,\"rank\":0}".utf8)))
    }
    @MainActor func testStockfishWholeGameSmoke() async throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Engines/stockfish")
        guard FileManager.default.isExecutableFile(atPath: path.path) else { throw XCTSkip("Stockfish not prepared") }
        let coordinator = GameReviewCoordinator()
        coordinator.start(record: try PGN.decode("1. f3 e5 2. g4 Qh4# 0-1"), preset: .quick,
                          engine: StockfishProcessEngine(executableURL: path))
        let deadline = Date().addingTimeInterval(45)
        while coordinator.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(50)) }
        if coordinator.isRunning { coordinator.cancel(); XCTFail("Stockfish review timed out"); return }
        let report = try XCTUnwrap(coordinator.report, coordinator.message ?? "No report")
        XCTAssertEqual(report.moves.count, 4)
        XCTAssertEqual(report.moves[2].quality, .blunder)
        XCTAssertEqual(report.moves.last?.after.mate, 1)
    }
}


extension ChessFeaturesTests {
    func testTenMoveClassificationsAndPriority() {
        XCTAssertEqual(ReviewQuality.allCases.count, 10)
        XCTAssertEqual(Set(ReviewQuality.allCases.map(\.colorHex)).count, 9)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0, isBest: true, brilliant: true), .brilliant)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0, isBest: true, great: true), .great)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0, isBest: true, isBook: true), .book)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0.01, isBest: false), .excellent)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0.03, isBest: false), .good)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0.07, isBest: false), .inaccuracy)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 0.15, isBest: false), .mistake)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 2, isBest: false, missedWin: true), .miss)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 2, isBest: false, missedWin: true, allowsMate: true), .blunder)
        XCTAssertEqual(ReviewMoveClassifier.classify(loss: 3, isBest: false, isBook: true), .blunder)
    }
    func testBadgeAssetsMatchAllCategories() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for category in ReviewQuality.allCases {
            let asset = root.appendingPathComponent("QipanChessApp/App/Assets.xcassets/MoveBadge-\(category.rawValue).imageset")
            let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: asset.appendingPathComponent("Contents.json"))) as! [String: Any]
            let images = catalog["images"] as! [[String: String]]
            XCTAssertEqual(images.count, 3)
            for image in images {
                XCTAssertTrue(FileManager.default.fileExists(atPath: asset.appendingPathComponent(image["filename"]!).path))
            }
        }
    }
}

extension ChessFeaturesTests {
    func testExpectedPointsIncludesDrawsAndThresholdEdges() {
        XCTAssertEqual(EngineWDL(wins: 0, draws: 1000, losses: 0)?.expectedPoints, 0.5)
        XCTAssertEqual(EngineWDL(wins: 200, draws: 600, losses: 200)?.expectedPoints, 0.5)
        XCTAssertNil(EngineWDL(wins: -1, draws: 1000, losses: 1))
        XCTAssertEqual(ReviewQuality.classify(loss: 0.02, isBest: false), .good)
        XCTAssertEqual(ReviewQuality.classify(loss: 0.05, isBest: false), .inaccuracy)
        XCTAssertEqual(ReviewQuality.classify(loss: 0.10, isBest: false), .mistake)
        XCTAssertEqual(ReviewQuality.classify(loss: 0.20, isBest: false), .blunder)
    }
    @MainActor func testRootComparisonUsesSamePositionDepthAndHistory() async throws {
        let engine = ReviewFixtureEngine()
        let coordinator = GameReviewCoordinator()
        let record = try PGN.decode("1. d4 *")
        coordinator.start(record: record, preset: .standard, engine: engine)
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(10)) }
        let calls = await engine.calls
        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].0, calls[1].0)
        XCTAssertEqual(calls[0].1.depth, calls[1].1.depth)
        XCTAssertEqual(calls[1].1.rootMoves, record.moves)
        XCTAssertEqual(calls[1].1.history?.initialFEN, record.initialFEN)
        XCTAssertEqual(coordinator.moves.first?.expectedBefore, 0.8)
        XCTAssertEqual(coordinator.moves.first?.expectedAfter, 0.2)
        XCTAssertEqual(coordinator.moves.first?.loss ?? 0, 0.6, accuracy: 0.0001)
    }
    @MainActor func testLiveReviewQueuesBothSidesAndRetainsPrefix() async throws {
        let coordinator = GameReviewCoordinator()
        let engine = ReviewFixtureEngine(delay: true)
        var record = try PGN.decode("1. d4 *")
        coordinator.updateLive(record: record, cursor: 1, engine: engine)
        let longer = try PGN.decode("1. d4 d5 2. c4 *")
        record.moves = longer.moves; record.cursor = 3
        coordinator.updateLive(record: record, cursor: 3, engine: engine)
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(coordinator.moves.map(\.index), [1, 2, 3])
        let first = coordinator.moves.first
        coordinator.updateLive(record: record, cursor: 1, engine: engine)
        XCTAssertFalse(coordinator.isRunning)
        XCTAssertEqual(coordinator.moves.first, first)
        record.moves = Array(record.moves.prefix(1)); record.cursor = 1
        coordinator.updateLive(record: record, cursor: 1, engine: engine)
        XCTAssertEqual(coordinator.moves.map(\.index), [1])
        var position = try record.positions().last!
        let reply = try SAN.move("Nf6", in: position); position.make(reply)
        record.moves.append(reply); record.cursor = 2
        coordinator.updateLive(record: record, cursor: 2, engine: engine)
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(coordinator.moves.last?.san, "Nf6")
        XCTAssertEqual(coordinator.moves.first, first)
    }
    func testOrdinaryExchangeIsNotBrilliantSacrifice() throws {
        let position = try GamePosition(fen: "3qk3/8/8/8/8/8/8/3QK3 w - - 0 1")
        var current = position
        let line = try ["Qxd8+", "Kxd8", "Kd2"].map { san in
            let move = try SAN.move(san, in: current); current.make(move); return move
        }
        XCTAssertFalse(GameReviewCoordinator.isSacrifice(position: position, line: line))
    }
    @MainActor func testStockfishRestrictedMoveReturnsWDLAndBlackPerspective() async throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Engines/stockfish")
        guard FileManager.default.isExecutableFile(atPath: path.path) else { throw XCTSkip("Stockfish not prepared") }
        let engine = StockfishProcessEngine(executableURL: path)
        let game = try PGN.decode("1. f3 e5 2. g4 *")
        let position = try game.positions().last!
        let move = try SAN.move("Qh4#", in: position)
        let result = try await engine.analyze(position: position, limit: AnalysisLimit(depth: 10, rootMoves: [move],
            history: EnginePositionHistory(initialFEN: game.initialFEN, moves: game.moves)))
        await engine.stop()
        XCTAssertEqual(result.bestMove, move)
        XCTAssertEqual(result.score, .mate(1))
        XCTAssertEqual(result.variations.first?.wdl?.expectedPoints, 1)
    }
}

extension ChessFeaturesTests {
    func testShortRealMaterialInvestmentIsDetected() throws {
        let position = try GamePosition(fen: "n3k3/1b6/8/8/8/8/8/R3K3 w - - 0 1")
        var current = position
        let line = try ["Rxa8+", "Bxa8", "Kd2"].map { san in
            let move = try SAN.move(san, in: current); current.make(move); return move
        }
        XCTAssertTrue(GameReviewCoordinator.isSacrifice(position: position, line: line))
        XCTAssertFalse(GameReviewCoordinator.isSacrifice(position: position, line: Array(line.prefix(2))))
    }
    @MainActor func testNewMoveInterruptsWholeReviewAndReceivesLiveGrade() async throws {
        let coordinator = GameReviewCoordinator()
        let engine = ReviewFixtureEngine(delay: true)
        var record = try PGN.decode("1. d4 *")
        coordinator.updateLive(record: record, cursor: 1, engine: engine)
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        coordinator.start(record: record, preset: .deep, engine: ReviewFixtureEngine(delay: true))
        record.moves = try PGN.decode("1. d4 d5 *").moves; record.cursor = 2
        coordinator.updateLive(record: record, cursor: 2, engine: ReviewFixtureEngine())
        while coordinator.isRunning { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(coordinator.moves.last?.index, 2)
        XCTAssertEqual(coordinator.report?.analysisKey, record.analysisKey)
    }
}
