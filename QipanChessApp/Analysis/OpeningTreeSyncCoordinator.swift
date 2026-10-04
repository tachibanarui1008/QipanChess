import Combine
import Engine
import Foundation
import GameCore

public struct GameRecommendation: Codable, Equatable, Identifiable, Sendable {
    public var gameID: UUID
    public var tags: [String]
    public var reason: String
    public var group: String
    public var treeName: String
    public var id: UUID { gameID }
}
public enum PersonalGameSelector {
    public static func recommendations(games: [GameRecord], reports: [UUID: GameReviewReport], username: String, limit: Int = 20) -> [GameRecommendation] {
        struct Candidate { var game: GameRecord; var side: PieceColor; var own: [ReviewedMove]; var group: String; var name: String }
        let candidates = games.compactMap { game -> Candidate? in
            let side: PieceColor
            if game.tags["White"]?.lowercased() == username.lowercased() { side = .white }
            else if game.tags["Black"]?.lowercased() == username.lowercased() { side = .black }
            else { return nil }
            guard let report = reports[game.id], report.version == GameReviewReport.currentVersion,
                  report.depth >= 14, report.analysisKey == game.analysisKey, report.moves.count == game.moves.count else { return nil }
            let own = report.moves.filter { $0.side == side }
            guard !own.isEmpty else { return nil }
            let info = openingGrouping(game, side: side)
            return Candidate(game: game, side: side, own: own, group: info.key, name: info.name)
        }
        func average(_ c: Candidate) -> Double { c.own.map(\.loss).reduce(0, +) / Double(c.own.count) }
        func highlights(_ c: Candidate) -> Int { c.own.filter { [.brilliant, .great].contains($0.classification) }.count }
        func errors(_ c: Candidate) -> Int { c.own.filter { [.mistake, .blunder, .miss].contains($0.classification) }.count }
        func date(_ c: Candidate) -> String { (c.game.tags["UTCDate"] ?? c.game.tags["Date"] ?? "") + (c.game.tags["UTCTime"] ?? "") }
        func diverse(_ sorted: [Candidate]) -> [Candidate] {
            var groups: [String: [Candidate]] = [:]; var keys: [String] = []
            for item in sorted { if groups[item.group] == nil { keys.append(item.group) }; groups[item.group, default: []].append(item) }
            var output: [Candidate] = []; var round = 0
            while output.count < limit {
                var added = false
                for key in keys where output.count < limit {
                    if let group = groups[key], group.indices.contains(round) { output.append(group[round]); added = true }
                }
                if !added { break }; round += 1
            }
            return output
        }
        let best = diverse(candidates.filter { $0.own.count >= 8 }.sorted {
            if average($0) != average($1) { return average($0) < average($1) }
            if highlights($0) != highlights($1) { return highlights($0) > highlights($1) }
            return date($0) == date($1) ? $0.game.id.uuidString < $1.game.id.uuidString : date($0) > date($1)
        })
        let learn = diverse(candidates.filter { errors($0) > 0 || ($0.own.map(\.loss).max() ?? 0) >= 0.05 }.sorted {
            let a = $0.own.map(\.loss).max() ?? 0, b = $1.own.map(\.loss).max() ?? 0
            if a != b { return a > b }; if errors($0) != errors($1) { return errors($0) > errors($1) }
            return date($0) == date($1) ? $0.game.id.uuidString < $1.game.id.uuidString : date($0) > date($1)
        })
        var results: [UUID: GameRecommendation] = [:]
        for c in best {
            let tree = grouping(c.game, side: c.side)
            results[c.game.id] = GameRecommendation(gameID: c.game.id, tags: ["精彩发挥"],
                reason: "本人平均预期得分损失 \(String(format: "%.1f", average(c) * 100)) 个百分点 · \(highlights(c)) 步妙着／关键好棋", group: tree.key, treeName: tree.name)
        }
        for c in learn {
            let tree = grouping(c.game, side: c.side)
            let turn = c.own.max { $0.loss < $1.loss }!
            let reason = "第 \(turn.index) 手 \(turn.san)：\(turn.classification.title)，预期得分下降 \(String(format: "%.1f", turn.loss * 100)) 个百分点"
            if var old = results[c.game.id] { old.tags.append("复盘素材"); old.reason += "\n" + reason; results[c.game.id] = old }
            else { results[c.game.id] = GameRecommendation(gameID: c.game.id, tags: ["复盘素材"], reason: reason, group: tree.key, treeName: tree.name) }
        }
        return results.values.sorted { $0.group == $1.group ? $0.gameID.uuidString < $1.gameID.uuidString : $0.group < $1.group }
    }
    public static func grouping(_ game: GameRecord, side: PieceColor) -> (key: String, name: String) {
        OpeningTreeDocument.firstMoveGroup(fen: game.initialFEN, moves: game.moves, side: side)
    }
    private static func openingGrouping(_ game: GameRecord, side: PieceColor) -> (key: String, name: String) {
        let color = side == .white ? "白方" : "黑方"
        if let eco = game.tags["ECO"], eco.range(of: "^[A-E][0-9]{2}$", options: .regularExpression) != nil {
            let local = OpeningBook.all.first { $0.eco == eco }?.name
            let slug = game.tags["ECOUrl"].flatMap { URL(string: $0)?.lastPathComponent.removingPercentEncoding }
            let remote = slug?.replacingOccurrences(of: "-", with: " ")
            return ("\(side.rawValue):\(eco)", "\(color) · \(local ?? remote ?? eco)")
        }
        let prefix = Array(game.moves.prefix(4)); var p = (try? GamePosition(fen: game.initialFEN)) ?? .starting
        let label = prefix.map { move in let s = SAN.string(for: move, in: p); p.make(move); return s }.joined(separator: " ")
        return ("\(side.rawValue):\(game.initialFEN):\(prefix.map(\.uci).joined(separator: " "))", "\(color) · \(label.isEmpty ? "自定义开局" : label)")
    }
}

@MainActor public final class OpeningTreeSyncCoordinator: ObservableObject {
    @Published public var username: String
    @Published public private(set) var isFetching = false
    @Published public private(set) var isAnalyzing = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var analyzed = 0
    @Published public private(set) var total = 0
    @Published public private(set) var currentMove = 0
    @Published public private(set) var currentTotal = 0
    @Published public private(set) var message = "连接公开棋局，建立自己的开局树。"
    @Published public private(set) var issues: [String] = []
    @Published public private(set) var recommendations: [GameRecommendation] = []
    public var foregroundBusy = false
    private let library: GameLibrary
    private let trees: OpeningTreeStore
    private let client: ChessComArchiveClient
    private let directory: URL
    private let engineFactory: () -> (any ChessEngine)?
    private var fetchTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var token = UUID()
    private struct State: Codable { var username: String; var requestedAnalysis: Bool; var recommendations: [GameRecommendation]; var paused: Bool? = nil }
    private var requestedAnalysis = false
    public init(library: GameLibrary, trees: OpeningTreeStore, directory: URL? = nil,
                transport: any ArchiveTransport = URLSessionArchiveTransport(), engineFactory: @escaping () -> (any ChessEngine)? = PlatformEngineFactory.makeDefaultEngine) {
        self.library = library; self.trees = trees
        self.directory = directory ?? library.directory.deletingLastPathComponent().appendingPathComponent("ChessCom")
        self.client = ChessComArchiveClient(directory: self.directory.appendingPathComponent("Cache"), transport: transport)
        self.engineFactory = engineFactory; username = "SuigennSennkakuGoodGirl"
        if let data = try? Data(contentsOf: self.directory.appendingPathComponent("state.json")), let state = try? JSONDecoder().decode(State.self, from: data) {
            username = state.username; requestedAnalysis = state.requestedAnalysis; recommendations = state.recommendations; isPaused = state.paused ?? false
        }
        refreshRecommendations()
    }
    public func importSeed(_ seed: URL) {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: seed, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("review-") {
            guard let data = try? Data(contentsOf: url), let incoming = try? JSONDecoder().decode(GameRecord.self, from: data).validated() else { continue }
            let record = library.importRecord(incoming)
            let reviewFile = seed.appendingPathComponent("review-\(incoming.id).json")
            if let data = try? Data(contentsOf: reviewFile), let report = try? JSONDecoder().decode(GameReviewReport.self, from: data), report.analysisKey == record.analysisKey,
               (library.review(for: record)?.moves.count ?? 0) < report.moves.count {
                library.saveReview(report, for: record.id)
            }
        }
        refreshRecommendations(); requestedAnalysis = analyzed < total; message = "已导入 \(total) 盘棋局，\(analyzed) 盘已完成本地分析。"; persist()
    }
    public func resumeIfNeeded() { if requestedAnalysis { startAnalysis() } }
    public func synchronize() {
        guard !isFetching else { return }
        isFetching = true; issues = []; message = "查询全部公开历史…"
        let requestedUsername = username
        fetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let urls = try await self.client.archives(for: requestedUsername)
                self.username = try await self.client.username(requestedUsername)
                for (index, url) in urls.enumerated() {
                    try Task.checkCancellation()
                    self.message = "读取归档 \(index + 1)/\(urls.count)…"
                    let games = try await self.client.month(url)
                    for incoming in games {
                        guard incoming.rules == "chess" else { self.issues.append("跳过非标准棋局：\(incoming.url)"); continue }
                        guard let pgn = incoming.pgn else { self.issues.append("缺少棋谱：\(incoming.url)"); continue }
                        do {
                            var record = try PGN.decode(pgn); record.tags["Link"] = incoming.url
                            record.tags["Source"] = "Chess.com"; record.tags["TimeClass"] = incoming.time_class
                            _ = self.library.importRecord(record)
                        } catch { self.issues.append("无法读取 \(incoming.url)：\(error.localizedDescription)") }
                    }
                }
                self.message = urls.isEmpty ? "该账号暂无公开棋局。" : "公开棋局已导入，开始本地评分。"
                self.isFetching = false; self.requestedAnalysis = true; self.refreshRecommendations(); self.startAnalysis()
            } catch {
                self.isFetching = false; self.message = error is CancellationError ? "同步已停止，已导入内容保留。" : "同步失败：\(error.localizedDescription)"; self.persist()
            }
        }
    }
    public func stopFetching() { fetchTask?.cancel() }
    public func pause() { isPaused = true; persist() }
    public func resume() { isPaused = false; requestedAnalysis = true; persist(); startAnalysis() }
    private func accountGames() -> [GameRecord] {
        library.games.filter { $0.tags["White"]?.lowercased() == username.lowercased() || $0.tags["Black"]?.lowercased() == username.lowercased() }
            .sorted { ($0.tags["Date"] ?? "") > ($1.tags["Date"] ?? "") }
    }
    private func updateCounts() {
        let games = accountGames(); total = games.count
        analyzed = games.filter { game in guard let report = library.review(for: game) else { return false }; return report.depth >= 14 && report.moves.count == game.moves.count }.count
    }
    public func refreshRecommendations() {
        let games = accountGames()
        let sourceSides = Dictionary(uniqueKeysWithValues: games.map { ($0.id, $0.tags["White"]?.lowercased() == username.lowercased() ? PieceColor.white : .black) })
        trees.consolidateByFirstMove(sourceSides: sourceSides)
        let reports = Dictionary(uniqueKeysWithValues: games.compactMap { game in library.review(for: game).map { (game.id, $0) } })
        recommendations = PersonalGameSelector.recommendations(games: games, reports: reports, username: username)
        for game in games {
            if trees.curation != nil { trees.importCurated(game, report: reports[game.id]); continue }
            let side = sourceSides[game.id] ?? .white
            let group = PersonalGameSelector.grouping(game, side: side)
            guard !trees.isGroupDeleted(group.key) else { continue }
            let id = trees.trees.first(where: { $0.groupingKey == group.key })?.id ?? trees.create(name: group.name, groupingKey: group.key, side: side)
            trees.synchronize(record: game, kind: .game, report: reports[game.id], treeID: id)
        }
        updateCounts(); persist()
    }
    public func startAnalysis() {
        guard !isAnalyzing, !isPaused else { return }
        updateCounts(); guard analyzed < total else { requestedAnalysis = false; refreshRecommendations(); message = "全部 \(total) 盘分析完成。"; persist(); return }
        guard let engine = engineFactory() else { message = "本地引擎不可用。"; return }
        let generation = UUID(); token = generation; isAnalyzing = true; requestedAnalysis = true; persist()
        analysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                for record in self.accountGames() {
                    try Task.checkCancellation()
                    guard self.token == generation else { break }
                    if let report = self.library.review(for: record), report.depth >= 14, report.moves.count == record.moves.count { continue }
                    let positions = try record.positions()
                    var reviewed = self.library.review(for: record).flatMap { $0.depth >= 14 && $0.engine == engine.name ? $0.moves : nil } ?? []
                    // Only a contiguous prefix can be resumed; live reviews may be sparse.
                    reviewed = reviewed.enumerated().prefix { $0.element.index == $0.offset + 1 }.map(\.element)
                    self.currentTotal = record.moves.count
                    for index in reviewed.count..<record.moves.count {
                        while self.foregroundBusy || self.isPaused { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation() }
                        self.currentMove = index + 1
                        self.message = "本地分析 \(self.analyzed + 1)/\(self.total) 盘 · 第 \(index + 1)/\(record.moves.count) 手"
                        let item = try await GameReviewCoordinator.review(move: record.moves[index], index: index, position: positions[index], after: positions[index + 1],
                            depth: 14, previous: reviewed.last, engine: engine, history: EnginePositionHistory(initialFEN: record.initialFEN, moves: Array(record.moves.prefix(index))))
                        reviewed.append(item)
                        let report = GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: record.analysisKey, depth: 14, engine: engine.name, completedAt: Date(), moves: reviewed)
                        self.library.saveReview(report, for: record.id)
                    }
                    self.refreshRecommendations()
                }
                self.requestedAnalysis = false; self.message = "全部 \(self.total) 盘分析完成。"; self.currentMove = 0
            } catch { self.message = "分析暂停，可继续：\(error.localizedDescription)" }
            self.isAnalyzing = false; self.persist(); await engine.stop()
        }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(State(username: username, requestedAnalysis: requestedAnalysis, recommendations: recommendations, paused: isPaused)).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        } catch { message = "同步进度保存失败：\(error.localizedDescription)" }
    }
}
