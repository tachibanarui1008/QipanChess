import Foundation
import GameCore

public struct AnalysisLimit: Equatable, Sendable {
    public let depth: Int

    public init(depth: Int = 16) {
        self.depth = depth
    }
}

public enum EngineScore: Equatable, Sendable {
    case centipawns(Int)
    case mate(Int)
}

public struct EngineResult: Equatable, Sendable {
    public let score: EngineScore
    public let depth: Int
    public let bestMove: Move?
    public let principalVariation: [Move]
    public let elapsedMilliseconds: Int
    public let nodes: Int

    public init(
        score: EngineScore,
        depth: Int,
        bestMove: Move?,
        principalVariation: [Move],
        elapsedMilliseconds: Int,
        nodes: Int
    ) {
        self.score = score
        self.depth = depth
        self.bestMove = bestMove
        self.principalVariation = principalVariation
        self.elapsedMilliseconds = elapsedMilliseconds
        self.nodes = nodes
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
