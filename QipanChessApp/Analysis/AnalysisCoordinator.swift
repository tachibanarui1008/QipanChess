import Combine
import Engine
import Foundation
import GameCore

@MainActor
public final class AnalysisCoordinator: ObservableObject {
    @Published public private(set) var snapshot: PositionAnalysis
    @Published public private(set) var timeline: [AdvantagePoint]

    private let engine: (any ChessEngine)?
    private var generation = 0
    private var pendingKey: String?
    private var cachedStrategies: [String: PositionAnalysis] = [:]
    private func cacheKey(_ position: GamePosition, _ strategy: StrategyType, _ depth: Int) -> String { position.fen + "|candidates3|" + strategy.rawValue + "|" + String(depth) }
    @discardableResult public func restoreCachedStrategy(for position: GamePosition, strategy: StrategyType, depth: Int) -> Bool {
        guard let cached = cachedStrategies[cacheKey(position, strategy, depth)] else { return false }
        generation += 1; analysisTask?.cancel(); pendingKey = nil; snapshot = cached
        timeline.removeAll { $0.ply > position.plyCount }
        record(advantage: cached.evaluation.advantage, at: position.plyCount)
        return true
    }
    private var analysisTask: Task<Void, Never>?

    public init(
        initialPosition: GamePosition = .starting,
        engine: (any ChessEngine)? = PlatformEngineFactory.makeDefaultEngine()
    ) {
        self.engine = engine
        let state: AnalysisState = engine == nil
            ? .unavailable(PlatformEngineEndpoint.unavailableDescription)
            : .idle
        self.snapshot = .placeholder(
            position: initialPosition,
            state: state,
            engineName: engine?.name ?? "分析引擎"
        )
        self.timeline = []
    }

    public func reset(for position: GamePosition) {
        generation += 1
        analysisTask?.cancel(); analysisTask = nil; pendingKey = nil
        timeline = []
        snapshot = .placeholder(position: position, engineName: engine?.name ?? "分析引擎")
    }
    public func suspend(for position: GamePosition, preservingTimeline: Bool = false) {
        let previousTimeline = timeline
        reset(for: position)
        if preservingTimeline { timeline = previousTimeline }
        if let engine { Task { await engine.stop() } }
    }

    /// Compatibility entry point: position suggestions now share one three-candidate search.
    public func refreshSelectedStrategy(
        for position: GamePosition,
        strategy: StrategyType,
        depth: Int
    ) {
        if pendingKey == cacheKey(position, strategy, depth) { return }
        if restoreCachedStrategy(for: position, strategy: strategy, depth: depth) { return }
        refresh(
            for: position,
            limit: AnalysisLimit(depth: depth),
            strategy: strategy
        )
    }

    private func refresh(
        for position: GamePosition,
        limit: AnalysisLimit,
        strategy: StrategyType
    ) {
        generation += 1
        let requestedGeneration = generation
        timeline.removeAll { $0.ply > position.plyCount }

        guard let engine else {
            snapshot = .placeholder(
                position: position,
                state: .unavailable(PlatformEngineEndpoint.unavailableDescription)
            )
            return
        }

        snapshot = .placeholder(
            position: position,
            state: .analyzing,
            engineName: engine.name
        )

        analysisTask?.cancel()
        pendingKey = cacheKey(position, strategy, limit.depth)
        analysisTask = Task { [weak self] in
            do {
                // Coalesce rapid cursor changes and let the board render before searching.
                try await Task.sleep(for: .milliseconds(120))
                let result = try await engine.analyze(position: position, limit: AnalysisLimit(depth: limit.depth, multiPV: 3))
                guard let self, requestedGeneration == self.generation else { return }
                self.pendingKey = nil
                let completedAnalysis = EngineAnalysisAdapter.make(
                    result: result,
                    position: position,
                    engineName: engine.name,
                    strategyOverride: strategy
                )
                if self.cachedStrategies.count >= 256 { self.cachedStrategies.removeAll() }
                self.cachedStrategies[self.cacheKey(position, strategy, limit.depth)] = completedAnalysis
                self.snapshot = completedAnalysis
                self.record(
                    advantage: completedAnalysis.evaluation.advantage,
                    at: position.plyCount
                )
            } catch {
                guard let self, requestedGeneration == self.generation else { return }
                self.pendingKey = nil
                self.snapshot = .placeholder(
                    position: position,
                    state: .failed(error.localizedDescription),
                    engineName: engine.name
                )
            }
        }
    }

    public func bestMove(
        for position: GamePosition,
        depth: Int,
        strategy: StrategyType = .balanced
    ) async throws -> Move? {
        guard let engine else {
            throw ChessEngineError.executableNotConfigured
        }
        let result = try await engine.analyze(position: position, limit: AnalysisLimit(depth: depth, multiPV: 1))
        return result.bestMove ?? result.principalVariation.first
    }

    private func record(advantage: PositionAdvantage, at ply: Int) {
        let point = AdvantagePoint(ply: ply, advantage: advantage)
        if let index = timeline.firstIndex(where: { $0.ply == ply }) {
            timeline[index] = point
        } else {
            timeline.append(point)
            timeline.sort { $0.ply < $1.ply }
        }
    }

}
