import Foundation

public struct Square: Hashable, Codable, Sendable, Comparable {
    public let file: Int
    public let rank: Int

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        self.file = file
        self.rank = rank
    }

    public init?(_ notation: String) {
        guard notation.count == 2,
              let fileCharacter = notation.first,
              let rankCharacter = notation.last,
              let file = "abcdefgh".firstIndex(of: fileCharacter),
              let rankNumber = Int(String(rankCharacter))
        else { return nil }

        self.init(
            file: "abcdefgh".distance(from: "abcdefgh".startIndex, to: file),
            rank: rankNumber - 1
        )
    }

    private enum CodingKeys: String, CodingKey { case file, rank }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let file = try container.decode(Int.self, forKey: .file)
        let rank = try container.decode(Int.self, forKey: .rank)
        guard let square = Square(file: file, rank: rank) else {
            throw DecodingError.dataCorruptedError(forKey: .file, in: container, debugDescription: "Square outside the board")
        }
        self = square
    }

    public var notation: String {
        let fileIndex = "abcdefgh".index("abcdefgh".startIndex, offsetBy: file)
        return "\("abcdefgh"[fileIndex])\(rank + 1)"
    }

    public func offset(file fileDelta: Int, rank rankDelta: Int) -> Square? {
        Square(file: file + fileDelta, rank: rank + rankDelta)
    }

    public static let all: [Square] = (0..<8).flatMap { rank in
        (0..<8).compactMap { file in Square(file: file, rank: rank) }
    }

    public static func < (lhs: Square, rhs: Square) -> Bool {
        lhs.rank == rhs.rank ? lhs.file < rhs.file : lhs.rank < rhs.rank
    }
}
