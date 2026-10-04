import Combine
import Foundation
import GameCore

/// Each record and report has its own atomic file; a bad file never replaces the library.
@MainActor
public final class GameLibrary: ObservableObject {
    @Published public private(set) var games: [GameRecord] = []
    @Published public private(set) var errorMessage: String?
    public let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var reviewCache: [UUID: GameReviewReport] = [:]
    private var loadedReviews: Set<UUID> = []
    private func storedReview(_ id: UUID) -> GameReviewReport? {
        if loadedReviews.insert(id).inserted, let data = try? Data(contentsOf: directory.appendingPathComponent("review-\(id).json")) { reviewCache[id] = try? decoder.decode(GameReviewReport.self, from: data) }
        return reviewCache[id]
    }

    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QipanChess/Library", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            let urls = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "json" && !url.lastPathComponent.hasPrefix("review-") {
                do { games.append(try decoder.decode(GameRecord.self, from: Data(contentsOf: url)).validated()) }
                catch { errorMessage = "部分棋局无法读取，原文件已保留：\(error.localizedDescription)" }
            }
            games.sort { $0.updatedAt > $1.updatedAt }
        } catch { errorMessage = "棋局库无法读取：\(error.localizedDescription)" }
    }
    @discardableResult
    public func save(_ record: GameRecord) -> Bool {
        do {
            try encoder.encode(record).write(to: directory.appendingPathComponent("\(record.id).json"), options: .atomic)
            games.removeAll { $0.id == record.id }; games.append(record)
            games.sort { $0.updatedAt > $1.updatedAt }; errorMessage = nil
            return true
        } catch { errorMessage = "保存失败：\(error.localizedDescription)"; return false }
    }
    @discardableResult public func importRecord(_ incoming: GameRecord) -> GameRecord {
        if let link = incoming.tags["Link"], let existing = games.first(where: { $0.tags["Link"] == link }) { return existing }
        if incoming.tags["Link"] == nil, let existing = games.first(where: { $0.analysisKey == incoming.analysisKey && $0.tags == incoming.tags }) { return existing }
        _ = save(incoming); return incoming
    }
    public func saveReview(_ report: GameReviewReport, for id: UUID) {
        do {
            let file = directory.appendingPathComponent("review-\(id).json")
            var value = report
            if let old = storedReview(id),
               old.analysisKey == report.analysisKey, old.version == report.version, old.engine == report.engine {
                var byIndex = Dictionary(uniqueKeysWithValues: old.moves.map { ($0.index, $0) })
                for item in report.moves where (byIndex[item.index]?.depth ?? 0) <= item.depth { byIndex[item.index] = item }
                let all = byIndex.values.sorted { $0.index < $1.index }
                value = GameReviewReport(version: report.version, analysisKey: report.analysisKey,
                    depth: all.map(\.depth).min() ?? max(old.depth, report.depth), engine: report.engine, completedAt: report.completedAt, moves: all)
            }
            try encoder.encode(value).write(to: file, options: .atomic)
            reviewCache[id] = value; loadedReviews.insert(id)
        } catch { errorMessage = "复盘保存失败：\(error.localizedDescription)" }
    }
    public func review(for record: GameRecord) -> GameReviewReport? {
        guard let report = storedReview(record.id),
              report.analysisKey == record.analysisKey, report.version == GameReviewReport.currentVersion else { return nil }
        return report
    }
}
