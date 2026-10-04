import Foundation
import GameCore

public struct OpeningCurationDecision: Equatable, Sendable {
    public let favoredSide: PieceColor?
    public let remove: Bool
    public let evaluated: Bool
    public static func evaluate(reviews: [ReviewedMove], plies: Int, isResearch: Bool, hasNotes: Bool) -> Self {
        let rows = reviews.filter { $0.index > 0 && $0.index <= plies && $0.depth >= 14 }
        let complete = plies >= 8 && Set(rows.map(\.index)).count == plies
        let whiteErrors = rows.filter { $0.side == .white && $0.loss >= 0.10 }.count
        let blackErrors = rows.filter { $0.side == .black && $0.loss >= 0.10 }.count
        let remove = complete && !isResearch && !hasNotes && whiteErrors >= 2 && blackErrors >= 2
        guard complete, let last = rows.first(where: { $0.index == plies }) else {
            return Self(favoredSide: nil, remove: remove, evaluated: false)
        }
        let score = last.whiteEvaluation
        return Self(favoredSide: score >= 0.5 ? .white : (score <= -0.5 ? .black : nil), remove: remove, evaluated: true)
    }
}
public struct OpeningCurationState: Codable, Sendable {
    public var version = 1
    public var excludedSourceIDs: Set<String> = []
    public var removedRoutes = 0
    public var whiteRoutes = 0
    public var blackRoutes = 0
    public var unclassifiedRoutes = 0
    public var backupPath = ""
    public var originalTreeIDs: Set<UUID>? = nil
}
