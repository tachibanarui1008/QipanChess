import Engine
import Foundation
import GameCore

enum EngineAnalysisAdapter {
    static func make(
        result: EngineResult,
        position: GamePosition,
        engineName: String,
        strategyOverride: StrategyType? = nil
    ) -> PositionAnalysis {
        let advantage = normalize(result.score, sideToMove: position.sideToMove)
        let principalVariation = result.principalVariation
        let currentMove = result.bestMove ?? principalVariation.first
        let reply = principalVariation.count > 1 ? principalVariation[1] : nil
        let continuation = principalVariation.count > 2
            ? Array(principalVariation.dropFirst(2).prefix(4))
            : []
        let strategies: [ChessStrategy]
        if let strategyOverride,
           let strategy = StrategyClassifier.singleStrategy(
               type: strategyOverride,
               result: result,
               position: position
           ) {
            strategies = [strategy]
        } else {
            strategies = StrategyClassifier.classify(
                result: result,
                position: position
            )
        }

        return PositionAnalysis(
            evaluation: PositionEvaluation(
                advantage: advantage,
                depth: result.depth,
                sourceName: engineName
            ),
            bestLine: BestLine(
                currentSide: position.sideToMove,
                currentMove: currentMove,
                bestReply: reply,
                continuation: continuation
            ),
            controlMap: ControlMap(position: position),
            state: .ready,
            engineName: engineName,
            elapsedMilliseconds: result.elapsedMilliseconds,
            nodes: result.nodes,
            strategies: strategies,
            candidates: MoveCandidate.make(result: result, position: position)
        )
    }

    private static func normalize(
        _ score: EngineScore,
        sideToMove: PieceColor
    ) -> PositionAdvantage {
        switch score {
        case .centipawns(let value):
            let magnitude = abs(Double(value)) / 100
            guard magnitude >= 0.15 else { return .balanced }
            let favoredSide = value >= 0 ? sideToMove : sideToMove.opposite
            return .side(favoredSide, magnitude: magnitude)
        case .mate(let moves):
            let favoredSide = moves >= 0 ? sideToMove : sideToMove.opposite
            return .mate(favoredSide, moves: abs(moves))
        }
    }
}
