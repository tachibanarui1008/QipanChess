import Foundation

public enum MoveGenerator {
    private static let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
    private static let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
    private static let knightOffsets = [
        (1, 2), (2, 1), (2, -1), (1, -2),
        (-1, -2), (-2, -1), (-2, 1), (-1, 2)
    ]

    public static func legalMoves(from square: Square, in position: GamePosition) -> [Move] {
        guard let piece = position[square] else { return [] }
        return pseudoLegalMoves(from: square, piece: piece, in: position)
            .filter { move in
                var resultingPosition = position
                resultingPosition.make(move)
                return !isKingInCheck(piece.color, in: resultingPosition)
            }
            .sorted { lhs, rhs in
                lhs.to == rhs.to
                    ? (lhs.promotion?.rawValue ?? "") < (rhs.promotion?.rawValue ?? "")
                    : lhs.to < rhs.to
            }
    }

    public static func allLegalMoves(for color: PieceColor, in position: GamePosition) -> [Move] {
        position.pieces
            .filter { $0.value.color == color }
            .keys
            .sorted()
            .flatMap { legalMoves(from: $0, in: position) }
    }

    public static func isKingInCheck(_ color: PieceColor, in position: GamePosition) -> Bool {
        guard let kingSquare = position.pieces.first(where: {
            $0.value.color == color && $0.value.kind == .king
        })?.key else { return false }
        return isSquareAttacked(kingSquare, by: color.opposite, in: position)
    }

    public static func isCheckmate(for color: PieceColor, in position: GamePosition) -> Bool {
        isKingInCheck(color, in: position) && allLegalMoves(for: color, in: position).isEmpty
    }

    public static func isStalemate(for color: PieceColor, in position: GamePosition) -> Bool {
        !isKingInCheck(color, in: position) && allLegalMoves(for: color, in: position).isEmpty
    }

    public static func controlledSquares(by color: PieceColor, in position: GamePosition) -> [Square: Int] {
        var counts: [Square: Int] = [:]

        for (square, piece) in position.pieces where piece.color == color {
            let targets = attackTargets(from: square, piece: piece, in: position)
            for target in targets {
                counts[target, default: 0] += 1
            }
        }
        return counts
    }

    public static func isSquareAttacked(
        _ square: Square,
        by color: PieceColor,
        in position: GamePosition
    ) -> Bool {
        position.pieces.contains { origin, piece in
            piece.color == color && attackTargets(from: origin, piece: piece, in: position).contains(square)
        }
    }

    private static func pseudoLegalMoves(
        from square: Square,
        piece: Piece,
        in position: GamePosition
    ) -> [Move] {
        switch piece.kind {
        case .pawn:
            pawnMoves(from: square, piece: piece, in: position)
        case .knight:
            jumpTargets(from: square, offsets: knightOffsets, color: piece.color, in: position)
                .map { Move(from: square, to: $0) }
        case .bishop:
            slidingTargets(from: square, directions: bishopDirections, color: piece.color, in: position)
                .map { Move(from: square, to: $0) }
        case .rook:
            slidingTargets(from: square, directions: rookDirections, color: piece.color, in: position)
                .map { Move(from: square, to: $0) }
        case .queen:
            slidingTargets(
                from: square,
                directions: rookDirections + bishopDirections,
                color: piece.color,
                in: position
            ).map { Move(from: square, to: $0) }
        case .king:
            kingMoves(from: square, piece: piece, in: position)
        }
    }

    private static func pawnMoves(from square: Square, piece: Piece, in position: GamePosition) -> [Move] {
        let direction = piece.color == .white ? 1 : -1
        let startingRank = piece.color == .white ? 1 : 6
        let promotionRank = piece.color == .white ? 7 : 0
        var targets: [Square] = []

        if let oneStep = square.offset(file: 0, rank: direction), position[oneStep] == nil {
            targets.append(oneStep)
            if square.rank == startingRank,
               let twoSteps = square.offset(file: 0, rank: direction * 2),
               position[twoSteps] == nil {
                targets.append(twoSteps)
            }
        }

        for fileDelta in [-1, 1] {
            guard let capture = square.offset(file: fileDelta, rank: direction) else { continue }
            if let target = position[capture], target.color != piece.color {
                targets.append(capture)
            } else if capture == position.enPassantTarget,
                      let pawnSquare = capture.offset(file: 0, rank: -direction),
                      let pawn = position[pawnSquare],
                      pawn.color != piece.color,
                      pawn.kind == .pawn {
                targets.append(capture)
            }
        }

        return targets.map { target in
            Move(
                from: square,
                to: target,
                promotion: target.rank == promotionRank ? .queen : nil
            )
        }
    }

    private static func kingMoves(from square: Square, piece: Piece, in position: GamePosition) -> [Move] {
        var moves = jumpTargets(
            from: square,
            offsets: rookDirections + bishopDirections,
            color: piece.color,
            in: position
        ).map { Move(from: square, to: $0) }

        guard !isKingInCheck(piece.color, in: position) else { return moves }
        let homeRank = piece.color == .white ? 0 : 7
        guard square == Square(file: 4, rank: homeRank) else { return moves }

        if position.castlingRights.containsKingSide(for: piece.color),
           let rookSquare = Square(file: 7, rank: homeRank),
           position[rookSquare] == Piece(color: piece.color, kind: .rook),
           let transit = Square(file: 5, rank: homeRank),
           let destination = Square(file: 6, rank: homeRank),
           position[transit] == nil,
           position[destination] == nil,
           !isSquareAttacked(transit, by: piece.color.opposite, in: position),
           !isSquareAttacked(destination, by: piece.color.opposite, in: position) {
            moves.append(Move(from: square, to: destination))
        }

        if position.castlingRights.containsQueenSide(for: piece.color),
           let rookSquare = Square(file: 0, rank: homeRank),
           position[rookSquare] == Piece(color: piece.color, kind: .rook),
           let betweenRook = Square(file: 1, rank: homeRank),
           let destination = Square(file: 2, rank: homeRank),
           let transit = Square(file: 3, rank: homeRank),
           position[betweenRook] == nil,
           position[destination] == nil,
           position[transit] == nil,
           !isSquareAttacked(transit, by: piece.color.opposite, in: position),
           !isSquareAttacked(destination, by: piece.color.opposite, in: position) {
            moves.append(Move(from: square, to: destination))
        }

        return moves
    }

    private static func attackTargets(from square: Square, piece: Piece, in position: GamePosition) -> [Square] {
        switch piece.kind {
        case .pawn:
            let direction = piece.color == .white ? 1 : -1
            return [-1, 1].compactMap { square.offset(file: $0, rank: direction) }
        case .knight:
            return knightOffsets.compactMap { square.offset(file: $0.0, rank: $0.1) }
        case .bishop:
            return slidingControls(from: square, directions: bishopDirections, in: position)
        case .rook:
            return slidingControls(from: square, directions: rookDirections, in: position)
        case .queen:
            return slidingControls(from: square, directions: rookDirections + bishopDirections, in: position)
        case .king:
            return (rookDirections + bishopDirections).compactMap { square.offset(file: $0.0, rank: $0.1) }
        }
    }

    private static func jumpTargets(
        from square: Square,
        offsets: [(Int, Int)],
        color: PieceColor,
        in position: GamePosition
    ) -> [Square] {
        offsets.compactMap { fileDelta, rankDelta in
            guard let target = square.offset(file: fileDelta, rank: rankDelta),
                  position[target]?.color != color
            else { return nil }
            return target
        }
    }

    private static func slidingTargets(
        from square: Square,
        directions: [(Int, Int)],
        color: PieceColor,
        in position: GamePosition
    ) -> [Square] {
        var targets: [Square] = []
        for (fileDelta, rankDelta) in directions {
            var cursor = square.offset(file: fileDelta, rank: rankDelta)
            while let target = cursor {
                if let occupant = position[target] {
                    if occupant.color != color { targets.append(target) }
                    break
                }
                targets.append(target)
                cursor = target.offset(file: fileDelta, rank: rankDelta)
            }
        }
        return targets
    }

    private static func slidingControls(
        from square: Square,
        directions: [(Int, Int)],
        in position: GamePosition
    ) -> [Square] {
        var targets: [Square] = []
        for (fileDelta, rankDelta) in directions {
            var cursor = square.offset(file: fileDelta, rank: rankDelta)
            while let target = cursor {
                targets.append(target)
                if position[target] != nil { break }
                cursor = target.offset(file: fileDelta, rank: rankDelta)
            }
        }
        return targets
    }
}
