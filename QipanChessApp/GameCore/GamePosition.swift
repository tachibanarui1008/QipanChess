import Foundation

public struct GamePosition: Equatable, Sendable {
    public private(set) var pieces: [Square: Piece]
    public private(set) var sideToMove: PieceColor
    public private(set) var plyCount: Int
    public private(set) var castlingRights: CastlingRights
    public private(set) var enPassantTarget: Square?
    public private(set) var halfmoveClock: Int

    public init(
        pieces: [Square: Piece],
        sideToMove: PieceColor = .white,
        plyCount: Int = 0,
        castlingRights: CastlingRights = [],
        enPassantTarget: Square? = nil,
        halfmoveClock: Int = 0
    ) {
        self.pieces = pieces
        self.sideToMove = sideToMove
        self.plyCount = plyCount
        self.castlingRights = castlingRights
        self.enPassantTarget = enPassantTarget
        self.halfmoveClock = halfmoveClock
    }

    public static var starting: GamePosition {
        var pieces: [Square: Piece] = [:]
        let backRank: [PieceKind] = [
            .rook, .knight, .bishop, .queen,
            .king, .bishop, .knight, .rook
        ]

        for file in 0..<8 {
            guard let whiteBack = Square(file: file, rank: 0),
                  let whitePawn = Square(file: file, rank: 1),
                  let blackPawn = Square(file: file, rank: 6),
                  let blackBack = Square(file: file, rank: 7)
            else { continue }

            pieces[whiteBack] = Piece(color: .white, kind: backRank[file])
            pieces[whitePawn] = Piece(color: .white, kind: .pawn)
            pieces[blackPawn] = Piece(color: .black, kind: .pawn)
            pieces[blackBack] = Piece(color: .black, kind: backRank[file])
        }

        return GamePosition(pieces: pieces, castlingRights: .all)
    }

    public subscript(square: Square) -> Piece? {
        pieces[square]
    }

    public mutating func make(_ move: Move) {
        guard let movingPiece = pieces[move.from] else { return }
        let capturedPiece = pieces[move.to]
        let isPawnMove = movingPiece.kind == .pawn
        let isCapture = capturedPiece != nil || (
            isPawnMove && move.from.file != move.to.file && move.to == enPassantTarget
        )

        pieces[move.from] = nil

        if isPawnMove,
           move.from.file != move.to.file,
           capturedPiece == nil,
           move.to == enPassantTarget,
           let capturedPawnSquare = move.to.offset(file: 0, rank: movingPiece.color == .white ? -1 : 1) {
            pieces[capturedPawnSquare] = nil
        }

        if movingPiece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            moveCastlingRook(for: movingPiece.color, kingDestination: move.to)
        }

        let resultingPiece: Piece
        if let promotion = move.promotion {
            resultingPiece = Piece(color: movingPiece.color, kind: promotion)
        } else if isPawnMove && (move.to.rank == 0 || move.to.rank == 7) {
            resultingPiece = Piece(color: movingPiece.color, kind: .queen)
        } else {
            resultingPiece = movingPiece
        }
        pieces[move.to] = resultingPiece

        updateCastlingRights(
            movingPiece: movingPiece,
            from: move.from,
            capturedPiece: capturedPiece,
            capturedAt: move.to
        )

        if isPawnMove && abs(move.to.rank - move.from.rank) == 2 {
            enPassantTarget = move.from.offset(
                file: 0,
                rank: movingPiece.color == .white ? 1 : -1
            )
        } else {
            enPassantTarget = nil
        }

        halfmoveClock = (isPawnMove || isCapture) ? 0 : halfmoveClock + 1
        sideToMove = sideToMove.opposite
        plyCount += 1
    }

    private mutating func moveCastlingRook(for color: PieceColor, kingDestination: Square) {
        let rank = color == .white ? 0 : 7
        let isKingSide = kingDestination.file == 6
        guard let rookFrom = Square(file: isKingSide ? 7 : 0, rank: rank),
              let rookTo = Square(file: isKingSide ? 5 : 3, rank: rank),
              let rook = pieces[rookFrom]
        else { return }
        pieces[rookFrom] = nil
        pieces[rookTo] = rook
    }

    private mutating func updateCastlingRights(
        movingPiece: Piece,
        from: Square,
        capturedPiece: Piece?,
        capturedAt: Square
    ) {
        if movingPiece.kind == .king {
            if movingPiece.color == .white {
                castlingRights.subtract([.whiteKingSide, .whiteQueenSide])
            } else {
                castlingRights.subtract([.blackKingSide, .blackQueenSide])
            }
        }

        if movingPiece.kind == .rook {
            removeCastlingRight(forRookAt: from)
        }
        if capturedPiece?.kind == .rook {
            removeCastlingRight(forRookAt: capturedAt)
        }
    }

    private mutating func removeCastlingRight(forRookAt square: Square) {
        switch (square.file, square.rank) {
        case (0, 0): castlingRights.remove(.whiteQueenSide)
        case (7, 0): castlingRights.remove(.whiteKingSide)
        case (0, 7): castlingRights.remove(.blackQueenSide)
        case (7, 7): castlingRights.remove(.blackKingSide)
        default: break
        }
    }

    public var fen: String {
        let board = (0..<8).reversed().map { rank -> String in
            var row = ""
            var emptyCount = 0
            for file in 0..<8 {
                guard let square = Square(file: file, rank: rank) else { continue }
                if let piece = pieces[square] {
                    if emptyCount > 0 {
                        row += String(emptyCount)
                        emptyCount = 0
                    }
                    row.append(piece.fenSymbol)
                } else {
                    emptyCount += 1
                }
            }
            if emptyCount > 0 { row += String(emptyCount) }
            return row
        }.joined(separator: "/")

        let turn = sideToMove == .white ? "w" : "b"
        let fullMove = max(1, plyCount / 2 + 1)
        let enPassant = enPassantTarget?.notation ?? "-"
        return "\(board) \(turn) \(castlingRights.fen) \(enPassant) \(halfmoveClock) \(fullMove)"
    }
}
