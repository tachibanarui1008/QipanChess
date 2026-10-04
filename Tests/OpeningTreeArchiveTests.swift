import XCTest
@testable import Analysis
import GameCore
import Engine

final class OpeningTreeArchiveTests: XCTestCase {
    func sample() throws -> OpeningTreeDocument {
        let game = try PGN.decode("1. e4 e5 2. Nf3 *")
        var tree = OpeningTreeDocument(name: "我的研究")
        tree.organizedByAdvantage = true
        tree.repertoireSide = .white
        tree.sources = [TreeSource(id: "research", gameID: game.id, title: "研究", initialFEN: game.initialFEN, moves: game.moves, kind: .research)]
        let root = OpeningTreeDocument.nodeID(fen: game.initialFEN, moves: [])
        let first = OpeningTreeDocument.nodeID(fen: game.initialFEN, moves: Array(game.moves.prefix(1)))
        tree.notes[first] = "争夺中心 ♟"
        let move = game.moves[0]
        let review = ReviewedMove(index: 1, side: .white, san: "e4", move: move,
            bestMove: move, bestSAN: "e4", before: ReviewScore(.centipawns(20)), after: ReviewScore(.centipawns(25)),
            loss: 0, quality: .best, highlight: nil, explanation: "控制中心", bestLine: [move], actualLine: [move], depth: 18)
        tree.annotations[first] = TreeAnnotation(review: review, version: GameReviewReport.currentVersion, engine: "Stockfish 18")
        tree.preferredChildren[root] = first
        tree.hidden = [first]
        tree.deletedEdges = [OpeningTreeDocument.nodeID(fen: game.initialFEN, moves: game.moves)]
        return tree
    }

    @MainActor func testTransferPreservesSnapshotAcrossRestartAndReplacementBacksUp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try sample()
        let archive = try OpeningTreeArchive.decode(OpeningTreeArchive(trees: [original]).encoded())
        XCTAssertEqual(archive.trees, [original])
        let store = OpeningTreeStore(directory: folder)
        try store.importArchive(archive)
        var expected = original; expected.importedSnapshot = true
        XCTAssertEqual(OpeningTreeStore(directory: folder).tree(original.id), expected)
        store.curateByAdvantage()
        XCTAssertEqual(store.tree(original.id), expected)
        XCTAssertEqual(OpeningTreeStore(directory: folder).tree(original.id), expected)
        var changed = original; changed.name = "平板新版"
        XCTAssertThrowsError(try store.importArchive(OpeningTreeArchive(trees: [changed])))
        XCTAssertEqual(store.tree(original.id), expected)
        try store.importArchive(OpeningTreeArchive(trees: [changed]), replacingExisting: true)
        XCTAssertEqual(store.tree(original.id)?.name, "平板新版")
        let backups = try FileManager.default.contentsOfDirectory(at: folder.appendingPathComponent("ImportBackups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.count, 1)
        let old = try JSONDecoder().decode(OpeningTreeDocument.self, from: Data(contentsOf: backups[0].appendingPathComponent("\(original.id).json")))
        XCTAssertEqual(old, expected)
        XCTAssertEqual(OpeningTreeStore(directory: folder).tree(original.id)?.name, "平板新版")
    }

    @MainActor func testInvalidBatchDoesNotModifyExistingTrees() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = OpeningTreeStore(directory: folder)
        let original = try sample()
        try store.importArchive(OpeningTreeArchive(trees: [original]))
        var changed = original; changed.name = "不能写入"
        var invalid = original; invalid.id = UUID(); invalid.version = 99
        XCTAssertThrowsError(try store.importArchive(OpeningTreeArchive(trees: [changed, invalid]), replacingExisting: true))
        XCTAssertEqual(store.tree(original.id)?.name, original.name)
        XCTAssertNil(store.tree(invalid.id))
        XCTAssertThrowsError(try OpeningTreeArchive(trees: [original, original]).encoded())
        var future = OpeningTreeArchive(trees: [original]); future.version = 99
        XCTAssertThrowsError(try future.encoded())
        XCTAssertThrowsError(try OpeningTreeArchive.decode(Data("{}".utf8)))
    }
}
