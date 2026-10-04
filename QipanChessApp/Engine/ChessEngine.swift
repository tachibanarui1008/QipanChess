import Foundation
import GameCore

public struct EnginePositionHistory: Equatable, Sendable {
    public let initialFEN: String
    public let moves: [Move]
    public init(initialFEN: String, moves: [Move]) { self.initialFEN = initialFEN; self.moves = moves }
}

public struct EngineWDL: Equatable, Sendable {
    public let wins: Int
    public let draws: Int
    public let losses: Int
    public init?(wins: Int, draws: Int, losses: Int) {
        guard wins >= 0, draws >= 0, losses >= 0, wins + draws + losses > 0 else { return nil }
        self.wins = wins; self.draws = draws; self.losses = losses
    }
    public var expectedPoints: Double { (Double(wins) + 0.5 * Double(draws)) / Double(wins + draws + losses) }
}

public struct AnalysisLimit: Equatable, Sendable {
    public let depth: Int
    public let multiPV: Int
    public let rootMoves: [Move]
    public let history: EnginePositionHistory?

    public init(depth: Int = 16, multiPV: Int = 1, rootMoves: [Move] = [], history: EnginePositionHistory? = nil) {
        self.depth = depth
        self.multiPV = max(1, multiPV)
        self.rootMoves = rootMoves
        self.history = history
    }
}

public enum EngineScore: Equatable, Sendable {
    case centipawns(Int)
    case mate(Int)
}

public struct EngineVariation: Equatable, Sendable, Identifiable {
    public let rank: Int
    public let score: EngineScore
    public let depth: Int
    public let principalVariation: [Move]
    public let winProbability: Double?
    public let wdl: EngineWDL?

    public init(
        rank: Int,
        score: EngineScore,
        depth: Int,
        principalVariation: [Move],
        winProbability: Double? = nil,
        wdl: EngineWDL? = nil
    ) {
        self.rank = rank
        self.score = score
        self.depth = depth
        self.principalVariation = principalVariation
        self.winProbability = winProbability
        self.wdl = wdl
    }

    public var id: Int { rank }
}

public struct EngineResult: Equatable, Sendable {
    public let score: EngineScore
    public let depth: Int
    public let bestMove: Move?
    public let principalVariation: [Move]
    public let elapsedMilliseconds: Int
    public let nodes: Int
    public let variations: [EngineVariation]

    public init(
        score: EngineScore,
        depth: Int,
        bestMove: Move?,
        principalVariation: [Move],
        elapsedMilliseconds: Int,
        nodes: Int,
        variations: [EngineVariation] = []
    ) {
        self.score = score
        self.depth = depth
        self.bestMove = bestMove
        self.principalVariation = principalVariation
        self.elapsedMilliseconds = elapsedMilliseconds
        self.nodes = nodes
        self.variations = variations
    }
}

public enum ChessEngineError: LocalizedError, Sendable {
    case executableNotConfigured
    case executableNotRunnable(String)
    case failedToLaunch(String)
    case unexpectedEndOfOutput
    case noAnalysisResult
    case embeddedResourcesMissing
    case embeddedEngineFailed(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotConfigured:
            "没有在 App 中找到 Stockfish 引擎文件。"
        case .executableNotRunnable(let path):
            "Stockfish 引擎不可执行：\(path)"
        case .failedToLaunch(let message):
            "Stockfish 启动失败：\(message)"
        case .unexpectedEndOfOutput:
            "Stockfish 输出意外结束。"
        case .noAnalysisResult:
            "Stockfish 没有返回有效分析结果。"
        case .embeddedResourcesMissing:
            "App 中缺少 iOS/iPadOS Stockfish 所需的 NNUE 模型文件。"
        case .embeddedEngineFailed(let message):
            "iOS/iPadOS 内嵌 Stockfish 分析失败：\(message)"
        }
    }
}

public protocol ChessEngine: AnyObject {
    var name: String { get }
    func start() async throws
    func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult
    func stop() async
}

public enum PlatformEngineFactory {
    public static func makeDefaultEngine() -> (any ChessEngine)? {
        #if os(macOS)
        StockfishProcessEngine(executableURL: StockfishLocator.locate())
        #elseif os(iOS)
        EmbeddedEngineAdapter(bridge: StockfishEmbeddedBridge())
        #else
        nil
        #endif
    }
}

public enum PlatformEngineEndpoint {
    public static var unavailableDescription: String {
        #if os(macOS)
        "没有在 App 资源中找到 Stockfish。"
        #elseif os(iOS)
        "iPhone/iPad 内嵌 Stockfish 暂时不可用。"
        #else
        "当前平台尚未配置引擎。"
        #endif
    }
}

#if os(macOS)
enum StockfishLocator {
    static func locate(bundle: Bundle = .main) -> URL? {
        let resources = bundle.resourceURL
        let candidates: [URL?] = [
            bundle.url(forResource: "stockfish", withExtension: nil, subdirectory: "Engines"),
            resources?.appendingPathComponent("Engines/stockfish"),
            resources?.appendingPathComponent("Resources/Engines/stockfish"),
            bundle.url(forResource: "stockfish", withExtension: nil),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Engines/stockfish")
        ]
        return candidates.compactMap { $0 }.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        })
    }
}
#endif
