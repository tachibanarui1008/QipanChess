import Combine
import Foundation

@MainActor
public final class GameSession: ObservableObject {
    @Published public private(set) var position: GamePosition
    @Published public private(set) var selectedSquare: Square?
    @Published public private(set) var legalTargets: Set<Square> = []
    @Published public private(set) var lastMove: Move?
    @Published public private(set) var moveHistory: [Move] = []
    @Published public private(set) var record: GameRecord
    @Published public private(set) var pendingPromotions: [Move] = []
    @Published public var showsControlHeatmap = false
    @Published public var showsBestLineOnBoard = false
    @Published public var isBoardFlipped = false
    public var moveFilter: ((Move) -> Bool)?
    private var positionHistory: [GamePosition]

    public init(position: GamePosition = .starting) {
        self.position = position
        self.record = GameRecord(position: position)
        self.positionHistory = [position]
    }
    public var cursor: Int { record.cursor }
    public var canUndo: Bool { cursor > 0 }
    public var canRedo: Bool { cursor < record.moves.count }
    public var allPositions: [GamePosition] { positionHistory }
    public var isBrowsing: Bool { canRedo }

    public var outcome: String? {
        if MoveGenerator.isCheckmate(for: position.sideToMove, in: position) {
            return position.sideToMove == .white ? "黑方将杀获胜" : "白方将杀获胜"
        }
        if MoveGenerator.isStalemate(for: position.sideToMove, in: position) { return "逼和" }
        if position.hasInsufficientMaterial { return "子力不足，和棋" }
        if position.halfmoveClock >= 150 { return "七十五回合规则，和棋" }
        if repetitionCount >= 5 { return "五次重复，和棋" }
        if !canRedo, record.tags["Result"] != "*" {
            switch record.tags["Result"] {
            case "1-0": return "白方获胜"
            case "0-1": return "黑方获胜"
            case "1/2-1/2": return "和棋"
            default: break
            }
        }
        return nil
    }
    public var canClaimDraw: Bool { outcome == nil && (position.halfmoveClock >= 100 || repetitionCount >= 3) }
    private var repetitionCount: Int {
        let key = position.repetitionKey
        return positionHistory.prefix(cursor + 1).filter { $0.repetitionKey == key }.count
    }
    public func claimDraw() {
        guard canClaimDraw, !isBrowsing else { return }
        record.tags["Result"] = "1/2-1/2"; record.updatedAt = Date()
    }
    public func select(_ square: Square) {
        if let selectedSquare, legalTargets.contains(square) {
            let moves = MoveGenerator.legalMoves(from: selectedSquare, in: position).filter { $0.to == square }
            if moves.count > 1 { pendingPromotions = moves }
            else if let move = moves.first { _ = make(move) }
            return
        }
        guard let piece = position[square], piece.color == position.sideToMove else { clearSelection(); return }
        selectedSquare = square
        legalTargets = Set(MoveGenerator.legalMoves(from: square, in: position).map(\.to))
    }
    public func reset() {
        position = .starting; record = GameRecord(); positionHistory = [.starting]
        moveHistory = []; lastMove = nil; clearSelection()
    }
    public func load(_ game: GameRecord) throws {
        let validated = try game.validated()
        let positions = try validated.positions()
        record = validated; positionHistory = positions
        synchronize()
    }
    public func seek(to index: Int) {
        guard (0...record.moves.count).contains(index) else { return }
        record.cursor = index
        synchronize()
    }
    public func undo() { if canUndo { seek(to: cursor - 1) } }
    public func redo() { if canRedo { seek(to: cursor + 1) } }
    public func setComment(_ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { record.comments.removeValue(forKey: cursor) }
        else { record.comments[cursor] = text }
        record.updatedAt = Date()
    }
    public func setPlayers(white: String, black: String) {
        record.tags["White"] = white; record.tags["Black"] = black; record.updatedAt = Date()
    }
    public func selectBranch(_ id: UUID) throws {
        guard let branch = record.branches.first(where: { $0.id == id }) else { return }
        var next = record
        next.branches.removeAll { $0.id == id }
        next.branches.append(GameBranch(name: "原路线", moves: record.moves, comments: record.comments))
        next.moves = branch.moves; next.comments = branch.comments; next.cursor = min(cursor, branch.moves.count)
        next.tags["Result"] = "*"; next.updatedAt = Date()
        try load(next)
    }
    @discardableResult
    public func make(_ move: Move) -> Bool {
        guard position[move.from]?.color == position.sideToMove,
              MoveGenerator.legalMoves(from: move.from, in: position).contains(move) else { return false }
        guard moveFilter?(move) != false else { clearSelection(); return false }
        // Following the recorded move navigates; deviating preserves the entire old line.
        if canRedo, record.moves[cursor] == move { redo(); return true }
        if canRedo {
            if !record.branches.contains(where: { $0.moves == record.moves }) {
                record.branches.append(GameBranch(name: "保留路线 \(record.branches.count + 1)", moves: record.moves, comments: record.comments))
            }
            record.moves = Array(record.moves.prefix(cursor))
            record.comments = record.comments.filter { $0.key <= cursor }
            positionHistory = Array(positionHistory.prefix(cursor + 1))
        }
        record.tags["Result"] = "*"
        position.make(move); positionHistory.append(position)
        record.moves.append(move); record.cursor += 1; record.updatedAt = Date()
        moveHistory = record.moves; lastMove = move; clearSelection()
        if let ending = outcome {
            record.tags["Result"] = ending.contains("白方将杀") ? "1-0" : ending.contains("黑方将杀") ? "0-1" : "1/2-1/2"
        }
        return true
    }
    public func cancelPromotion() { pendingPromotions = [] }
    private func synchronize() {
        position = positionHistory[cursor]; moveHistory = Array(record.moves.prefix(cursor))
        lastMove = moveHistory.last; clearSelection()
    }
    private func clearSelection() { selectedSquare = nil; legalTargets = []; pendingPromotions = [] }
}
