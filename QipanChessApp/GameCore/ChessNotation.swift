import Foundation

public enum ChessDocumentError: LocalizedError {
    case invalidFEN(String)
    case invalidPGN(String)
    case illegalMove(String)

    public var errorDescription: String? {
        switch self {
        case .invalidFEN(let detail): "FEN 无效：\(detail)"
        case .invalidPGN(let detail): "PGN 无效：\(detail)"
        case .illegalMove(let move): "无法识别或不合法的走法：\(move)"
        }
    }
}

extension GamePosition {
    public init(fen: String) throws {
        let fields = fen.split(whereSeparator: \.isWhitespace).map(String.init)
        guard fields.count == 6, ["w", "b"].contains(fields[1]),
              let halfmove = Int(fields[4]), halfmove >= 0,
              let fullmove = Int(fields[5]), (1...100_000).contains(fullmove)
        else { throw ChessDocumentError.invalidFEN("需要六个字段和有效回合数") }
        let rows = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { throw ChessDocumentError.invalidFEN("需要八行棋盘") }
        var pieces: [Square: Piece] = [:]
        let kinds: [Character: PieceKind] = ["k": .king, "q": .queen, "r": .rook, "b": .bishop, "n": .knight, "p": .pawn]
        for (row, text) in rows.enumerated() {
            var file = 0
            for symbol in text {
                if let count = symbol.wholeNumberValue, (1...8).contains(count) {
                    file += count
                } else {
                    guard let kind = kinds[Character(String(symbol).lowercased())],
                          let square = Square(file: file, rank: 7 - row)
                    else { throw ChessDocumentError.invalidFEN("棋子或格子无效") }
                    guard kind != .pawn || (1...6).contains(square.rank) else {
                        throw ChessDocumentError.invalidFEN("兵不能位于第一或第八横线")
                    }
                    pieces[square] = Piece(color: symbol.isUppercase ? .white : .black, kind: kind)
                    file += 1
                }
                guard file <= 8 else { throw ChessDocumentError.invalidFEN("每行需要八格") }
            }
            guard file == 8 else { throw ChessDocumentError.invalidFEN("每行需要八格") }
        }
        for color in PieceColor.allCases {
            guard pieces.values.filter({ $0 == Piece(color: color, kind: .king) }).count == 1 else {
                throw ChessDocumentError.invalidFEN("双方各需要一枚王")
            }
        }
        var rights: CastlingRights = []
        if fields[2] != "-" {
            var seen: Set<Character> = []
            for symbol in fields[2] {
                guard seen.insert(symbol).inserted else { throw ChessDocumentError.invalidFEN("易位权重复") }
                let right: CastlingRights
                let color: PieceColor
                let file: Int
                switch symbol {
                case "K": (right, color, file) = (.whiteKingSide, .white, 7)
                case "Q": (right, color, file) = (.whiteQueenSide, .white, 0)
                case "k": (right, color, file) = (.blackKingSide, .black, 7)
                case "q": (right, color, file) = (.blackQueenSide, .black, 0)
                default: throw ChessDocumentError.invalidFEN("易位权无效")
                }
                let rank = color == .white ? 0 : 7
                guard pieces[Square(file: 4, rank: rank)!] == Piece(color: color, kind: .king),
                      pieces[Square(file: file, rank: rank)!] == Piece(color: color, kind: .rook)
                else { throw ChessDocumentError.invalidFEN("易位权与王车位置不一致") }
                rights.insert(right)
            }
        }
        let side: PieceColor = fields[1] == "w" ? .white : .black
        var ep: Square?
        if fields[3] != "-" {
            guard let target = Square(fields[3]), target.rank == (side == .white ? 5 : 2),
                  pieces[target] == nil,
                  let pawnSquare = target.offset(file: 0, rank: side == .white ? -1 : 1),
                  pieces[pawnSquare] == Piece(color: side.opposite, kind: .pawn),
                  let origin = target.offset(file: 0, rank: side == .white ? 1 : -1),
                  pieces[origin] == nil, halfmove == 0
            else { throw ChessDocumentError.invalidFEN("吃过路兵字段无效") }
            ep = target
        }
        self.init(pieces: pieces, sideToMove: side,
                  plyCount: (fullmove - 1) * 2 + (side == .black ? 1 : 0),
                  castlingRights: rights, enPassantTarget: ep, halfmoveClock: halfmove)
        guard !MoveGenerator.isKingInCheck(side.opposite, in: self) else {
            throw ChessDocumentError.invalidFEN("非行棋方的王不能处于将军中")
        }
    }

    /// Repetition ignores clocks and en passant targets with no legal capture.
    public var repetitionKey: String {
        var fields = fen.split(separator: " ").prefix(4).map(String.init)
        if let ep = enPassantTarget {
            let canCapture = MoveGenerator.allLegalMoves(for: sideToMove, in: self).contains {
                $0.to == ep && pieces[$0.from]?.kind == .pawn && $0.from.file != $0.to.file
            }
            if !canCapture { fields[3] = "-" }
        }
        return fields.joined(separator: " ")
    }

    public var hasInsufficientMaterial: Bool {
        let nonKings = pieces.filter { $0.value.kind != .king }
        if nonKings.isEmpty { return true }
        if nonKings.count == 1 {
            return [.bishop, .knight].contains(nonKings.first!.value.kind)
        }
        if nonKings.values.allSatisfy({ $0.kind == .bishop }) {
            return Set(nonKings.keys.map { ($0.file + $0.rank) % 2 }).count == 1
        }
        return false
    }
}

public enum SAN {
    public static func string(for move: Move, in position: GamePosition) -> String {
        guard let piece = position[move.from] else { return move.uci }
        var text: String
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            text = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            let capture = position[move.to] != nil || (piece.kind == .pawn && move.from.file != move.to.file)
            let symbols: [PieceKind: String] = [.king: "K", .queen: "Q", .rook: "R", .bishop: "B", .knight: "N", .pawn: ""]
            text = symbols[piece.kind] ?? ""
            if piece.kind == .pawn {
                if capture { text += String(move.from.notation.prefix(1)) }
            } else {
                let peers = MoveGenerator.allLegalMoves(for: piece.color, in: position).filter {
                    $0.to == move.to && $0.from != move.from && position[$0.from]?.kind == piece.kind
                }
                if !peers.isEmpty {
                    if !peers.contains(where: { $0.from.file == move.from.file }) {
                        text += String(move.from.notation.prefix(1))
                    } else if !peers.contains(where: { $0.from.rank == move.from.rank }) {
                        text += String(move.from.rank + 1)
                    } else { text += move.from.notation }
                }
            }
            if capture { text += "x" }
            text += move.to.notation
            if let promotion = move.promotion { text += "=" + (symbols[promotion] ?? "Q") }
        }
        var after = position
        after.make(move)
        if MoveGenerator.isKingInCheck(after.sideToMove, in: after) {
            text += MoveGenerator.isCheckmate(for: after.sideToMove, in: after) ? "#" : "+"
        }
        return text
    }

    public static func move(_ text: String, in position: GamePosition) throws -> Move {
        let normalized = normalize(text)
        let matches = MoveGenerator.allLegalMoves(for: position.sideToMove, in: position).filter {
            normalize(string(for: $0, in: position)) == normalized || $0.uci == normalized
        }
        guard matches.count == 1, let move = matches.first else { throw ChessDocumentError.illegalMove(text) }
        return move
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "0", with: "O").filter { !"+#!?".contains($0) }
    }
}
