import Foundation
import GameCore

/// A portable snapshot; game-library files and device preferences are not included.
public struct OpeningTreeArchive: Codable, Sendable {
    public var format = "QipanChess.OpeningTrees"
    public var version = 1
    public var trees: [OpeningTreeDocument]
    public init(trees: [OpeningTreeDocument]) { self.trees = trees }

    public func validated() throws -> Self {
        guard format == "QipanChess.OpeningTrees", version == 1,
              !trees.isEmpty, trees.count <= 1_000,
              Set(trees.map(\.id)).count == trees.count else {
            throw ChessDocumentError.invalidPGN("开局树文件格式、版本或数量无效")
        }
        for tree in trees { _ = try tree.validated() }
        return self
    }

    public func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumBytes else { throw ChessDocumentError.invalidPGN("开局树文件不能超过 50 MB，请分别导出") }
        return data
    }

    public static let maximumBytes = 50_000_000
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= maximumBytes else { throw ChessDocumentError.invalidPGN("开局树文件不能超过 50 MB") }
        return try JSONDecoder().decode(Self.self, from: data).validated()
    }
}
