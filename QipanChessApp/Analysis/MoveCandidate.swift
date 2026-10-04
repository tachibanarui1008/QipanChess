import Foundation
import Engine
import GameCore

/// One root move; opponent continuations stay inside the engine search.
public struct MoveCandidate: Equatable, Identifiable, Sendable {
    public let rank: Int
    public let move: Move
    public let san: String
    public let quality: ReviewQuality
    public let loss: Double
    public let score: String
    public let depth: Int
    public var id: Move { move }

    static func make(result: EngineResult, position: GamePosition) -> [MoveCandidate] {
        let variations = result.variations.sorted { $0.rank < $1.rank }
        guard let best = variations.first else { return [] }
        let baseline = GameReviewCoordinator.expectedPoints(score: best.score, wdl: best.wdl)
        let legal = Set(MoveGenerator.allLegalMoves(for: position.sideToMove, in: position))
        var seen: Set<Move> = []
        return variations.compactMap { variation -> MoveCandidate? in
            guard let move = variation.principalVariation.first, legal.contains(move), seen.insert(move).inserted,
                  variation.depth == best.depth else { return nil }
            let loss = max(0, baseline - GameReviewCoordinator.expectedPoints(score: variation.score, wdl: variation.wdl))
            var quality = ReviewQuality.classify(loss: loss, isBest: variation.rank == best.rank)
            if case .mate(let mate) = variation.score, mate < 0 {
                if case .mate(let bestMate) = best.score, bestMate < 0 {} else { quality = .blunder }
            } else if case .mate(let mate) = best.score, mate > 0, variation.rank != best.rank {
                if case .mate(let other) = variation.score, other > 0 {} else { quality = .miss }
            }
            return MoveCandidate(rank: variation.rank, move: move, san: SAN.string(for: move, in: position),
                quality: quality, loss: loss, score: ReviewScore(variation.score).text, depth: variation.depth)
        }.prefix(3).map { $0 }
    }
}
