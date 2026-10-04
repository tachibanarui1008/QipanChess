import Combine
import Engine
import Foundation
import GameCore

/// Desktop and embedded builds use the same Stockfish version and scoring contract.
public enum ReviewEngineIdentity {
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let stockfish18 = ["Stockfish 18", "Stockfish 18（内嵌）"]
        return lhs == rhs || (stockfish18.contains(lhs) && stockfish18.contains(rhs))
    }
}

public enum ReviewQuality: String, Codable, CaseIterable, Sendable {
    case brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder
    public var title: String {
        switch self {
        case .brilliant: "妙着"
        case .great: "关键好棋"
        case .best: "最佳着"
        case .excellent: "优秀"
        case .book: "理论着"
        case .miss: "错失机会"
        case .good: "好棋"
        case .inaccuracy: "不精确"
        case .mistake: "错误"
        case .blunder: "严重失误"
        }
    }
    public static func classify(loss: Double, isBest: Bool) -> Self {
        if isBest { return .best }
        if loss < 0.02 { return .excellent }
        if loss < 0.05 { return .good }
        if loss < 0.10 { return .inaccuracy }
        if loss < 0.20 { return .mistake }
        return .blunder
    }
    public var symbol: String {
        switch self {
        case .brilliant: "!!"
        case .great: "!"
        case .best: "★"
        case .excellent: "👍"
        case .good: "✓"
        case .book: "书"
        case .inaccuracy: "?!"
        case .mistake: "?"
        case .miss: "×"
        case .blunder: "??"
        }
    }
    public var isPositive: Bool { [.brilliant, .great, .best, .excellent, .good, .book].contains(self) }
    public var isKeyMove: Bool { [.brilliant, .great, .mistake, .miss, .blunder].contains(self) }
    public var colorHex: String {
        switch self {
        case .brilliant: "26c2a3"
        case .great: "749bb8"
        case .best, .excellent: "81b64c"
        case .good: "95b776"
        case .book: "a88865"
        case .inaccuracy: "f7c531"
        case .mistake: "f9a85a"
        case .miss: "f5746a"
        case .blunder: "ee4a2f"
        }
    }
    public var meaning: String {
        switch self {
        case .brilliant: "加深搜索验证的好弃子，落子后局面不劣；仍是本地规则识别。"
        case .great: "当前搜索中找到明显优于其他选择的关键资源。"
        case .best: "引擎当前首选。"
        case .excellent: "与最佳选择极为接近。"
        case .good: "合理的好棋，但仍有更好的选择。"
        case .book: "本地开局库中的已知走法。"
        case .inaccuracy: "造成小幅评价损失。"
        case .mistake: "明显削弱当前局面。"
        case .miss: "错过强制将杀，或未利用对手失误取得胜势。"
        case .blunder: "造成严重评价损失或允许对手将杀。"
        }
    }
}

public enum ReviewMoveClassifier {
    public static func classify(loss: Double, isBest: Bool, isBook: Bool = false,
                                brilliant: Bool = false, great: Bool = false,
                                missedWin: Bool = false, allowsMate: Bool = false) -> ReviewQuality {
        let basic = ReviewQuality.classify(loss: loss, isBest: isBest)
        if allowsMate { return .blunder }
        if brilliant && loss < 0.02 { return .brilliant }
        if great && isBest { return .great }
        if missedWin { return .miss }
        if isBook && basic.isPositive { return .book }
        return basic
    }
}

public struct ReviewScore: Codable, Equatable, Sendable {
    public let centipawns: Int?
    public let mate: Int?
    public init(_ score: EngineScore, inverted: Bool = false) {
        let sign = inverted ? -1 : 1
        switch score {
        case .centipawns(let cp): centipawns = cp * sign; mate = nil
        case .mate(let count): centipawns = nil; mate = count * sign
        }
    }
    public var value: Double {
        if let cp = centipawns { return Double(cp) / 100 }
        if let mate { return mate > 0 ? 100 : -100 }
        return 0
    }
    public var text: String {
        if let mate { return mate > 0 ? "将杀 M\(mate)" : "被将杀 M\(abs(mate))" }
        return String(format: "%+.2f", value)
    }
}

public struct ReviewedMove: Codable, Equatable, Identifiable, Sendable {
    public let index: Int
    public let side: PieceColor
    public let san: String
    public let move: Move
    public let bestMove: Move?
    public let bestSAN: String?
    public let before: ReviewScore
    public let after: ReviewScore
    public let loss: Double
    public let quality: ReviewQuality
    public let highlight: String?
    public let explanation: String
    public let bestLine: [Move]
    public let actualLine: [Move]
    public let depth: Int
    public var expectedBefore: Double? = nil
    public var expectedAfter: Double? = nil
    public var id: Int { index }
    public var classification: ReviewQuality {
        // Old serialized highlights remain displayable for callers holding v1 reports.
        if highlight == "妙棋候选" { return .brilliant }
        if highlight == "关键好棋" { return .great }
        return quality
    }
    public var whiteEvaluation: Double { max(-10, min(10, after.value * (side == .white ? 1 : -1))) }
}

public struct GameReviewReport: Codable, Equatable, Sendable {
    public static let currentVersion = 3
    public let version: Int
    public let analysisKey: String
    public let depth: Int
    public let engine: String
    public let completedAt: Date
    public let moves: [ReviewedMove]
    public init(version: Int, analysisKey: String, depth: Int, engine: String, completedAt: Date, moves: [ReviewedMove]) {
        self.version = version; self.analysisKey = analysisKey; self.depth = depth
        self.engine = engine; self.completedAt = completedAt; self.moves = moves
    }
}

public enum ReviewPreset: String, CaseIterable, Identifiable, Sendable {
    case quick, standard, deep
    public var id: Self { self }
    public var title: String { switch self { case .quick: "快速"; case .standard: "标准"; case .deep: "深入" } }
    public var depth: Int { switch self { case .quick: 10; case .standard: 14; case .deep: 18 } }
}

@MainActor
public final class GameReviewCoordinator: ObservableObject {
    @Published public private(set) var report: GameReviewReport?
    @Published public private(set) var moves: [ReviewedMove] = []
    @Published public private(set) var isRunning = false
    @Published public private(set) var total = 0
    @Published public private(set) var message: String?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private var activeKey: String?
    private var liveRecord: GameRecord?
    private var pending: Set<Int> = []
    private var workingIndex: Int?
    private var fullReview = false
    @Published public private(set) var gradingIndex: Int?


    public init() {}
    public func restore(_ report: GameReviewReport?) {
        cancel(); liveRecord = nil; self.report = report; moves = report?.moves ?? []; total = moves.count
        activeKey = report?.analysisKey; message = nil
    }
    public func invalidateIfNeeded(for record: GameRecord) { updateLive(record: record, cursor: record.cursor) }
    public func updateLive(record: GameRecord, cursor: Int, engine: (any ChessEngine)? = nil, cached: GameReviewReport? = nil, allowAnalysis: Bool = true) {
        if fullReview {
            if activeKey == record.analysisKey { return }
            cancel()
        }
        let old = liveRecord
        let extends = old.map { $0.id == record.id && $0.initialFEN == record.initialFEN && Array(record.moves.prefix($0.moves.count)) == $0.moves } ?? false
        if !extends {
            cancel()
            if old?.id != record.id || old?.initialFEN != record.initialFEN {
                if activeKey != record.analysisKey { moves = []; report = nil }
            } else {
                let common = zip(old!.moves, record.moves).prefix { $0 == $1 }.count
                moves.removeAll { $0.index > common }
            }
        }
        liveRecord = record; activeKey = record.analysisKey; total = record.moves.count
        if let cached, cached.version == GameReviewReport.currentVersion, cached.analysisKey == record.analysisKey {
            for item in cached.moves where item.index <= record.moves.count {
                let existing = moves.first { $0.index == item.index }
                guard existing == nil || (existing!.depth <= item.depth && existing != item) else { continue }
                moves.removeAll { $0.index == item.index }; moves.append(item)
            }
            moves.sort { $0.index < $1.index }
            if report?.analysisKey != record.analysisKey || report?.moves != moves {
                report = GameReviewReport(version: cached.version, analysisKey: record.analysisKey,
                    depth: moves.map(\.depth).min() ?? cached.depth, engine: cached.engine, completedAt: cached.completedAt, moves: moves)
            }
        }
        if extends, let old {
            for index in old.moves.count..<record.moves.count { pending.insert(index) }
        } else if cursor > 0 && cursor <= record.moves.count { pending.insert(cursor - 1) }
        if cursor > 0 && cursor <= record.moves.count { pending.insert(cursor - 1) }
        pending = pending.filter { index in !moves.contains { $0.index == index + 1 } && index != workingIndex }
        if !allowAnalysis { pending = []; if isRunning { cancel() }; return }
        guard !pending.isEmpty, !isRunning else { return }
        guard let engine = engine ?? PlatformEngineFactory.makeDefaultEngine() else { message = "分析引擎不可用"; return }
        let token = UUID(); generation = token; isRunning = true; message = nil
        task = Task { [weak self] in
            do {
                while let self, self.generation == token, let index = self.pending.min(), let record = self.liveRecord {
                    self.pending.remove(index); self.workingIndex = index; self.gradingIndex = index + 1
                    let positions = try await Self.positions(for: record)
                    let item = try await Self.review(move: record.moves[index], index: index,
                        position: positions[index], after: positions[index + 1], depth: ReviewPreset.standard.depth,
                        previous: self.moves.first { $0.index == index }, engine: engine,
                        history: EnginePositionHistory(initialFEN: record.initialFEN, moves: Array(record.moves.prefix(index))))
                    try Task.checkCancellation()
                    guard self.generation == token, let latest = self.liveRecord,
                          Array(latest.moves.prefix(index + 1)) == Array(record.moves.prefix(index + 1)) else { break }
                    self.moves.removeAll { $0.index == item.index }; self.moves.append(item); self.moves.sort { $0.index < $1.index }
                    self.workingIndex = nil
                    self.report = GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: latest.analysisKey,
                        depth: ReviewPreset.standard.depth, engine: engine.name, completedAt: Date(), moves: self.moves)
                }
            } catch {
                if let self, self.generation == token { self.message = error is CancellationError ? nil : "评价失败：\(error.localizedDescription)" }
            }
            if let self, self.generation == token { self.isRunning = false; self.gradingIndex = nil; self.workingIndex = nil }
            await engine.stop()
        }
    }
    public func cancel() {
        generation = UUID(); task?.cancel(); task = nil; pending = []; workingIndex = nil; gradingIndex = nil; fullReview = false
        if isRunning { message = "已取消；当前局面计算结束后释放引擎。" }
        isRunning = false
    }
    public func start(record: GameRecord, preset: ReviewPreset, engine: (any ChessEngine)? = PlatformEngineFactory.makeDefaultEngine()) {
        cancel()
        guard !record.moves.isEmpty else { message = "先走棋或导入棋谱。"; return }
        guard let engine else { message = "分析引擎不可用。"; return }
        fullReview = true
        let token = UUID(); generation = token
        total = record.moves.count
        if activeKey != record.analysisKey { moves = [] }
        activeKey = record.analysisKey
        moves = moves.filter { $0.index > 0 && $0.index <= record.moves.count && $0.move == record.moves[$0.index - 1] }
        report = nil; message = nil; isRunning = true
        task = Task { [weak self] in
            do {
                let positions = try await Self.positions(for: record)
                var reviewed: [ReviewedMove] = []
                for index in record.moves.indices {
                    try Task.checkCancellation()
                    let item = try await Self.review(move: record.moves[index], index: index,
                                                     position: positions[index], after: positions[index + 1],
                                                     depth: preset.depth, previous: reviewed.last, engine: engine,
                                                     history: EnginePositionHistory(initialFEN: record.initialFEN, moves: Array(record.moves.prefix(index))))
                    try Task.checkCancellation()
                    reviewed.append(item)
                    guard let self, self.generation == token else { await engine.stop(); return }
                    self.moves.removeAll { $0.index == item.index }
                    self.moves.append(item); self.moves.sort { $0.index < $1.index }
                }
                guard let self, self.generation == token else { await engine.stop(); return }
                self.report = GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: record.analysisKey,
                                               depth: preset.depth, engine: engine.name, completedAt: Date(), moves: reviewed)
                self.isRunning = false; self.fullReview = false; self.message = "整盘分析完成"
            } catch {
                if let self, self.generation == token {
                    self.isRunning = false; self.fullReview = false
                    self.message = error is CancellationError ? "分析已取消" : "分析失败：\(error.localizedDescription)"
                }
            }
            await engine.stop()
        }
    }

    nonisolated private static func positions(for record: GameRecord) async throws -> [GamePosition] {
        try Task.checkCancellation()
        return try record.positions()
    }

    nonisolated public static func review(move: Move, index: Int, position: GamePosition, after: GamePosition,
                               depth: Int, previous: ReviewedMove?, engine: any ChessEngine,
                               history: EnginePositionHistory? = nil) async throws -> ReviewedMove {
        try Task.checkCancellation()
        var root = try await engine.analyze(position: position, limit: AnalysisLimit(depth: depth, multiPV: 2, history: history))
        try Task.checkCancellation()
        var actual = root.bestMove == move ? root : try await engine.analyze(position: position,
            limit: AnalysisLimit(depth: depth, rootMoves: [move], history: history))
        if isSacrifice(position: position, line: actual.principalVariation) {
            root = try await engine.analyze(position: position, limit: AnalysisLimit(depth: depth + 4, multiPV: 2, history: history))
            actual = root.bestMove == move ? root : try await engine.analyze(position: position,
                limit: AnalysisLimit(depth: depth + 4, rootMoves: [move], history: history))
        }
        try Task.checkCancellation()
        let before = ReviewScore(root.score), afterScore = ReviewScore(actual.score)
        let bestMove = root.bestMove ?? root.principalVariation.first
        let isBest = bestMove == move
        let beforePoints = expectedPoints(root), afterPoints = expectedPoints(actual)
        let loss = isBest ? 0 : max(0, beforePoints - afterPoints)
        let second = root.variations.first { $0.rank == 2 && $0.depth == root.depth }.map { expectedPoints(score: $0.score, wdl: $0.wdl) }
        let legalCount = MoveGenerator.allLegalMoves(for: position.sideToMove, in: position).count
        let recapture = previous?.move.to == move.to && position[move.to] != nil
        let great = isBest && legalCount > 1 && !recapture && second.map { beforePoints - $0 >= 0.10 } == true
        let brilliant = loss < 0.02 && afterPoints >= 0.5 && second.map { $0 < 0.8 } == true
            && isSacrifice(position: position, line: actual.principalVariation)
        let lostMate = (before.mate ?? 0) > 0 && (afterScore.mate ?? 0) <= 0 && afterPoints < 0.8
        let missedWin = (previous?.loss ?? 0) >= 0.1 && beforePoints >= 0.8 && afterPoints <= 0.55
        let allowsMate = (afterScore.mate ?? 0) < 0 && beforePoints >= 0.2 && !isBest
        let quality = ReviewMoveClassifier.classify(loss: loss, isBest: isBest,
            isBook: ReviewOpeningMoves.contains(move, in: position), brilliant: brilliant,
            great: great, missedWin: lostMate || missedWin, allowsMate: allowsMate)
        let bestSAN = bestMove.map { SAN.string(for: $0, in: position) }
        let explanation: String
        switch quality {
        case .brilliant: explanation = "加深搜索后，实战弃子仍有充分补偿，普通吃回不能立刻恢复投入的子力。请展开变化核查。"
        case .great: explanation = "找到关键资源；当前搜索中，其他候选的预期得分明显更低。"
        case .book: explanation = "本地开局库中的理论走法。关注出子、中心和后续计划。"
        case .miss: explanation = lostMate ? "错过搜索发现的强制将杀。" : "未能利用对手失误保持取胜机会。"
        default: explanation = isBest ? "与引擎当前最佳选择一致。" : "相较最佳着，预期得分下降 \(String(format: "%.1f", loss * 100)) 个百分点。可比较 \(bestSAN ?? "最佳着") 的变化。"
        }
        var item = ReviewedMove(index: index + 1, side: position.sideToMove, san: SAN.string(for: move, in: position),
            move: move, bestMove: bestMove, bestSAN: bestSAN, before: before, after: afterScore,
            loss: loss, quality: quality, highlight: nil, explanation: explanation,
            bestLine: root.principalVariation, actualLine: actual.principalVariation,
            depth: min(root.depth, actual.depth))
        item.expectedBefore = beforePoints; item.expectedAfter = afterPoints
        return item
    }
    nonisolated public static func expectedPoints(score: EngineScore, wdl: EngineWDL?) -> Double {
        if case .mate(let count) = score { return count > 0 ? 1 : 0 }
        if let wdl { return wdl.expectedPoints }
        if case .centipawns(let cp) = score { return 1 / (1 + exp(-Double(cp) / 200)) }
        return 0.5
    }
    nonisolated private static func expectedPoints(_ result: EngineResult) -> Double {
        expectedPoints(score: result.score, wdl: result.variations.first { $0.rank == 1 }?.wdl)
    }
    nonisolated public static func isSacrifice(position: GamePosition, line: [Move]) -> Bool {
        guard line.count >= 3, let first = line.first, let piece = position[first.from],
              piece.kind != .pawn, piece.kind != .king, line[1].to == first.to else { return false }
        let side = position.sideToMove
        func balance(_ p: GamePosition) -> Double {
            var total = 0.0
            for rank in 0..<8 { for file in 0..<8 {
                if let p = p[Square(file: file, rank: rank)!] {
                    total += pieceValue(p.kind) * (p.color == side ? 1 : -1)
                }
            }}
            return total
        }
        let initial = balance(position)
        var current = position
        for (i, move) in line.prefix(7).enumerated() {
            guard MoveGenerator.legalMoves(from: move.from, in: current).contains(move) else { return false }
            current.make(move)
            // A normal exchange is recovered by our immediate recapture.
            if i >= 2 && i % 2 == 0 && balance(current) > initial - 1.5 { return false }
        }
        return balance(current) <= initial - 1.5
    }
    nonisolated private static func pieceValue(_ kind: PieceKind) -> Double {
        switch kind { case .pawn: 1; case .knight, .bishop: 3; case .rook: 5; case .queen: 9; case .king: 0 }
    }

}


private enum ReviewOpeningMoves {
    static let keys: Set<String> = {
        var keys: Set<String> = []
        let lines = OpeningBook.all.map(\.moves)
        for line in lines {
            var position = GamePosition.starting
            for move in line {
                guard MoveGenerator.legalMoves(from: move.from, in: position).contains(move) else { break }
                keys.insert(position.repetitionKey + "|" + move.uci)
                position.make(move)
            }
        }
        return keys
    }()
    static func contains(_ move: Move, in position: GamePosition) -> Bool {
        keys.contains(position.repetitionKey + "|" + move.uci)
    }
}
