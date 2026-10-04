import Foundation
import GameCore

public enum PositionAdvantage: Equatable, Sendable {
    case balanced
    case side(PieceColor, magnitude: Double)
    case mate(PieceColor, moves: Int)

    public var favoredSide: PieceColor? {
        switch self {
        case .balanced: nil
        case .side(let color, _), .mate(let color, _): color
        }
    }

    public var magnitude: Double {
        switch self {
        case .balanced: 0
        case .side(_, let magnitude): magnitude
        case .mate: 10
        }
    }
}

public struct PositionEvaluation: Equatable, Sendable {
    public let advantage: PositionAdvantage
    public let depth: Int?
    public let sourceName: String

    public init(advantage: PositionAdvantage, depth: Int?, sourceName: String) {
        self.advantage = advantage
        self.depth = depth
        self.sourceName = sourceName
    }

    public static let placeholder = PositionEvaluation(
        advantage: .balanced,
        depth: nil,
        sourceName: "等待分析"
    )
}

public struct BestLine: Equatable, Sendable {
    public let currentSide: PieceColor
    public let currentMove: Move?
    public let bestReply: Move?
    public let continuation: [Move]

    public init(
        currentSide: PieceColor,
        currentMove: Move?,
        bestReply: Move?,
        continuation: [Move]
    ) {
        self.currentSide = currentSide
        self.currentMove = currentMove
        self.bestReply = bestReply
        self.continuation = continuation
    }
}

public enum AnalysisState: Equatable, Sendable {
    case idle
    case analyzing
    case ready
    case unavailable(String)
    case failed(String)
}

public struct ControlMap: Equatable, Sendable {
    public let white: [Square: Int]
    public let black: [Square: Int]

    public init(position: GamePosition) {
        self.white = MoveGenerator.controlledSquares(by: .white, in: position)
        self.black = MoveGenerator.controlledSquares(by: .black, in: position)
    }
}

public struct PositionAnalysis: Equatable, Sendable {
    public let evaluation: PositionEvaluation
    public let bestLine: BestLine
    public let controlMap: ControlMap
    public let state: AnalysisState
    public let engineName: String
    public let elapsedMilliseconds: Int?
    public let nodes: Int?
    public let candidates: [MoveCandidate]
    public let strategies: [ChessStrategy]

    public init(
        evaluation: PositionEvaluation,
        bestLine: BestLine,
        controlMap: ControlMap,
        state: AnalysisState,
        engineName: String,
        elapsedMilliseconds: Int?,
        nodes: Int?,
        strategies: [ChessStrategy] = [],
        candidates: [MoveCandidate] = []
    ) {
        self.evaluation = evaluation
        self.bestLine = bestLine
        self.controlMap = controlMap
        self.state = state
        self.engineName = engineName
        self.elapsedMilliseconds = elapsedMilliseconds
        self.nodes = nodes
        self.strategies = strategies
        self.candidates = candidates
    }

    public static func placeholder(
        position: GamePosition,
        state: AnalysisState = .idle,
        engineName: String = "分析引擎"
    ) -> PositionAnalysis {
        PositionAnalysis(
            evaluation: .placeholder,
            bestLine: BestLine(
                currentSide: position.sideToMove,
                currentMove: nil,
                bestReply: nil,
                continuation: []
            ),
            controlMap: ControlMap(position: position),
            state: state,
            engineName: engineName,
            elapsedMilliseconds: nil,
            nodes: nil,
            strategies: []
        )
    }
}
