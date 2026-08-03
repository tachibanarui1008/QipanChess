#if os(iOS)
import Foundation
import GameCore
import QipanStockfishBridge

/// 由 Stockfish C/C++ wrapper 或其他内嵌引擎实现。
public protocol EmbeddedEngineBridge: Sendable {
    var displayName: String { get }
    func start() async throws
    func analyze(fen: String, limit: AnalysisLimit) async throws -> EngineResult
    func stop() async
}

/// 将平台相关的内嵌桥接统一适配为应用层 `ChessEngine`。
public actor EmbeddedEngineAdapter: ChessEngine {
    public nonisolated let name: String
    private let bridge: any EmbeddedEngineBridge

    public init(bridge: any EmbeddedEngineBridge) {
        self.bridge = bridge
        self.name = bridge.displayName
    }

    public func start() async throws {
        try await bridge.start()
    }

    public func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        try await bridge.analyze(fen: position.fen, limit: limit)
    }

    public func stop() async {
        await bridge.stop()
    }
}

/// iOS/iPadOS 使用的 App 内嵌 Stockfish 18。
///
/// 与 macOS 版本不同，它不会启动子进程，而是通过 C API 在当前 App
/// 进程中调用静态链接的 Stockfish C++ 引擎。
public actor StockfishEmbeddedBridge: EmbeddedEngineBridge {
    public nonisolated let displayName = "Stockfish 18（内嵌）"

    private static let bigNetworkName = "nn-c288c895ea92"
    private static let smallNetworkName = "nn-37f18f62d772"
    private var context: OpaquePointer?

    public init() {}

    deinit {
        if let context {
            qipan_stockfish_destroy(context)
        }
    }

    public func start() async throws {
        if context != nil { return }

        guard let resourceURL = Bundle.main.resourceURL,
              Bundle.main.url(
                forResource: Self.bigNetworkName,
                withExtension: "nnue"
              ) != nil,
              Bundle.main.url(
                forResource: Self.smallNetworkName,
                withExtension: "nnue"
              ) != nil
        else {
            throw ChessEngineError.embeddedResourcesMissing
        }

        let virtualExecutable = resourceURL.appendingPathComponent("stockfish-mobile")
        context = virtualExecutable.path.withCString { path in
            qipan_stockfish_create(path)
        }

        guard context != nil else {
            throw ChessEngineError.embeddedEngineFailed("引擎初始化失败。")
        }
    }

    public func analyze(fen: String, limit: AnalysisLimit) async throws -> EngineResult {
        try await start()
        guard let context else {
            throw ChessEngineError.embeddedEngineFailed("引擎尚未启动。")
        }

        var nativeResult = QipanStockfishResult(
            scoreKind: 0,
            scoreValue: 0,
            depth: 0,
            elapsedMilliseconds: 0,
            nodes: 0
        )

        let status = fen.withCString { fenPointer in
            qipan_stockfish_analyze(
                context,
                fenPointer,
                Int32(limit.depth),
                &nativeResult
            )
        }

        guard status == 0 else {
            let message = qipan_stockfish_last_error(context).map(String.init(cString:))
                ?? "未知错误（\(status)）。"
            throw ChessEngineError.embeddedEngineFailed(message)
        }

        let bestMoveText = qipan_stockfish_best_move(context).map(String.init(cString:)) ?? ""
        let principalVariationText = qipan_stockfish_principal_variation(context)
            .map(String.init(cString:)) ?? ""
        let principalVariation = principalVariationText
            .split(separator: " ")
            .compactMap { Move(uci: String($0)) }

        let score: EngineScore = nativeResult.scoreKind == 1
            ? .mate(Int(nativeResult.scoreValue))
            : .centipawns(Int(nativeResult.scoreValue))

        return EngineResult(
            score: score,
            depth: Int(nativeResult.depth),
            bestMove: Move(uci: bestMoveText) ?? principalVariation.first,
            principalVariation: principalVariation,
            elapsedMilliseconds: Int(nativeResult.elapsedMilliseconds),
            nodes: Int(clamping: nativeResult.nodes)
        )
    }

    public func stop() async {
        if let context {
            qipan_stockfish_stop(context)
        }
    }
}
#endif
