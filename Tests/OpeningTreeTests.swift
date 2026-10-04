import XCTest
@testable import Analysis
import GameCore
import Engine

final class OpeningTreeTests: XCTestCase {
    func temporary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    @MainActor func testPrefixMergeResearchCountsAndRestore() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "我的意大利")
        var a = try PGN.decode("1. e4 e5 2. Nf3 Nc6 3. Bc4 *")
        let b = try PGN.decode("1. e4 e5 2. Nf3 Nf6 *")
        store.bind(id, to: a); store.synchronize(record: a, kind: .game)
        store.synchronize(record: a, kind: .game); store.synchronize(record: b, kind: .game, treeID: id)
        var doc = try XCTUnwrap(store.tree(id))
        let trunk = doc.nodes().first { $0.moves.count == 3 }!
        XCTAssertEqual(trunk.count, 2); XCTAssertEqual(trunk.children.count, 2)
        let nc6 = a.moves[3]; let original = a.moves
        a.moves = Array(a.moves.prefix(3)); a.moves.append(try SAN.move("d6", in: a.positions().last!))
        store.synchronize(record: a, kind: .research)
        doc = try XCTUnwrap(store.tree(id))
        XCTAssertTrue(doc.sources.contains { $0.moves == original && $0.kind == .game })
        XCTAssertTrue(doc.nodes().contains { $0.move == nc6 })
        let hiddenID = OpeningTreeDocument.nodeID(fen: a.initialFEN, moves: Array(original.prefix(4)))
        store.update(id) { $0.hidden.insert(hiddenID); $0.notes[trunk.id] = "先出马"; $0.maxPlies = 4 }
        store.synchronize(record: b, kind: .game, treeID: id)
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertEqual(restored.boundTree(for: a), id)
        XCTAssertEqual(restored.tree(id)?.notes[trunk.id], "先出马")
        XCTAssertFalse(restored.tree(id)!.nodes().contains { $0.id == hiddenID })
        XCTAssertTrue(restored.tree(id)!.nodes(includeHidden: true).contains { $0.id == hiddenID })
        XCTAssertLessThanOrEqual(restored.tree(id)!.nodes().map { $0.moves.count }.max()!, 4)
        restored.update(id) { $0.hidden.remove(hiddenID) }
        XCTAssertTrue(restored.tree(id)!.nodes().contains { $0.id == hiddenID })
    }
    @MainActor func testBrowsingDoesNotChangeCountsAndMainLineOrder() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder); let id = store.create(name: "自由主题")
        var a = try PGN.decode("1. e4 e5 *"), b = try PGN.decode("1. d4 d5 *")
        store.bind(id, to: a); store.synchronize(record: a, kind: .game)
        a.cursor = 0; store.synchronize(record: a, kind: .game)
        b.cursor = 0; store.synchronize(record: b, kind: .research, treeID: id)
        let nodes = store.tree(id)!.nodes(); let root = nodes.first { $0.parentID == nil }!
        XCTAssertEqual(root.count, 1)
        let d4 = nodes.first { $0.san == "d4" }!
        store.update(id) { $0.preferredChildren[root.id] = d4.id }
        XCTAssertEqual(store.tree(id)!.nodes().first { $0.id == root.id }?.children.first, d4.id)
    }
    @MainActor func testTranspositionsRemainDifferentRoutesAndLayoutDoesNotOverlap() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder); let id = store.create(name: "转置")
        let a = try PGN.decode("1. Nf3 Nf6 2. Nc3 Nc6 *"), b = try PGN.decode("1. Nc3 Nc6 2. Nf3 Nf6 *")
        XCTAssertEqual(try a.positions().last!.repetitionKey, try b.positions().last!.repetitionKey)
        store.synchronize(record: a, kind: .game, treeID: id); store.synchronize(record: b, kind: .game, treeID: id)
        let nodes = store.tree(id)!.nodes(); XCTAssertEqual(nodes.filter { $0.moves.count == 4 }.count, 2)
        let layout = OpeningTreeLayout(nodes: nodes)
        let levels = Dictionary(grouping: nodes, by: { $0.moves.count })
        for group in levels.values {
            let xs = group.compactMap { layout.points[$0.id]?.x }.sorted()
            for pair in zip(xs, xs.dropFirst()) { XCTAssertGreaterThanOrEqual(pair.1 - pair.0, 126) }
        }
        for node in nodes { if let parent = node.parentID { XCTAssertGreaterThan(layout.points[parent]!.y, layout.points[node.id]!.y) } }
    }
    func testMultiPGNCommentsVariationsAndPartialFailure() throws {
        let input = """
        [Event "first"]
        1. e4 {not a header: [Event "fake"]} e5 (1...c5) *
        [Event "bad"]
        1. Bh6 *
        [Event "last"]
        1. d4 d5 *
        """
        let collection = try PGN.decodeCollection(input)
        XCTAssertEqual(collection.games.count, 2); XCTAssertEqual(collection.failures.count, 1)
        XCTAssertEqual(collection.games.first?.branches.count, 1)
        XCTAssertEqual(collection.games.last?.tags["Event"], "last")
        XCTAssertEqual(try PGN.decodeCollection("1. e4 *\n1. d4 *").games.count, 2)
    }
    @MainActor func testImportsDeduplicateLinksAndKeepOriginalNotes() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder)
        var record = try PGN.decode("1. e4 e5 *"); record.tags["Link"] = "https://www.chess.com/game/live/1"; record.comments[1] = "保留我自己的备注"
        let first = library.importRecord(record)
        var duplicate = record; duplicate.id = UUID(); duplicate.comments = [:]
        XCTAssertEqual(library.importRecord(duplicate).id, first.id)
        XCTAssertEqual(library.games.count, 1); XCTAssertEqual(library.games.first?.comments[1], record.comments[1])
    }
    func testSerialArchiveCacheAndOfflineFallback() async throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let payload = Data("{\"archives\":[\"https://api.chess.com/pub/player/test-user/games/2026/09\",\"https://evil.example/month\"]}".utf8)
        let mock = ArchiveFixture(data: payload)
        let client = ChessComArchiveClient(directory: folder, transport: mock)
        let first = try await client.archives(for: " Test-User "); XCTAssertEqual(first.count, 1)
        let cached = try await client.archives(for: "test-user"); XCTAssertEqual(cached.count, 1)
        let tags = await mock.tags; XCTAssertEqual(tags, [nil, "etag"])
        await mock.offline()
        let offline = try await client.archives(for: "test-user"); XCTAssertEqual(offline.count, 1)
        do { _ = try await client.archives(for: "../bad"); XCTFail("unsafe username accepted") } catch {}
        let missing = ChessComArchiveClient(directory: temporary(), transport: ArchiveFixture(data: payload, missing: true))
        do { _ = try await missing.archives(for: "missing"); XCTFail("404 accepted") } catch { XCTAssertNotNil(error as? ArchiveError) }
    }
    @MainActor func report(_ game: GameRecord, losses: [Double], depth: Int = 14) throws -> GameReviewReport {
        let positions = try game.positions()
        let items = game.moves.enumerated().map { index, move in
            let p = positions[index], loss = losses[index % losses.count]
            return ReviewedMove(index: index + 1, side: p.sideToMove, san: SAN.string(for: move, in: p), move: move,
                bestMove: move, bestSAN: nil, before: ReviewScore(.centipawns(0)), after: ReviewScore(.centipawns(0)), loss: loss,
                quality: ReviewQuality.classify(loss: loss, isBest: loss == 0), highlight: nil, explanation: "fixture", bestLine: [move], actualLine: [move], depth: depth)
        }
        return GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: game.analysisKey, depth: depth, engine: "fixture", completedAt: Date(), moves: items)
    }
    @MainActor func testRecommendationsUseOwnerSideAndNotGameResult() throws {
        let line = "1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O *"
        var white = try PGN.decode(line), black = try PGN.decode(line)
        white.tags["White"] = "Owner"; white.tags["Result"] = "0-1"; white.tags["ECO"] = "C60"
        black.tags["Black"] = "OWNER"; black.tags["Result"] = "1-0"; black.tags["ECO"] = "C60"
        let reports = [white.id: try report(white, losses: [0, 0.4]), black.id: try report(black, losses: [0, 0.4])]
        let results = PersonalGameSelector.recommendations(games: [white, black], reports: reports, username: "owner", limit: 1)
        XCTAssertTrue(results.first { $0.gameID == white.id }?.tags.contains("精彩发挥") == true)
        XCTAssertTrue(results.first { $0.gameID == black.id }?.tags.contains("复盘素材") == true)
        XCTAssertEqual(PersonalGameSelector.recommendations(games: [white], reports: [white.id: try report(white, losses: [0], depth: 10)], username: "owner").count, 0)
        XCTAssertEqual(results, PersonalGameSelector.recommendations(games: [white, black], reports: reports, username: "owner", limit: 1))
    }
    @MainActor func testBackgroundWaitsForForegroundAndResumesPartialReport() async throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder.appendingPathComponent("Library")), trees = OpeningTreeStore(directory: folder.appendingPathComponent("Trees"))
        var game = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *"); game.tags["White"] = "Owner"; library.save(game)
        let complete = try report(game, losses: [0])
        library.saveReview(GameReviewReport(version: complete.version, analysisKey: complete.analysisKey, depth: 14, engine: "fixture", completedAt: Date(), moves: Array(complete.moves.prefix(2))), for: game.id)
        let engine = TreeFixtureEngine()
        let sync = OpeningTreeSyncCoordinator(library: library, trees: trees, directory: folder.appendingPathComponent("Sync"), engineFactory: { engine })
        sync.username = "owner"; sync.foregroundBusy = true; sync.resume()
        try await Task.sleep(for: .milliseconds(350)); let count = await engine.calls; XCTAssertEqual(count, 0)
        sync.foregroundBusy = false
        let deadline = Date().addingTimeInterval(5)
        while sync.isAnalyzing && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(sync.isAnalyzing); XCTAssertEqual(sync.analyzed, 1)
        XCTAssertEqual(library.review(for: game)?.moves.count, 4)
        let calls = await engine.calls; XCTAssertGreaterThan(calls, 0); XCTAssertLessThanOrEqual(calls, 4)
    }
}
private actor ArchiveFixture: ArchiveTransport {
    let data: Data; let missing: Bool; var disconnected = false; var tags: [String?] = []
    init(data: Data, missing: Bool = false) { self.data = data; self.missing = missing }
    func offline() { disconnected = true }
    func fetch(url: URL, etag: String?, modified: String?) async throws -> ArchiveFetch? {
        tags.append(etag)
        if missing { throw ArchiveError.response(404) }
        if disconnected { throw URLError(.notConnectedToInternet) }
        return etag == nil ? ArchiveFetch(data: data, etag: "etag", modified: nil) : nil
    }
}
private actor TreeFixtureEngine: ChessEngine {
    nonisolated let name = "fixture"
    var calls = 0
    func start() async throws {}
    func stop() async {}
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        calls += 1
        let move = limit.rootMoves.first ?? MoveGenerator.allLegalMoves(for: position.sideToMove, in: position).first!
        let wdl = EngineWDL(wins: 100, draws: 800, losses: 100)
        return EngineResult(score: .centipawns(0), depth: limit.depth, bestMove: move, principalVariation: [move], elapsedMilliseconds: 1, nodes: 1,
            variations: [EngineVariation(rank: 1, score: .centipawns(0), depth: limit.depth, principalVariation: [move], wdl: wdl)])
    }
}

extension OpeningTreeTests {
    @MainActor func testExistingRouteUsesGradesWithoutEngineAndNewBranchStaysDraft() async throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let game = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *")
        let id = store.create(name: "我的 e4", side: .white)
        store.synchronize(record: game, kind: .game, report: try report(game, losses: [0.01], depth: 18), treeID: id)
        _ = store.nodes(for: id); _ = store.nodes(for: id, includeHidden: true)
        let firstKey = OpeningTreeDocument.nodeID(fen: game.initialFEN, moves: Array(game.moves.prefix(1)))
        let originalAnnotation = store.tree(id)!.annotations[firstKey]!
        store.update(id) { $0.annotations.removeValue(forKey: firstKey) }
        XCTAssertNil(store.nodes(for: id).first { $0.id == firstKey }?.annotation)
        XCTAssertNil(store.nodes(for: id, includeHidden: true).first { $0.id == firstKey }?.annotation)
        store.update(id) { $0.annotations[firstKey] = originalAnnotation }
        XCTAssertEqual(store.nodes(for: id), store.tree(id)!.nodes())
        var browsing = game; browsing.id = UUID(); browsing.moves = Array(game.moves.prefix(3)); browsing.cursor = 3
        let cached = try XCTUnwrap(store.cachedReview(for: browsing, engine: "fixture"))
        XCTAssertEqual(cached.moves.count, 3); XCTAssertEqual(cached.depth, 18)
        XCTAssertNil(store.cachedReview(for: browsing, engine: "another engine"))
        XCTAssertNil(store.cachedReview(for: browsing, engine: "fixture", minimumDepth: 20))
        let engine = TreeFixtureEngine(), review = GameReviewCoordinator()
        review.updateLive(record: browsing, cursor: 3, engine: engine, cached: cached)
        review.updateLive(record: browsing, cursor: 1, engine: engine, cached: cached, allowAnalysis: false)
        try await Task.sleep(for: .milliseconds(100))
        let calls = await engine.calls; XCTAssertEqual(calls, 0); XCTAssertFalse(review.isRunning)
        XCTAssertEqual(review.moves, cached.moves)
        browsing.moves.append(try SAN.move("d6", in: browsing.positions().last!)); browsing.cursor = 4
        review.updateLive(record: browsing, cursor: 4, engine: engine, cached: store.cachedReview(for: browsing, engine: "fixture"))
        let deadline = Date().addingTimeInterval(3)
        while review.isRunning && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        let newCalls = await engine.calls; XCTAssertGreaterThan(newCalls, 0); XCTAssertLessThanOrEqual(newCalls, 2)
        XCTAssertEqual(Array(review.moves.prefix(3)), cached.moves)
        let draftID = OpeningTreeDocument.nodeID(fen: browsing.initialFEN, moves: browsing.moves)
        store.saveKnownAnnotations(record: browsing, report: try XCTUnwrap(review.report), treeID: id)
        XCTAssertFalse(store.nodes(for: id, includeHidden: true).contains { $0.id == draftID })
        store.synchronize(record: browsing, kind: .research, report: review.report, treeID: id)
        XCTAssertTrue(store.nodes(for: id).contains { $0.id == draftID })
        XCTAssertEqual(store.nodes(for: id).first { $0.moves.count == 1 }?.side, .white)
        XCTAssertEqual(store.nodes(for: id).first { $0.moves.count == 2 }?.side, .black)
    }
    @MainActor func testRepertoiresSplitByOwnerColorWithIndependentNotesAndBindings() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let white = try PGN.decode("1. d4 d5 2. c4 e6 *"), black = try PGN.decode("1. d4 Nf6 2. c4 g6 *")
        let id = store.create(name: "d4 · 开局树", groupingKey: OpeningTreeDocument.firstMoveGroup(fen: white.initialFEN, moves: white.moves).key)
        store.synchronize(record: white, kind: .game, report: try report(white, losses: [0]), treeID: id)
        store.synchronize(record: black, kind: .game, report: try report(black, losses: [0]), treeID: id)
        let root = OpeningTreeDocument.nodeID(fen: white.initialFEN, moves: Array(white.moves.prefix(1)))
        store.update(id) { $0.notes[root] = "中心计划" }
        store.bind(id, to: white); store.bind(id, to: black)
        store.consolidateByFirstMove(sourceSides: [white.id: .white, black.id: .black])
        XCTAssertEqual(store.trees.count, 2)
        let a = try XCTUnwrap(store.tree(store.boundTree(for: white))), b = try XCTUnwrap(store.tree(store.boundTree(for: black)))
        XCTAssertEqual(a.repertoireSide, .white); XCTAssertEqual(b.repertoireSide, .black)
        XCTAssertEqual(a.sources.map(\.gameID), [white.id]); XCTAssertEqual(b.sources.map(\.gameID), [black.id])
        XCTAssertEqual(a.notes[root], "中心计划"); XCTAssertEqual(b.notes[root], "中心计划")
        store.update(a.id) { $0.notes[root] = "我的白方计划" }
        XCTAssertEqual(store.tree(b.id)?.notes[root], "中心计划")
        XCTAssertEqual(OpeningTreeStore(directory: folder).trees, store.trees)
    }
    @MainActor func testFirstMoveMigrationMergesColorsAndPreservesEdits() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        var white = try PGN.decode("1. d4 d5 2. c4 e6 *"), black = try PGN.decode("1. d4 Nf6 2. c4 g6 *")
        white.tags["White"] = "Owner"; white.tags["ECO"] = "D30"
        black.tags["Black"] = "Owner"; black.tags["ECO"] = "E60"
        XCTAssertNotEqual(PersonalGameSelector.grouping(white, side: .white).key, PersonalGameSelector.grouping(black, side: .black).key)
        let a = store.create(name: "白方 · 后翼弃兵", groupingKey: "white:D30")
        let b = store.create(name: "黑方 · 印度防御", groupingKey: "black:E60")
        store.synchronize(record: white, kind: .game, report: try report(white, losses: [0], depth: 18), treeID: a)
        store.synchronize(record: black, kind: .game, report: try report(black, losses: [0.1]), treeID: b)
        let unplayed = GameRecord(position: .starting)
        store.synchronize(record: unplayed, kind: .research, treeID: a)
        // Duplicate game in another old theme must not count twice.
        store.synchronize(record: white, kind: .game, treeID: b)
        let trunk = OpeningTreeDocument.nodeID(fen: white.initialFEN, moves: Array(white.moves.prefix(1)))
        let hidden = OpeningTreeDocument.nodeID(fen: black.initialFEN, moves: Array(black.moves.prefix(2)))
        store.update(a) { $0.notes[trunk] = "占据中心"; $0.maxPlies = 4; $0.preferredChildren[trunk] = OpeningTreeDocument.nodeID(fen: white.initialFEN, moves: Array(white.moves.prefix(2))) }
        store.update(b) { $0.notes[trunk] = "黑方应对"; $0.hidden.insert(hidden); $0.maxPlies = 6 }
        store.bind(a, to: white); store.bind(b, to: black)
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertEqual(restored.trees.count, 1)
        let tree = try XCTUnwrap(restored.trees.first)
        XCTAssertEqual(tree.name, "d4 · 开局树"); XCTAssertEqual(tree.maxPlies, 6)
        XCTAssertEqual(tree.sources.count, 3)
        XCTAssertEqual(tree.nodes(includeHidden: true).first { $0.id == trunk }?.count, 2)
        XCTAssertEqual(tree.annotations[trunk]?.review.depth, 18)
        XCTAssertTrue(tree.notes[trunk]!.contains("占据中心")); XCTAssertTrue(tree.notes[trunk]!.contains("黑方应对"))
        XCTAssertTrue(tree.hidden.contains(hidden)); XCTAssertNotNil(tree.preferredChildren[trunk])
        XCTAssertEqual(restored.boundTree(for: white), tree.id); XCTAssertEqual(restored.boundTree(for: black), tree.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("MigrationBackups").path))
        XCTAssertEqual(OpeningTreeStore(directory: folder).trees, restored.trees)
    }
    @MainActor func testMixedFirstMovesSplitWithoutLosingSourcesOrBindings() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let id = store.create(name: "自由研究", groupingKey: "white:A00")
        let e4 = try PGN.decode("1. e4 e5 *"), d4 = try PGN.decode("1. d4 d5 *")
        store.synchronize(record: e4, kind: .game, treeID: id)
        store.synchronize(record: d4, kind: .research, treeID: id)
        store.bind(id, to: d4)
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertEqual(restored.trees.count, 2)
        XCTAssertEqual(Set(restored.trees.flatMap(\.sources).map(\.gameID)), Set([e4.id, d4.id]))
        let bound = try XCTUnwrap(restored.tree(restored.boundTree(for: d4)))
        XCTAssertEqual(bound.sources.first?.moves.first, d4.moves.first)
        XCTAssertNotEqual(PersonalGameSelector.grouping(e4, side: .white).key, PersonalGameSelector.grouping(d4, side: .white).key)
    }
    @MainActor func testSparseLiveReportDoesNotOverwriteDeepBackgroundReport() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder)
        let game = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *")
        let complete = try report(game, losses: [0.1], depth: 18)
        library.saveReview(complete, for: game.id)
        let shallow = try report(game, losses: [0], depth: 10)
        let sparse = GameReviewReport(version: shallow.version, analysisKey: shallow.analysisKey, depth: 10, engine: shallow.engine, completedAt: Date(), moves: [shallow.moves.last!])
        library.saveReview(sparse, for: game.id)
        XCTAssertEqual(library.review(for: game)?.moves, complete.moves)
        XCTAssertEqual(library.review(for: game)?.depth, 18)
    }
    @MainActor func testRecommendationsAppendWithoutDestroyingTreeEdits() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let library = GameLibrary(directory: folder.appendingPathComponent("Library")), trees = OpeningTreeStore(directory: folder.appendingPathComponent("Trees"))
        var game = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *"); game.tags["White"] = "Owner"; game.tags["ECO"] = "C20"
        library.save(game); library.saveReview(try report(game, losses: [0.3, 0]), for: game.id)
        let sync = OpeningTreeSyncCoordinator(library: library, trees: trees, directory: folder.appendingPathComponent("Sync"))
        sync.username = "owner"; sync.refreshRecommendations()
        let id = try XCTUnwrap(trees.trees.first?.id); let node = trees.tree(id)!.nodes().first { $0.moves.count == 1 }!
        trees.update(id) { $0.name = "保留我的名字"; $0.notes[node.id] = "研究计划"; $0.hidden.insert(node.id) }
        sync.refreshRecommendations()
        XCTAssertEqual(trees.trees.count, 1); XCTAssertEqual(trees.tree(id)?.name, "保留我的名字")
        XCTAssertEqual(trees.tree(id)?.notes[node.id], "研究计划"); XCTAssertTrue(trees.tree(id)!.hidden.contains(node.id))
        XCTAssertEqual(trees.tree(id)?.sources.count, 1)
    }
    func testRateLimitRetryAndCancellation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RateLimitURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        RateLimitURLProtocol.reset()
        let transport = URLSessionArchiveTransport(session: session)
        let result = try await transport.fetch(url: URL(string: "https://api.chess.com/pub/player/test/games/archives")!, etag: nil, modified: nil)
        XCTAssertNotNil(result); XCTAssertEqual(RateLimitURLProtocol.requestCount, 2)
        RateLimitURLProtocol.reset()
        let task = Task { try await transport.fetch(url: URL(string: "https://api.chess.com/pub/player/test/games/archives")!, etag: nil, modified: nil) }
        try await Task.sleep(for: .milliseconds(100)); task.cancel()
        do { _ = try await task.value; XCTFail("cancelled request completed") } catch {}
    }
}
private final class RateLimitURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var count = 0
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); count = 0; lock.unlock() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; let number = Self.count; Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: number == 1 ? 429 : 200, httpVersion: "HTTP/1.1", headerFields: ["Retry-After": "0"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"archives\":[]}".utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension OpeningTreeTests {
    @MainActor func testDeleteContinuationPersistsAndExplicitSaveRestores() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let a = try PGN.decode("1. e4 e5 2. Nf3 Nc6 *")
        let b = try PGN.decode("1. e4 c5 2. Nf3 d6 *")
        let group = OpeningTreeDocument.firstMoveGroup(fen: a.initialFEN, moves: a.moves, side: .white)
        let id = store.create(name: "我的树", groupingKey: group.key, side: .white)
        store.synchronize(record: a, kind: .game, treeID: id)
        store.synchronize(record: b, kind: .game, treeID: id)
        let node = try XCTUnwrap(store.nodes(for: id).first { $0.moves == Array(a.moves.prefix(2)) })
        store.deleteBranch(id, node: node)
        XCTAssertTrue(store.nodes(for: id).contains { $0.id == node.id })
        XCTAssertFalse(store.nodes(for: id).contains { $0.moves == a.moves })
        XCTAssertTrue(store.nodes(for: id).contains { $0.moves == b.moves })
        store.synchronize(record: a, kind: .game, treeID: id)
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertFalse(restored.nodes(for: id).contains { $0.moves == a.moves })
        restored.synchronize(record: a, kind: .research, treeID: id, restoreDeleted: true)
        XCTAssertTrue(restored.nodes(for: id).contains { $0.moves == a.moves })
        store.undoLastDeletion()
        XCTAssertTrue(store.nodes(for: id).contains { $0.moves == a.moves })
    }
    @MainActor func testWholeTreeDeleteSuppressionAndUndo() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let a = try PGN.decode("1. d4 d5 *")
        let group = OpeningTreeDocument.firstMoveGroup(fen: a.initialFEN, moves: a.moves, side: .black)
        let id = store.create(name: "执黑", groupingKey: group.key, side: .black)
        store.bind(id, to: a); store.synchronize(record: a, kind: .game)
        XCTAssertTrue(store.deleteTree(id)); XCTAssertNil(store.tree(id)); XCTAssertNil(store.boundTree(for: a))
        let restored = OpeningTreeStore(directory: folder)
        XCTAssertTrue(restored.isGroupDeleted(group.key)); XCTAssertNil(restored.tree(id))
        XCTAssertEqual(store.undoLastDeletion(), id)
        XCTAssertEqual(store.boundTree(for: a), id); XCTAssertFalse(store.isGroupDeleted(group.key))
        XCTAssertEqual(store.nodes(for: id).filter { $0.move != nil }.count, 2)
    }
    @MainActor func testDeleteSelectedStepRetainsParentAndAlternateMove() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder), id = store.create(name: "修改路线")
        let a = try PGN.decode("1. e4 e5 2. Nf3 *"), b = try PGN.decode("1. e4 c5 *")
        store.synchronize(record: a, kind: .research, treeID: id); store.synchronize(record: b, kind: .research, treeID: id)
        let node = try XCTUnwrap(store.nodes(for: id).first { $0.moves == Array(a.moves.prefix(2)) })
        store.deleteBranch(id, node: node, includeNode: true)
        XCTAssertFalse(store.nodes(for: id, includeHidden: true).contains { $0.id == node.id })
        XCTAssertTrue(store.nodes(for: id).contains { $0.moves == Array(a.moves.prefix(1)) })
        XCTAssertTrue(store.nodes(for: id).contains { $0.moves == b.moves })
    }
}

extension OpeningTreeTests {
    @MainActor func testAutomaticTreeRoutingBySideAndFirstMove() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let a = try PGN.decode("1. e4 e5 2. Nf3 *"), b = try PGN.decode("1. e4 c5 *"), c = try PGN.decode("1. d4 d5 *")
        XCTAssertNil(store.resolveTree(fen: a.initialFEN, moves: [], side: .white))
        XCTAssertNil(store.matchingTree(fen: a.initialFEN, moves: a.moves, side: .white))
        XCTAssertTrue(store.trees.isEmpty)
        let white = try XCTUnwrap(store.resolveTree(fen: a.initialFEN, moves: a.moves, side: .white))
        store.synchronize(record: a, kind: .research, treeID: white)
        XCTAssertEqual(store.matchingTree(fen: b.initialFEN, moves: b.moves, side: .white), white)
        XCTAssertEqual(store.resolveTree(fen: b.initialFEN, moves: b.moves, side: .white), white)
        let black = store.resolveTree(fen: a.initialFEN, moves: a.moves, side: .black)
        let d4 = store.resolveTree(fen: c.initialFEN, moves: c.moves, side: .white)
        XCTAssertNotEqual(white, black); XCTAssertNotEqual(white, d4)
        XCTAssertEqual(store.trees.count, 3)
        XCTAssertNil(store.matchingTree(fen: a.initialFEN, moves: [], side: .white))
        XCTAssertEqual(store.matchingTree(fen: a.initialFEN, moves: Array(a.moves.prefix(1)), side: .white), white)
    }
    @MainActor func testOpeningEngineSuggestionIsOnDemandAndCached() async throws {
        let engine = TreeFixtureEngine()
        let coordinator = AnalysisCoordinator(engine: engine)
        XCTAssertFalse(coordinator.restoreCachedStrategy(for: .starting, strategy: .balanced, depth: 14))
        let initialCalls = await engine.calls; XCTAssertEqual(initialCalls, 0)
        coordinator.refreshSelectedStrategy(for: .starting, strategy: .balanced, depth: 14)
        for _ in 0..<100 where coordinator.snapshot.state != .ready { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(coordinator.snapshot.state, .ready)
        let move = try XCTUnwrap(coordinator.snapshot.bestLine.currentMove)
        XCTAssertTrue(MoveGenerator.allLegalMoves(for: .white, in: .starting).contains(move))
        var next = GamePosition.starting; next.make(move)
        coordinator.reset(for: next)
        XCTAssertFalse(coordinator.restoreCachedStrategy(for: next, strategy: .balanced, depth: 14))
        XCTAssertNil(coordinator.snapshot.bestLine.currentMove)
        coordinator.reset(for: .starting)
        XCTAssertTrue(coordinator.restoreCachedStrategy(for: .starting, strategy: .balanced, depth: 14))
        XCTAssertEqual(coordinator.snapshot.bestLine.currentMove, move)
        coordinator.refreshSelectedStrategy(for: .starting, strategy: .balanced, depth: 14)
        let calls = await engine.calls; XCTAssertEqual(calls, 1)
        XCTAssertFalse(coordinator.restoreCachedStrategy(for: .starting, strategy: .balanced, depth: 18))
    }
}

extension OpeningTreeTests {
    @MainActor func testThreeCandidatesUseSingleSearchAndCache() async throws {
        let engine = ThreeCandidateEngine()
        let coordinator = AnalysisCoordinator(engine: engine)
        coordinator.refreshSelectedStrategy(for: .starting, strategy: .balanced, depth: 14)
        for _ in 0..<100 where coordinator.snapshot.state != .ready { try await Task.sleep(for: .milliseconds(10)) }
        let candidates = coordinator.snapshot.candidates
        XCTAssertEqual(candidates.count, 3)
        XCTAssertEqual(candidates.map(\.rank), [1, 2, 3])
        XCTAssertEqual(candidates.map(\.quality), [.best, .excellent, .blunder])
        XCTAssertEqual(Set(candidates.map(\.move)).count, 3)
        XCTAssertTrue(candidates.allSatisfy { GamePosition.starting[$0.move.from]?.color == .white })
        coordinator.refreshSelectedStrategy(for: .starting, strategy: .balanced, depth: 14)
        let requests = await engine.requests
        XCTAssertEqual(requests, [3])
        _ = try await coordinator.bestMove(for: .starting, depth: 10, strategy: .aggressive)
        let later = await engine.requests
        XCTAssertEqual(later, [3, 1])
    }
    func testCandidatesDoNotInventMovesOrMixDepths() throws {
        let position = GamePosition.starting
        let a = Move(uci: "e2e4")!, b = Move(uci: "d2d4")!, illegal = Move(uci: "e7e5")!
        let result = EngineResult(score: .centipawns(0), depth: 14, bestMove: a, principalVariation: [a], elapsedMilliseconds: 1, nodes: 1,
            variations: [EngineVariation(rank: 1, score: .centipawns(0), depth: 14, principalVariation: [a]),
                         EngineVariation(rank: 2, score: .centipawns(0), depth: 14, principalVariation: [a]),
                         EngineVariation(rank: 3, score: .centipawns(0), depth: 13, principalVariation: [b]),
                         EngineVariation(rank: 4, score: .centipawns(0), depth: 14, principalVariation: [illegal])])
        XCTAssertEqual(MoveCandidate.make(result: result, position: position).map(\.move), [a])
    }
}
private actor ThreeCandidateEngine: ChessEngine {
    nonisolated let name = "three-candidate-fixture"
    var requests: [Int] = []
    func start() async throws {}
    func stop() async {}
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        requests.append(limit.multiPV)
        let moves = ["e2e4", "d2d4", "g1f3"].map { Move(uci: $0)! }
        let wdls = [EngineWDL(wins: 200, draws: 800, losses: 0)!, EngineWDL(wins: 190, draws: 800, losses: 10)!, EngineWDL(wins: 0, draws: 200, losses: 800)!]
        let variations = moves.enumerated().prefix(limit.multiPV).map { i, move in
            EngineVariation(rank: i+1, score: .centipawns(i == 2 ? -200 : 20-i), depth: limit.depth, principalVariation: [move], wdl: wdls[i])
        }
        return EngineResult(score: .centipawns(20), depth: limit.depth, bestMove: moves[0], principalVariation: [moves[0]], elapsedMilliseconds: 1, nodes: 1, variations: variations)
    }
}

extension OpeningTreeTests {
    func curationRows(_ game: GameRecord, whiteCP: Int, loss: Double = 0, depth: Int = 14) throws -> [ReviewedMove] {
        let positions = try game.positions()
        return game.moves.enumerated().map { index, move in
            let side = positions[index].sideToMove
            return ReviewedMove(index: index+1, side: side, san: SAN.string(for: move, in: positions[index]), move: move, bestMove: move, bestSAN: nil,
                before: ReviewScore(.centipawns(0)), after: ReviewScore(.centipawns(side == .white ? whiteCP : -whiteCP)), loss: loss,
                quality: .good, highlight: nil, explanation: "fixture", bestLine: [move], actualLine: [move], depth: depth)
        }
    }
    func testCurationUsesEndpointAdvantageAndProtectsUnratedResearch() throws {
        let game = try PGN.decode("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 *")
        let white = try curationRows(game, whiteCP: 90)
        let black = try curationRows(game, whiteCP: -90)
        XCTAssertEqual(OpeningCurationDecision.evaluate(reviews: white, plies: 8, isResearch: false, hasNotes: false).favoredSide, .white)
        XCTAssertEqual(OpeningCurationDecision.evaluate(reviews: black, plies: 8, isResearch: false, hasNotes: false).favoredSide, .black)
        let errors = try curationRows(game, whiteCP: 90, loss: 0.2)
        XCTAssertTrue(OpeningCurationDecision.evaluate(reviews: errors, plies: 8, isResearch: false, hasNotes: false).remove)
        XCTAssertFalse(OpeningCurationDecision.evaluate(reviews: errors, plies: 8, isResearch: true, hasNotes: false).remove)
        XCTAssertFalse(OpeningCurationDecision.evaluate(reviews: errors, plies: 8, isResearch: false, hasNotes: true).remove)
        XCTAssertFalse(OpeningCurationDecision.evaluate(reviews: Array(errors.prefix(6)), plies: 8, isResearch: false, hasNotes: false).remove)
        XCTAssertNil(OpeningCurationDecision.evaluate(reviews: try curationRows(game, whiteCP: 20), plies: 8, isResearch: false, hasNotes: false).favoredSide)
    }
    @MainActor func testCurationBackupRestartAndNoReimportOfRemovedRoutes() throws {
        let folder = temporary(); defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let a = try PGN.decode("1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 *")
        let b = try PGN.decode("1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Nf3 Be7 *")
        let c = try PGN.decode("1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 *")
        for (game, score, loss) in [(a, 80, 0.0), (b, -80, 0.0), (c, 90, 0.2)] {
            let id = store.create(name: "旧树", side: .black)
            let report = GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: game.analysisKey, depth: 14, engine: "Stockfish 18", completedAt: Date(), moves: try curationRows(game, whiteCP: score, loss: loss))
            store.bind(id, to: game); store.synchronize(record: game, kind: .game, report: report, treeID: id)
        }
        store.curateByAdvantage()
        XCTAssertEqual(store.curation?.removedRoutes, 1)
        XCTAssertEqual(store.tree(store.boundTree(for: a))?.repertoireSide, .white)
        XCTAssertEqual(store.tree(store.boundTree(for: b))?.repertoireSide, .black)
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(store.curation?.backupPath)))
        let loaded = OpeningTreeStore(directory: folder)
        XCTAssertEqual(Set(loaded.trees.map(\.id)), Set(store.trees.map(\.id)))
        loaded.importCurated(c, report: nil)
        XCTAssertFalse(loaded.trees.flatMap(\.sources).contains { $0.gameID == c.id })
        loaded.curateByAdvantage(); XCTAssertEqual(loaded.trees.count, 2)
    }
    func testPositionSetupRejectsInvalidKingsPawnsAndRights() throws {
        XCTAssertEqual(try PositionSetup.validate(.starting), .starting)
        var pieces = GamePosition.starting.pieces
        pieces[Square("e1")!] = nil
        XCTAssertThrowsError(try PositionSetup.validate(GamePosition(pieces: pieces)))
        let kings: [Square: Piece] = [Square("e1")!: Piece(color: .white, kind: .king), Square("e2")!: Piece(color: .black, kind: .king)]
        XCTAssertThrowsError(try PositionSetup.validate(GamePosition(pieces: kings)))
        var valid: [Square: Piece] = [Square("e1")!: Piece(color: .white, kind: .king), Square("e8")!: Piece(color: .black, kind: .king)]
        XCTAssertNoThrow(try PositionSetup.validate(GamePosition(pieces: valid, sideToMove: .black)))
        XCTAssertThrowsError(try PositionSetup.validate(GamePosition(pieces: valid, castlingRights: .all)))
        valid[Square("a8")!] = Piece(color: .white, kind: .pawn)
        XCTAssertThrowsError(try PositionSetup.validate(GamePosition(pieces: valid)))
    }
}
