import Engine
import Foundation
import GameCore

public enum StrategyType: String, CaseIterable, Identifiable, Sendable {
    case aggressive
    case balanced
    case conservative

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .aggressive: "激进路线"
        case .balanced: "稳健路线"
        case .conservative: "保守路线"
        }
    }

    public var shortName: String {
        switch self {
        case .aggressive: "攻"
        case .balanced: "稳"
        case .conservative: "守"
        }
    }
}

public enum StrategyRiskLevel: String, Sendable {
    case high
    case medium
    case low

    public var displayName: String {
        switch self {
        case .high: "高"
        case .medium: "中"
        case .low: "低"
        }
    }
}

public struct ChessStrategy: Identifiable, Equatable, Sendable {
    public let type: StrategyType
    public let firstMove: Move
    public let secondMove: Move?
    public let evaluation: PositionAdvantage
    public let evaluationDelta: Double
    public let riskLevel: StrategyRiskLevel
    public let riskScore: Double
    public let winProbability: Double?
    public let principalVariation: [Move]
    public let engineRank: Int
    public let depth: Int
    public let summary: String

    public init(
        type: StrategyType,
        firstMove: Move,
        secondMove: Move?,
        evaluation: PositionAdvantage,
        evaluationDelta: Double,
        riskLevel: StrategyRiskLevel,
        riskScore: Double,
        winProbability: Double?,
        principalVariation: [Move],
        engineRank: Int,
        depth: Int,
        summary: String
    ) {
        self.type = type
        self.firstMove = firstMove
        self.secondMove = secondMove
        self.evaluation = evaluation
        self.evaluationDelta = evaluationDelta
        self.riskLevel = riskLevel
        self.riskScore = riskScore
        self.winProbability = winProbability
        self.principalVariation = principalVariation
        self.engineRank = engineRank
        self.depth = depth
        self.summary = summary
    }

    public var id: StrategyType { type }
}

enum StrategyClassifier {
    /// 不调用引擎，直接从全部合法着法中按棋风规则选出唯一根着法。
    /// 后续只需要让 Stockfish 沿这一个着法计算对手回应。
    static func preferredMove(
        for type: StrategyType,
        in position: GamePosition
    ) -> Move? {
        let candidates = MoveGenerator.allLegalMoves(
            for: position.sideToMove,
            in: position
        ).enumerated().compactMap { index, move in
            Candidate(
                variation: EngineVariation(
                    rank: index + 1,
                    score: .centipawns(0),
                    depth: 0,
                    principalVariation: [move]
                ),
                position: position
            )
        }

        switch type {
        case .aggressive:
            return candidates.max { $0.aggressionScore < $1.aggressionScore }?.firstMove
        case .balanced:
            return nil
        case .conservative:
            return candidates.max { $0.safetyScore < $1.safetyScore }?.firstMove
        }
    }

    static func singleStrategy(
        type: StrategyType,
        result: EngineResult,
        position: GamePosition
    ) -> ChessStrategy? {
        guard let variation = normalizedVariations(from: result).first,
              let candidate = Candidate(variation: variation, position: position)
        else { return nil }

        return makeStrategy(
            type: type,
            candidate: candidate,
            bestValue: scoreValue(variation.score),
            position: position
        )
    }

    static func classify(
        result: EngineResult,
        position: GamePosition
    ) -> [ChessStrategy] {
        let variations = normalizedVariations(from: result)
        let candidates = variations
            .prefix(8)
            .compactMap { Candidate(variation: $0, position: position) }

        guard let balanced = candidates.min(by: { $0.variation.rank < $1.variation.rank }) else {
            return []
        }

        let withoutBalanced = candidates.filter { $0.firstMove != balanced.firstMove }
        let aggressive = withoutBalanced.max { lhs, rhs in
            lhs.aggressionScore < rhs.aggressionScore
        }
        let withoutAggressive = withoutBalanced.filter {
            $0.firstMove != aggressive?.firstMove
        }
        let conservative = withoutAggressive.max { lhs, rhs in
            lhs.safetyScore < rhs.safetyScore
        }
        let bestValue = scoreValue(balanced.variation.score)

        let assignments: [(StrategyType, Candidate?)] = [
            (.aggressive, aggressive),
            (.balanced, balanced),
            (.conservative, conservative)
        ]

        return assignments.compactMap { type, candidate in
            guard let candidate else { return nil }
            return makeStrategy(
                type: type,
                candidate: candidate,
                bestValue: bestValue,
                position: position
            )
        }
    }

    private static func makeStrategy(
        type: StrategyType,
        candidate: Candidate,
        bestValue: Double,
        position: GamePosition
    ) -> ChessStrategy {
        let riskLevel: StrategyRiskLevel = switch type {
        case .aggressive: .high
        case .balanced: .medium
        case .conservative: .low
        }
        let rawRisk = switch type {
        case .aggressive:
            0.68 + min(candidate.aggressionScore / 18, 0.30)
        case .balanced:
            0.45 + min(candidate.tacticalVolatility / 20, 0.18)
        case .conservative:
            0.30 - min(candidate.safetyScore / 40, 0.18)
        }

        return ChessStrategy(
            type: type,
            firstMove: candidate.firstMove,
            secondMove: candidate.reply,
            evaluation: normalizedAdvantage(
                candidate.variation.score,
                sideToMove: position.sideToMove
            ),
            evaluationDelta: clampedEvaluationDelta(
                scoreValue(candidate.variation.score) - bestValue
            ),
            riskLevel: riskLevel,
            riskScore: min(max(rawRisk, 0.08), 0.98),
            winProbability: candidate.variation.winProbability,
            principalVariation: candidate.variation.principalVariation,
            engineRank: candidate.variation.rank,
            depth: candidate.variation.depth,
            summary: candidate.summary(for: type)
        )
    }

    private static func normalizedVariations(from result: EngineResult) -> [EngineVariation] {
        if !result.variations.isEmpty {
            return result.variations.sorted { $0.rank < $1.rank }
        }
        guard !result.principalVariation.isEmpty else { return [] }
        return [EngineVariation(
            rank: 1,
            score: result.score,
            depth: result.depth,
            principalVariation: result.principalVariation
        )]
    }

    private static func normalizedAdvantage(
        _ score: EngineScore,
        sideToMove: PieceColor
    ) -> PositionAdvantage {
        switch score {
        case .centipawns(let value):
            let magnitude = abs(Double(value)) / 100
            guard magnitude >= 0.15 else { return .balanced }
            return .side(value >= 0 ? sideToMove : sideToMove.opposite, magnitude: magnitude)
        case .mate(let moves):
            return .mate(moves >= 0 ? sideToMove : sideToMove.opposite, moves: abs(moves))
        }
    }

    private static func scoreValue(_ score: EngineScore) -> Double {
        switch score {
        case .centipawns(let value): Double(value) / 100
        case .mate(let moves): moves >= 0 ? 100 : -100
        }
    }

    private static func clampedEvaluationDelta(_ value: Double) -> Double {
        min(max(value, -9.99), 9.99)
    }
}

private struct Candidate {
    let variation: EngineVariation
    let firstMove: Move
    let reply: Move?
    let givesCheck: Bool
    let sacrificeCost: Double
    let capturedValue: Double
    let kingPressureGain: Double
    let ownKingPressureReduction: Double
    let removesQueens: Bool
    let simplifies: Bool
    let castles: Bool
    let developsPiece: Bool
    let centralizes: Bool
    let advancesCenterPawn: Bool
    let aggressionScore: Double
    let safetyScore: Double
    let tacticalVolatility: Double

    init?(variation: EngineVariation, position: GamePosition) {
        guard let firstMove = variation.principalVariation.first,
              let movingPiece = position[firstMove.from]
        else { return nil }

        let reply = variation.principalVariation.dropFirst().first
        let firstCapturedPiece = Self.capturedPiece(for: firstMove, in: position)
        var afterFirst = position
        afterFirst.make(firstMove)
        let givesCheck = MoveGenerator.isKingInCheck(
            position.sideToMove.opposite,
            in: afterFirst
        )

        let pressureBefore = Self.kingPressure(
            on: position.sideToMove.opposite,
            by: position.sideToMove,
            in: position
        )
        let pressureAfter = Self.kingPressure(
            on: position.sideToMove.opposite,
            by: position.sideToMove,
            in: afterFirst
        )
        let ownPressureBefore = Self.kingPressure(
            on: position.sideToMove,
            by: position.sideToMove.opposite,
            in: position
        )
        let ownPressureAfter = Self.kingPressure(
            on: position.sideToMove,
            by: position.sideToMove.opposite,
            in: afterFirst
        )

        var replyCapturedPiece: Piece?
        var afterReply = afterFirst
        if let reply {
            replyCapturedPiece = Self.capturedPiece(for: reply, in: afterFirst)
            afterReply.make(reply)
        }

        let capturedValue = firstCapturedPiece.map(Self.pieceValue) ?? 0
        let replyCapturedValue = replyCapturedPiece.map(Self.pieceValue) ?? 0
        let movedPieceWasTaken = reply?.to == firstMove.to
            && replyCapturedPiece?.color == position.sideToMove
        let sacrificeCost = movedPieceWasTaken
            ? max(0, Self.pieceValue(movingPiece) - capturedValue)
            : 0
        let removesQueens = firstCapturedPiece?.kind == .queen
            || replyCapturedPiece?.kind == .queen
        let piecesRemoved = position.pieces.count - afterReply.pieces.count
        let simplifies = removesQueens || piecesRemoved >= 2
        let castles = movingPiece.kind == .king
            && abs(firstMove.to.file - firstMove.from.file) == 2
        let homeRank = movingPiece.color == .white ? 0 : 7
        let developsPiece = [.knight, .bishop].contains(movingPiece.kind)
            && firstMove.from.rank == homeRank
            && firstMove.to.rank != homeRank
        let centralizes = (2...5).contains(firstMove.to.file)
            && (2...5).contains(firstMove.to.rank)
        let advancesCenterPawn = movingPiece.kind == .pawn
            && [3, 4].contains(firstMove.from.file)
            && abs(firstMove.to.rank - firstMove.from.rank) >= 1
        let centerPawnAdvanceDistance = advancesCenterPawn
            ? abs(firstMove.to.rank - firstMove.from.rank)
            : 0
        let kingPressureGain = Double(max(0, pressureAfter - pressureBefore))
        let ownKingPressureReduction = Double(max(0, ownPressureBefore - ownPressureAfter))

        let tacticalVolatility = sacrificeCost * 2.2
            + replyCapturedValue
            + (givesCheck ? 3.0 : 0)
            + kingPressureGain
        let aggressionScore = (givesCheck ? 5.0 : 0)
            + sacrificeCost * 1.35
            + capturedValue * 0.30
            + kingPressureGain * 1.25
            + (centralizes ? 0.8 : 0)
            + (centerPawnAdvanceDistance == 2 ? 3.2 : (advancesCenterPawn ? 1.2 : 0))
            + (advancesCenterPawn && firstMove.from.file == 4 ? 0.25 : 0)
            + (developsPiece ? 0.7 : 0)
            + (firstMove.promotion != nil ? 5.0 : 0)
        let safetyScore = (castles ? 6.0 : 0)
            + (removesQueens ? 4.0 : 0)
            + (simplifies ? 2.2 : 0)
            + ownKingPressureReduction * 1.35
            + (sacrificeCost == 0 ? 1.5 : -sacrificeCost)
            + (developsPiece ? 0.8 : 0)
            - (givesCheck ? 0.5 : 0)

        self.variation = variation
        self.firstMove = firstMove
        self.reply = reply
        self.givesCheck = givesCheck
        self.sacrificeCost = sacrificeCost
        self.capturedValue = capturedValue
        self.kingPressureGain = kingPressureGain
        self.ownKingPressureReduction = ownKingPressureReduction
        self.removesQueens = removesQueens
        self.simplifies = simplifies
        self.castles = castles
        self.developsPiece = developsPiece
        self.centralizes = centralizes
        self.advancesCenterPawn = advancesCenterPawn
        self.aggressionScore = aggressionScore
        self.safetyScore = safetyScore
        self.tacticalVolatility = tacticalVolatility
    }

    func summary(for type: StrategyType) -> String {
        switch type {
        case .aggressive:
            if sacrificeCost > 0.5 { return "以子力换取主动，需要精确计算后续。" }
            if givesCheck { return "直接制造将军，迫使对手立即回应。" }
            if kingPressureGain > 0 { return "增加王区压力，争取战术机会。" }
            if capturedValue > 0 { return "主动进入交换，争取节奏和子力收益。" }
            return "主动争夺空间与节奏，局面变化较多。"
        case .balanced:
            return "Stockfish 当前首选，兼顾评价、发展与局面稳定性。"
        case .conservative:
            if castles { return "优先完成王的安全部署，降低被攻击风险。" }
            if removesQueens { return "主动简化后翼重子，减少战术波动。" }
            if simplifies { return "通过交换降低局面复杂度，便于控制。" }
            if ownKingPressureReduction > 0 { return "缓解己方王区压力，保持结构完整。" }
            if developsPiece { return "稳妥完成出子，不制造额外结构弱点。" }
            return "保持结构和退路，降低下一回合的战术风险。"
        }
    }

    private static func capturedPiece(for move: Move, in position: GamePosition) -> Piece? {
        if let piece = position[move.to] { return piece }
        guard let movingPiece = position[move.from],
              movingPiece.kind == .pawn,
              move.from.file != move.to.file,
              move.to == position.enPassantTarget,
              let capturedSquare = move.to.offset(
                file: 0,
                rank: movingPiece.color == .white ? -1 : 1
              )
        else { return nil }
        return position[capturedSquare]
    }

    private static func pieceValue(_ piece: Piece) -> Double {
        switch piece.kind {
        case .pawn: 1
        case .knight: 3.2
        case .bishop: 3.3
        case .rook: 5
        case .queen: 9
        case .king: 20
        }
    }

    private static func kingPressure(
        on kingColor: PieceColor,
        by attackingColor: PieceColor,
        in position: GamePosition
    ) -> Int {
        guard let kingSquare = position.pieces.first(where: {
            $0.value.color == kingColor && $0.value.kind == .king
        })?.key else { return 0 }

        let controlled = MoveGenerator.controlledSquares(by: attackingColor, in: position)
        var zone = [kingSquare]
        for fileDelta in -1...1 {
            for rankDelta in -1...1 where fileDelta != 0 || rankDelta != 0 {
                if let square = kingSquare.offset(file: fileDelta, rank: rankDelta) {
                    zone.append(square)
                }
            }
        }
        return zone.reduce(0) { $0 + controlled[$1, default: 0] }
    }
}
