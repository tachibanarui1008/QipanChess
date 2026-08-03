import Combine
import Foundation

@MainActor
public final class GameSession: ObservableObject {
    @Published public private(set) var position: GamePosition
    @Published public private(set) var selectedSquare: Square?
    @Published public private(set) var legalTargets: Set<Square>
    @Published public private(set) var lastMove: Move?
    @Published public var showsControlHeatmap = false
    @Published public var showsBestLineOnBoard = false

    public init(position: GamePosition = .starting) {
        self.position = position
        self.selectedSquare = nil
        self.legalTargets = []
        self.lastMove = nil
    }

    public func select(_ square: Square) {
        if let selectedSquare, legalTargets.contains(square) {
            make(Move(from: selectedSquare, to: square))
            return
        }

        guard let piece = position[square], piece.color == position.sideToMove else {
            clearSelection()
            return
        }

        selectedSquare = square
        legalTargets = Set(MoveGenerator.legalMoves(from: square, in: position).map(\.to))
    }

    public func reset() {
        position = .starting
        lastMove = nil
        clearSelection()
    }

    private func make(_ move: Move) {
        position.make(move)
        lastMove = move
        clearSelection()
    }

    private func clearSelection() {
        selectedSquare = nil
        legalTargets = []
    }
}
