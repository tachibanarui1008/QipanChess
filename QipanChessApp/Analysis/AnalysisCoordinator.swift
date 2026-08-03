import Combine
import Engine
import Foundation
import GameCore

@MainActor
public final class AnalysisCoordinator: ObservableObject {
    @Published public private(set) var snapshot: PositionAnalysis

    private let engine: (any ChessEngine)?
    private var generation = 0

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
    }

    public func refresh(for position: GamePosition) {
        generation += 1
        let requestedGeneration = generation

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

        Task { [weak self] in
            do {
                let result = try await engine.analyze(
                    position: position,
                    limit: AnalysisLimit(depth: 16)
                )
                guard let self, requestedGeneration == self.generation else { return }
                self.snapshot = EngineAnalysisAdapter.make(
                    result: result,
                    position: position,
                    engineName: engine.name
                )
            } catch {
                guard let self, requestedGeneration == self.generation else { return }
                self.snapshot = .placeholder(
                    position: position,
                    state: .failed(error.localizedDescription),
                    engineName: engine.name
                )
            }
        }
    }
}
