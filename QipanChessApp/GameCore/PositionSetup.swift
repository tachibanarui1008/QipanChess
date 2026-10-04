import Foundation

public enum PositionSetup {
    public static func validate(_ position: GamePosition) throws -> GamePosition {
        for color in PieceColor.allCases {
            let pieces = position.pieces.values.filter { $0.color == color }
            guard pieces.count <= 16, pieces.filter({ $0.kind == .pawn }).count <= 8 else {
                throw ChessDocumentError.invalidFEN("每方最多 16 枚棋子、8 枚兵")
            }
        }
        return try GamePosition(fen: position.fen)
    }
}
