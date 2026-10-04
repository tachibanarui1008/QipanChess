import Combine
import Foundation
import GameCore

public enum TreeSourceKind: String, Codable, Sendable { case game, research }
public struct TreeSource: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var gameID: UUID
    public var title: String
    public var initialFEN: String
    public var moves: [Move]
    public var kind: TreeSourceKind
}
public struct TreeAnnotation: Codable, Equatable, Sendable {
    public var review: ReviewedMove
    public var version: Int
    public var engine: String
}
public struct OpeningTreeNode: Identifiable, Equatable, Sendable {
    public var id: String
    public var parentID: String?
    public var move: Move?
    public var san: String
    public var side: PieceColor?
    public var moves: [Move]
    public var initialFEN: String
    public var children: [String]
    public var gameIDs: Set<UUID>
    public var researchIDs: Set<String>
    public var annotation: TreeAnnotation?
    public var count: Int { gameIDs.count }
}
fileprivate struct CachedOpeningStep {
    var position: GamePosition
    var san: String
}
public struct OpeningTreeDocument: Codable, Equatable, Identifiable, Sendable {
    public var version = 1
    public var id = UUID()
    public var name: String
    public var maxPlies = 40
    public var savedZoom: Double? = nil
    public var organizedByAdvantage: Bool? = nil
    public var importedSnapshot: Bool? = nil
    public var groupingKey: String?
    public var repertoireSide: PieceColor?
    public var sources: [TreeSource] = []
    public var notes: [String: String] = [:]
    public var preferredChildren: [String: String] = [:]
    public var deletedEdges: Set<String>? = nil
    public var hidden: Set<String> = []
    public var annotations: [String: TreeAnnotation] = [:]
    public var updatedAt = Date()
    public init(name: String, groupingKey: String? = nil) { self.name = name; self.groupingKey = groupingKey }
    public static func nodeID(fen: String, moves: [Move]) -> String { fen + "|" + moves.map(\.uci).joined(separator: " ") }
    public static func firstMoveGroup(fen: String, moves: [Move], side: PieceColor? = nil) -> (key: String, name: String) {
        let position = (try? GamePosition(fen: fen)) ?? .starting
        let san = moves.first.map { SAN.string(for: $0, in: position) } ?? "起始局面"
        return ("first-move:" + (side.map { $0.rawValue + ":" } ?? "") + nodeID(fen: fen, moves: Array(moves.prefix(1))), san + " · 开局树")
    }
    public func nodes(includeHidden: Bool = false) -> [OpeningTreeNode] {
        var steps: [String: CachedOpeningStep] = [:]
        return nodes(includeHidden: includeHidden, steps: &steps)
    }
    fileprivate func nodes(includeHidden: Bool, steps: inout [String: CachedOpeningStep]) -> [OpeningTreeNode] {
        var result: [String: OpeningTreeNode] = [:]
        for source in sources {
            guard var position = try? GamePosition(fen: source.initialFEN) else { continue }
            var prefix: [Move] = []
            var parent: String?
            var san = "起始局面"
            let route = Array(source.moves.prefix(maxPlies))
            for index in 0...route.count {
                let id = Self.nodeID(fen: source.initialFEN, moves: prefix)
                if deletedEdges?.contains(id) == true || (!includeHidden && hidden.contains(id)) { break }
                if result[id] == nil {
                    result[id] = OpeningTreeNode(id: id, parentID: parent, move: prefix.last,
                        san: san, side: prefix.isEmpty ? nil : position.sideToMove.opposite,
                        moves: prefix, initialFEN: source.initialFEN, children: [], gameIDs: [], researchIDs: [], annotation: annotations[id].flatMap { $0.version == GameReviewReport.currentVersion ? $0 : nil })
                }
                if source.kind == .game { result[id]?.gameIDs.insert(source.gameID) }
                else { result[id]?.researchIDs.insert(source.id) }
                if let parent, result[parent]?.children.contains(id) == false { result[parent]?.children.append(id) }
                parent = id
                guard index < route.count else { break }
                let move = route[index]
                let nextID = Self.nodeID(fen: source.initialFEN, moves: prefix + [move])
                if let cached = steps[nextID] {
                    san = cached.san; prefix.append(move); position = cached.position; continue
                }
                guard MoveGenerator.legalMoves(from: move.from, in: position).contains(move) else { break }
                san = SAN.string(for: move, in: position)
                prefix.append(move); position.make(move)
                steps[nextID] = CachedOpeningStep(position: position, san: san)
            }
        }
        for id in result.keys {
            let sorted = (result[id]?.children ?? []).sorted { lhs, rhs in
                if preferredChildren[id] == lhs { return true }
                if preferredChildren[id] == rhs { return false }
                let a = result[lhs]?.count ?? 0, b = result[rhs]?.count ?? 0
                return a == b ? lhs < rhs : a > b
            }
            result[id]?.children = sorted
        }
        return result.values.sorted { $0.id < $1.id }
    }
    public func validated() throws -> Self {
        guard version == 1, (1...400).contains(maxPlies), sources.count <= 50_000 else { throw ChessDocumentError.invalidPGN("开局树格式或大小无效") }
        for source in sources { var r = GameRecord(position: try GamePosition(fen: source.initialFEN)); r.moves = source.moves; _ = try r.validated() }
        return self
    }
}

@MainActor public final class OpeningTreeStore: ObservableObject {
    @Published public private(set) var trees: [OpeningTreeDocument] = []
    @Published public private(set) var bindings: [String: UUID] = [:]
    @Published public private(set) var errorMessage: String?
    public let directory: URL
    @Published public private(set) var curation: OpeningCurationState?
    @Published public private(set) var canUndoDeletion = false
    private var deletedGroups: Set<String> = []
    private var undoDeletion: (OpeningTreeDocument, [String: UUID], Set<String>)?
    private var routeStepCache: [String: CachedOpeningStep] = [:]
    private var nodeCache: [String: [OpeningTreeNode]] = [:]
    private var layoutCache: [UUID: OpeningTreeLayout] = [:]
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("QipanChess/OpeningTrees")
        do {
            try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil) where url.pathExtension == "json" {
                do {
                    if url.lastPathComponent == "curation.json" { curation = try JSONDecoder().decode(OpeningCurationState.self, from: Data(contentsOf: url)) }
                    else if url.lastPathComponent == "deleted-groups.json" { deletedGroups = try JSONDecoder().decode(Set<String>.self, from: Data(contentsOf: url)) }
                    else if url.lastPathComponent == "bindings.json" { bindings = try JSONDecoder().decode([String: UUID].self, from: Data(contentsOf: url)) }
                    else { trees.append(try JSONDecoder().decode(OpeningTreeDocument.self, from: Data(contentsOf: url)).validated()) }
                } catch { errorMessage = "部分开局树无法读取，原文件已保留：\(error.localizedDescription)" }
            }
            if let ids = curation?.originalTreeIDs { trees.removeAll { ids.contains($0.id) && $0.importedSnapshot != true } }
            else if curation == nil { trees.removeAll { $0.organizedByAdvantage == true && $0.importedSnapshot != true } }
            trees.sort { $0.updatedAt > $1.updatedAt }
            consolidateByFirstMove()
        } catch { errorMessage = error.localizedDescription }
    }
    /// Merge and partition existing routes by their first move, independent of player color/ECO.
    /// Original documents and bindings are backed up before changing any files.
    public func consolidateByFirstMove(sourceSides: [UUID: PieceColor]? = nil) {
        let originals = trees.filter { $0.importedSnapshot != true && $0.organizedByAdvantage != true && $0.sources.contains { !$0.moves.isEmpty } }
        guard !originals.isEmpty else { return }
        func side(_ document: OpeningTreeDocument, _ source: TreeSource) -> PieceColor? {
            document.repertoireSide ?? sourceSides.map { $0[source.gameID] ?? .white }
        }
        func group(_ document: OpeningTreeDocument, _ source: TreeSource) -> (key: String, name: String) {
            OpeningTreeDocument.firstMoveGroup(fen: source.initialFEN, moves: source.moves, side: side(document, source))
        }
        var groups: [String: [(OpeningTreeDocument, [TreeSource])]] = [:]
        for document in originals {
            var routes = Dictionary(grouping: document.sources.filter { !$0.moves.isEmpty }) { group(document, $0).key }
            // A freshly bound, unplayed game belongs with the existing theme until it has a first move.
            if let primary = routes.keys.sorted(by: { routes[$0]!.count == routes[$1]!.count ? $0 < $1 : routes[$0]!.count > routes[$1]!.count }).first {
                routes[primary, default: []].append(contentsOf: document.sources.filter { $0.moves.isEmpty })
            }
            for (key, sources) in routes { groups[key, default: []].append((document, sources)) }
        }
        guard groups.contains(where: { key, entries in entries.count > 1 || entries.first?.0.groupingKey != key }) else { return }
        do {
            let backup = directory.appendingPathComponent("MigrationBackups/first-move-\(UUID())")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            for document in originals { try encoder.encode(document).write(to: backup.appendingPathComponent("\(document.id).json"), options: .atomic) }
            try encoder.encode(bindings).write(to: backup.appendingPathComponent("bindings.json"), options: .atomic)
            var merged: [OpeningTreeDocument] = []
            var destinations: [UUID: [String: UUID]] = [:]
            var usedIDs: Set<UUID> = []
            for key in groups.keys.sorted() {
                let entries = groups[key]!.sorted {
                    if ($0.0.groupingKey == key) != ($1.0.groupingKey == key) { return $0.0.groupingKey == key }
                    if ($0.0.groupingKey == nil) != ($1.0.groupingKey == nil) { return $0.0.groupingKey == nil }
                    return $0.0.updatedAt == $1.0.updatedAt ? $0.0.id.uuidString < $1.0.id.uuidString : $0.0.updatedAt > $1.0.updatedAt
                }
                let first = entries[0]
                var document = OpeningTreeDocument(name: group(first.0, first.1[0]).name, groupingKey: key)
                if usedIDs.insert(first.0.id).inserted { document.id = first.0.id }
                if first.0.groupingKey == nil || first.0.groupingKey == key ||
                   (!first.0.name.hasPrefix("白方 · ") && !first.0.name.hasPrefix("黑方 · ")) { document.name = first.0.name }
                document.repertoireSide = side(first.0, first.1[0])
                document.savedZoom = first.0.savedZoom
                document.maxPlies = entries.map { $0.0.maxPlies }.max() ?? 40
                var sources: [String: TreeSource] = [:]
                for (old, routes) in entries {
                    destinations[old.id, default: [:]][key] = document.id
                    document.maxPlies = max(document.maxPlies, old.maxPlies)
                    for source in routes {
                        // Preserve differing historical routes even if they shared a source identifier.
                        var value = source
                        if let existing = sources[value.id], existing.initialFEN != value.initialFEN || existing.moves != value.moves {
                            value.id += ":merged:" + OpeningTreeDocument.nodeID(fen: value.initialFEN, moves: value.moves)
                        }
                        if sources[value.id]?.kind != .game { sources[value.id] = value }
                    }
                    func belongs(_ id: String) -> Bool {
                        routes.contains { source in
                            let root = OpeningTreeDocument.nodeID(fen: source.initialFEN, moves: [])
                            let end = OpeningTreeDocument.nodeID(fen: source.initialFEN, moves: source.moves)
                            return id == root || id == end || end.hasPrefix(id + " ")
                        }
                    }
                    for (id, text) in old.notes where belongs(id) {
                        if let existing = document.notes[id], existing != text { document.notes[id] = existing + "\n\n" + text }
                        else { document.notes[id] = text }
                    }
                    for (parent, child) in old.preferredChildren where belongs(parent) && belongs(child) {
                        if document.preferredChildren[parent] == nil { document.preferredChildren[parent] = child }
                        else if document.preferredChildren[parent] != child {
                            document.notes[child, default: ""] += "\n原主题树「\(old.name)」的主线。"
                        }
                    }
                    document.hidden.formUnion(old.hidden.filter(belongs))
                    document.deletedEdges = (document.deletedEdges ?? []).union(old.deletedEdges ?? [])
                    for (id, annotation) in old.annotations where belongs(id) {
                        let existing = document.annotations[id]
                        if existing == nil || (existing?.version ?? 0) < annotation.version ||
                           (existing?.version == annotation.version && existing.map { ReviewEngineIdentity.matches($0.engine, annotation.engine) } == true && (existing?.review.depth ?? 0) < annotation.review.depth) {
                            document.annotations[id] = annotation
                        }
                    }
                }
                document.sources = sources.values.sorted { $0.id < $1.id }
                merged.append(document)
            }
            var newBindings = bindings
            for (gameID, oldID) in bindings {
                guard let choices = destinations[oldID] else { continue }
                let source = originals.first { $0.id == oldID }?.sources.first { $0.gameID.uuidString == gameID }
                let original = originals.first { $0.id == oldID }
                let key = source.flatMap { value in original.map { group($0, value).key } }
                let routed = source.flatMap { value in merged.first { document in
                    choices.values.contains(document.id) && document.sources.contains { $0.id == value.id && $0.gameID == value.gameID }
                }?.id }
                newBindings[gameID] = routed ?? key.flatMap { choices[$0] } ?? choices.sorted { $0.key < $1.key }.first?.value
            }
            for document in merged { try encoder.encode(document).write(to: directory.appendingPathComponent("\(document.id).json"), options: .atomic) }
            try encoder.encode(newBindings).write(to: directory.appendingPathComponent("bindings.json"), options: .atomic)
            let retained = Set(merged.map(\.id))
            for old in originals where !retained.contains(old.id) { try FileManager.default.removeItem(at: directory.appendingPathComponent("\(old.id).json")) }
            let replaced = Set(originals.map(\.id))
            trees = (trees.filter { !replaced.contains($0.id) } + merged).sorted { $0.updatedAt > $1.updatedAt }
            bindings = newBindings; nodeCache.removeAll(); layoutCache.removeAll()
        } catch { errorMessage = "开局树合并未完成，原始数据已有备份：\(error.localizedDescription)" }
    }
    @discardableResult public func create(name: String, groupingKey: String? = nil, side: PieceColor? = nil) -> UUID {
        if let groupingKey { deletedGroups.remove(groupingKey); persistDeletedGroups() }
        var tree = OpeningTreeDocument(name: name, groupingKey: groupingKey); tree.repertoireSide = side; save(tree); return tree.id
    }
    public func matchingTree(fen: String, moves: [Move], side: PieceColor) -> UUID? {
        guard !moves.isEmpty else { return nil }
        let group = OpeningTreeDocument.firstMoveGroup(fen: fen, moves: moves, side: side)
        if curation != nil {
            return trees.filter { $0.repertoireSide == side || $0.repertoireSide == nil }.first { doc in
                doc.repertoireSide == side && doc.sources.contains { $0.initialFEN == fen && $0.moves.first == moves.first }
            }?.id ?? trees.first { $0.repertoireSide == nil && $0.sources.contains { $0.initialFEN == fen && $0.moves.first == moves.first } }?.id
        }
        return trees.first { $0.groupingKey == group.key && ($0.repertoireSide ?? .white) == side }?.id
    }
    public func resolveTree(fen: String, moves: [Move], side: PieceColor) -> UUID? {
        guard !moves.isEmpty else { return nil }
        if curation != nil {
            let rows = moves.indices.compactMap { index -> ReviewedMove? in
                let key = OpeningTreeDocument.nodeID(fen: fen, moves: Array(moves.prefix(index + 1)))
                return trees.compactMap { $0.annotations[key] }.filter { $0.version == GameReviewReport.currentVersion && ReviewEngineIdentity.matches($0.engine, "Stockfish 18") }.max { $0.review.depth < $1.review.depth }?.review
            }
            let decision = OpeningCurationDecision.evaluate(reviews: rows, plies: min(40, moves.count), isResearch: true, hasNotes: true)
            return curatedTree(fen: fen, moves: moves, side: decision.favoredSide)
        }
        if let id = matchingTree(fen: fen, moves: moves, side: side) { return id }
        let group = OpeningTreeDocument.firstMoveGroup(fen: fen, moves: moves, side: side)
        return create(name: group.name, groupingKey: group.key, side: side)
    }
    public static func advantageGroup(fen: String, moves: [Move], side: PieceColor?) -> (key: String, name: String) {
        let base = OpeningTreeDocument.firstMoveGroup(fen: fen, moves: moves)
        return ("advantage:" + (side?.rawValue ?? "unclassified") + ":" + base.key,
                base.name + " · " + (side.map { $0.displayName + "有利" } ?? "均衡／待评估"))
    }
    private func curatedTree(fen: String, moves: [Move], side: PieceColor?) -> UUID {
        let group = Self.advantageGroup(fen: fen, moves: moves, side: side)
        if let existing = trees.first(where: { $0.groupingKey == group.key }) { return existing.id }
        let id = create(name: group.name, groupingKey: group.key, side: side)
        update(id) { $0.organizedByAdvantage = true }; return id
    }
    /// Imports after curation cannot resurrect intentionally removed low-quality resources.
    public func importCurated(_ record: GameRecord, report: GameReviewReport?) {
        let sourceID = record.id.uuidString + ":main"
        guard curation?.excludedSourceIDs.contains(sourceID) != true else { return }
        if let existing = trees.first(where: { $0.sources.contains { $0.id == sourceID } }) {
            synchronize(record: record, kind: .game, report: report, treeID: existing.id); return
        }
        let rows = report?.version == GameReviewReport.currentVersion && report.map { ReviewEngineIdentity.matches($0.engine, "Stockfish 18") } == true ? report?.moves ?? [] : []
        let decision = OpeningCurationDecision.evaluate(reviews: rows, plies: min(40, record.moves.count), isResearch: false, hasNotes: false)
        if decision.remove {
            curation?.excludedSourceIDs.insert(sourceID); curation?.removedRoutes += 1; persistCuration(); return
        }
        let group = Self.advantageGroup(fen: record.initialFEN, moves: record.moves, side: decision.favoredSide)
        // Respect deletions from either the old repertoire or the new advantage organization.
        guard !deletedGroups.contains(group.key), !PieceColor.allCases.contains(where: {
            deletedGroups.contains(OpeningTreeDocument.firstMoveGroup(fen: record.initialFEN, moves: record.moves, side: $0).key)
        }) else { return }
        let id = curatedTree(fen: record.initialFEN, moves: record.moves, side: decision.favoredSide)
        synchronize(record: record, kind: .game, report: report, treeID: id)
    }
    private func persistCuration() {
        guard let curation else { return }
        do { try JSONEncoder().encode(curation).write(to: directory.appendingPathComponent("curation.json"), options: .atomic) }
        catch { errorMessage = "整理记录保存失败：\(error.localizedDescription)" }
    }
    /// One-time, backed-up migration from player-color repertoires to route-end advantages.
    public func curateByAdvantage() {
        guard curation == nil else { return }
        let imported = trees.filter { $0.importedSnapshot == true }
        let originals = trees.filter { $0.importedSnapshot != true }
        do {
            let backup = directory.appendingPathComponent("MigrationBackups/advantage-\(UUID())")
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            for doc in originals { try encoder.encode(doc).write(to: backup.appendingPathComponent("\(doc.id).json"), options: .atomic) }
            try encoder.encode(bindings).write(to: backup.appendingPathComponent("bindings.json"), options: .atomic)
            var state = OpeningCurationState(); state.backupPath = backup.path; state.originalTreeIDs = Set(originals.map(\.id))
            var grades: [String: TreeAnnotation] = [:]
            for doc in originals {
                for (key, grade) in doc.annotations where grade.version == GameReviewReport.currentVersion && ReviewEngineIdentity.matches(grade.engine, "Stockfish 18") {
                    if (grades[key]?.review.depth ?? -1) < grade.review.depth { grades[key] = grade }
                }
            }
            var groups: [String: OpeningTreeDocument] = [:]
            var seen: Set<String> = []
            var destination: [String: UUID] = [:]
            for old in originals {
                for source in old.sources {
                    let signature = source.id + ":" + OpeningTreeDocument.nodeID(fen: source.initialFEN, moves: source.moves)
                    guard seen.insert(signature).inserted else { continue }
                    let plies = min(old.maxPlies, source.moves.count)
                    let keys = (0...plies).map { OpeningTreeDocument.nodeID(fen: source.initialFEN, moves: Array(source.moves.prefix($0))) }
                    let hasNotes = keys.contains { !(old.notes[$0] ?? "").isEmpty }
                    let rows = keys.compactMap { grades[$0]?.review }
                    let decision = OpeningCurationDecision.evaluate(reviews: rows, plies: plies, isResearch: source.kind == .research, hasNotes: hasNotes)
                    if decision.remove { state.excludedSourceIDs.insert(source.id); state.removedRoutes += 1; continue }
                    let group = Self.advantageGroup(fen: source.initialFEN, moves: source.moves, side: decision.favoredSide)
                    var doc = groups[group.key] ?? OpeningTreeDocument(name: group.name, groupingKey: group.key)
                    doc.organizedByAdvantage = true; doc.repertoireSide = decision.favoredSide
                    doc.maxPlies = max(doc.maxPlies, old.maxPlies); doc.savedZoom = old.savedZoom
                    var value = source
                    if doc.sources.contains(where: { $0.id == value.id && $0.moves != value.moves }) { value.id += ":" + signature }
                    doc.sources.append(value)
                    // Preserve annotations and personal metadata, including data beyond the visible cutoff.
                    let end = OpeningTreeDocument.nodeID(fen: source.initialFEN, moves: source.moves)
                    func belongs(_ key: String) -> Bool { key == keys[0] || key == end || end.hasPrefix(key + " ") }
                    for (key, note) in old.notes where belongs(key) {
                        if let previous = doc.notes[key], previous != note { doc.notes[key] = previous + "\n" + note }
                        else { doc.notes[key] = note }
                    }
                    doc.annotations.merge(old.annotations.filter { belongs($0.key) }) { a, b in a.review.depth >= b.review.depth ? a : b }
                    doc.preferredChildren.merge(old.preferredChildren.filter { belongs($0.key) && belongs($0.value) }) { a, _ in a }
                    doc.hidden.formUnion(old.hidden.filter(belongs)); doc.deletedEdges = (doc.deletedEdges ?? []).union((old.deletedEdges ?? []).filter(belongs))
                    groups[group.key] = doc
                    if bindings[source.gameID.uuidString] == old.id { destination[source.gameID.uuidString] = doc.id }
                    switch decision.favoredSide { case .white: state.whiteRoutes += 1; case .black: state.blackRoutes += 1; case nil: state.unclassifiedRoutes += 1 }
                }
            }
            var documents = Array(groups.values)
            for old in originals where old.sources.isEmpty {
                var empty = old; empty.id = UUID(); empty.organizedByAdvantage = true; empty.repertoireSide = nil
                empty.groupingKey = nil; documents.append(empty)
            }
            // All original files are already backed up before any replacement is written.
            for doc in documents { try encoder.encode(doc).write(to: directory.appendingPathComponent("\(doc.id).json"), options: .atomic) }
            try encoder.encode(destination).write(to: directory.appendingPathComponent("bindings.json"), options: .atomic)
            try encoder.encode(state).write(to: directory.appendingPathComponent("curation.json"), options: .atomic)
            for doc in originals { try FileManager.default.removeItem(at: directory.appendingPathComponent("\(doc.id).json")) }
            trees = (documents + imported).sorted { $0.updatedAt > $1.updatedAt }; bindings = destination; curation = state
            nodeCache.removeAll(); layoutCache.removeAll()
        } catch { errorMessage = "整理未完成，原始开局树备份已保留：\(error.localizedDescription)" }
    }
    public func tree(_ id: UUID?) -> OpeningTreeDocument? { trees.first { $0.id == id } }
    public func nodes(for id: UUID, includeHidden: Bool = false) -> [OpeningTreeNode] {
        let key = id.uuidString + (includeHidden ? ":all" : ":visible")
        if let cached = nodeCache[key] { return cached }
        // Stable route prefixes retain notation and positions when counts or grades change.
        if routeStepCache.count > 50_000 { routeStepCache.removeAll() }
        let result = tree(id)?.nodes(includeHidden: includeHidden, steps: &routeStepCache) ?? []
        nodeCache[key] = result; return result
    }
    public func layout(for id: UUID) -> OpeningTreeLayout {
        if let cached = layoutCache[id] { return cached }
        let result = OpeningTreeLayout(nodes: nodes(for: id))
        layoutCache[id] = result; return result
    }
    public func boundTree(for record: GameRecord) -> UUID? { bindings[record.id.uuidString] }
    public func cachedReview(for record: GameRecord, engine: String, minimumDepth: Int = 14) -> GameReviewReport? {
        var reviewed: [ReviewedMove] = []
        for index in record.moves.indices {
            let key = OpeningTreeDocument.nodeID(fen: record.initialFEN, moves: Array(record.moves.prefix(index + 1)))
            let item = trees.compactMap { $0.annotations[key] }.filter {
                $0.version == GameReviewReport.currentVersion && ReviewEngineIdentity.matches($0.engine, engine) && $0.review.depth >= minimumDepth
            }.max { $0.review.depth < $1.review.depth }
            if let item { reviewed.append(item.review) }
        }
        guard !reviewed.isEmpty else { return nil }
        return GameReviewReport(version: GameReviewReport.currentVersion, analysisKey: record.analysisKey,
                               depth: reviewed.map(\.depth).min() ?? minimumDepth, engine: engine, completedAt: Date(), moves: reviewed)
    }
    /// Updating a cached grade never adds an unsaved route or changes source counts.
    public func saveKnownAnnotations(record: GameRecord, report: GameReviewReport, treeID: UUID?) {
        guard let id = treeID, let old = tree(id), report.analysisKey == record.analysisKey else { return }
        let known = Set(nodes(for: id, includeHidden: true).map(\.id))
        var document = old
        for item in report.moves where item.index <= record.moves.count {
            let key = OpeningTreeDocument.nodeID(fen: record.initialFEN, moves: Array(record.moves.prefix(item.index)))
            guard known.contains(key) else { continue }
            let existing = document.annotations[key]
            if existing == nil || existing?.version != report.version || existing.map { !ReviewEngineIdentity.matches($0.engine, report.engine) } == true || (existing?.review.depth ?? 0) < item.depth {
                document.annotations[key] = TreeAnnotation(review: item, version: report.version, engine: report.engine)
            }
        }
        if document != old { save(document) }
    }
    public func bind(_ treeID: UUID?, to record: GameRecord) {
        guard bindings[record.id.uuidString] != treeID else { return }
        bindings[record.id.uuidString] = treeID
        do { try JSONEncoder().encode(bindings).write(to: directory.appendingPathComponent("bindings.json"), options: .atomic) }
        catch { errorMessage = "关联保存失败：\(error.localizedDescription)" }
    }
    public func update(_ id: UUID, _ mutation: (inout OpeningTreeDocument) -> Void) {
        guard let original = tree(id) else { return }; var doc = original; mutation(&doc)
        guard doc != original else { return }; doc.updatedAt = Date(); save(doc)
    }
    public func save(_ document: OpeningTreeDocument) {
        let old = tree(document.id)
        if old?.sources != document.sources || old?.maxPlies != document.maxPlies || old?.preferredChildren != document.preferredChildren || old?.hidden != document.hidden || old?.deletedEdges != document.deletedEdges {
            nodeCache.removeValue(forKey: document.id.uuidString + ":visible")
            nodeCache.removeValue(forKey: document.id.uuidString + ":all")
            layoutCache.removeValue(forKey: document.id)
        } else if old?.annotations != document.annotations {
            for suffix in [":visible", ":all"] {
                let key = document.id.uuidString + suffix
                if let cached = nodeCache[key] {
                    nodeCache[key] = cached.map { node in
                        var node = node
                        node.annotation = document.annotations[node.id].flatMap { $0.version == GameReviewReport.currentVersion ? $0 : nil }
                        return node
                    }
                }
            }
        }
        do {
            try JSONEncoder().encode(document).write(to: directory.appendingPathComponent("\(document.id).json"), options: .atomic)
            trees.removeAll { $0.id == document.id }; trees.append(document); trees.sort { $0.updatedAt > $1.updatedAt }
        } catch { errorMessage = "开局树保存失败：\(error.localizedDescription)" }
    }
    /// Validate the entire snapshot before writing. Keep replaced files as recoverable backups.
    public func importArchive(_ archive: OpeningTreeArchive, replacingExisting: Bool = false) throws {
        _ = try archive.validated()
        let ids = Set(archive.trees.map(\.id))
        guard replacingExisting || !trees.contains(where: { ids.contains($0.id) }) else {
            throw ChessDocumentError.invalidPGN("已有同一棵开局树，请确认是否替换")
        }
        let encoder = JSONEncoder()
        let files = try archive.trees.map { original -> (URL, Data) in
            var tree = original; tree.importedSnapshot = true
            return (directory.appendingPathComponent("\(tree.id).json"), try encoder.encode(tree))
        }
        var previous: [URL: Data] = [:]
        for (url, _) in files where FileManager.default.fileExists(atPath: url.path) {
            previous[url] = try Data(contentsOf: url)
        }
        if !previous.isEmpty {
            let backup = directory.appendingPathComponent("ImportBackups/\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
            for (url, data) in previous { try data.write(to: backup.appendingPathComponent(url.lastPathComponent), options: .atomic) }
        }
        var written: [URL] = []
        do {
            for (url, data) in files { try data.write(to: url, options: .atomic); written.append(url) }
        } catch {
            let failure = error
            for url in written {
                if let data = previous[url] { try data.write(to: url, options: .atomic) }
                else { try FileManager.default.removeItem(at: url) }
            }
            throw failure
        }
        trees.removeAll { ids.contains($0.id) }
        trees.append(contentsOf: archive.trees.map { original in var tree = original; tree.importedSnapshot = true; return tree })
        trees.sort { $0.updatedAt > $1.updatedAt }
        nodeCache.removeAll(); layoutCache.removeAll(); errorMessage = nil
    }
    public func isGroupDeleted(_ key: String) -> Bool { deletedGroups.contains(key) }
    private func persistDeletedGroups() {
        do { try JSONEncoder().encode(deletedGroups).write(to: directory.appendingPathComponent("deleted-groups.json"), options: .atomic) }
        catch { errorMessage = "删除设置保存失败：\(error.localizedDescription)" }
    }
    private func backupDeletion(_ document: OpeningTreeDocument) -> Bool {
        do {
            let folder = directory.appendingPathComponent("Trash")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(document).write(to: folder.appendingPathComponent("\(document.id)-\(UUID()).json"), options: .atomic)
            undoDeletion = (document, bindings, deletedGroups); canUndoDeletion = true
            return true
        } catch { errorMessage = "未能备份，未删除：\(error.localizedDescription)"; return false }
    }
    public func deleteBranch(_ id: UUID, node: OpeningTreeNode, includeNode: Bool = false) {
        guard let document = tree(id), backupDeletion(document) else { return }
        let targets = includeNode && node.move != nil ? Set([node.id]) : Set(node.children)
        guard !targets.isEmpty else { return }
        update(id) { doc in
            doc.deletedEdges = (doc.deletedEdges ?? []).union(targets)
            func removed(_ key: String) -> Bool { targets.contains { key == $0 || key.hasPrefix($0 + " ") } }
            doc.notes = doc.notes.filter { !removed($0.key) }
            doc.annotations = doc.annotations.filter { !removed($0.key) }
            doc.preferredChildren = doc.preferredChildren.filter { !removed($0.key) && !removed($0.value) }
            doc.hidden = doc.hidden.filter { !removed($0) }
        }
    }
    @discardableResult public func deleteTree(_ id: UUID) -> Bool {
        guard let document = tree(id), backupDeletion(document) else { return false }
        do {
            if let key = document.groupingKey { deletedGroups.insert(key); persistDeletedGroups() }
            try FileManager.default.removeItem(at: directory.appendingPathComponent("\(id).json"))
            bindings = bindings.filter { $0.value != id }
            try JSONEncoder().encode(bindings).write(to: directory.appendingPathComponent("bindings.json"), options: .atomic)
            trees.removeAll { $0.id == id }; nodeCache.removeAll(); layoutCache.removeValue(forKey: id)
            return true
        } catch { errorMessage = "删除失败，可撤销恢复：\(error.localizedDescription)"; return false }
    }
    @discardableResult public func undoLastDeletion() -> UUID? {
        guard let (document, oldBindings, groups) = undoDeletion else { return nil }
        save(document); bindings = oldBindings; deletedGroups = groups; persistDeletedGroups()
        do { try JSONEncoder().encode(bindings).write(to: directory.appendingPathComponent("bindings.json"), options: .atomic) }
        catch { errorMessage = error.localizedDescription }
        undoDeletion = nil; canUndoDeletion = false; return document.id
    }
    public func synchronize(record: GameRecord, kind: TreeSourceKind, report: GameReviewReport? = nil, treeID: UUID? = nil, restoreDeleted: Bool = false) {
        guard let id = treeID ?? boundTree(for: record) else { return }
        update(id) { doc in
            if restoreDeleted {
                for index in 1...max(1, record.moves.count) { doc.deletedEdges?.remove(OpeningTreeDocument.nodeID(fen: record.initialFEN, moves: Array(record.moves.prefix(index)))) }
            }
            let sourceID = record.id.uuidString + ":main"
            let existing = doc.sources.first(where: { $0.id == sourceID })
            let effectiveKind: TreeSourceKind = existing?.moves == record.moves && existing?.kind == .game ? .game : kind
            if let old = existing, old.moves != record.moves,
               !old.moves.isEmpty, !Array(record.moves.prefix(old.moves.count)).elementsEqual(old.moves) {
                let branchID = record.id.uuidString + ":" + old.moves.map(\.uci).joined(separator: " ")
                if !doc.sources.contains(where: { $0.id == branchID }) {
                    var branch = old; branch.id = branchID; branch.kind = old.kind == .game && kind == .research ? .game : .research; doc.sources.append(branch)
                }
            }
            let source = TreeSource(id: sourceID, gameID: record.id, title: record.title, initialFEN: record.initialFEN, moves: record.moves, kind: effectiveKind)
            if let index = doc.sources.firstIndex(where: { $0.id == sourceID }) { doc.sources[index] = source }
            else { doc.sources.append(source) }
            for branch in record.branches {
                let id = record.id.uuidString + ":" + branch.moves.map(\.uci).joined(separator: " ")
                if !doc.sources.contains(where: { $0.id == id }) { doc.sources.append(TreeSource(id: id, gameID: record.id, title: branch.name, initialFEN: record.initialFEN, moves: branch.moves, kind: .research)) }
            }
            guard let report, report.version == GameReviewReport.currentVersion, report.analysisKey == record.analysisKey else { return }
            for item in report.moves where item.index <= min(record.moves.count, doc.maxPlies) {
                let key = OpeningTreeDocument.nodeID(fen: record.initialFEN, moves: Array(record.moves.prefix(item.index)))
                let old = doc.annotations[key]
                if old == nil || old.map { !ReviewEngineIdentity.matches($0.engine, report.engine) } == true || old?.version != report.version || (old?.review.depth ?? 0) < item.depth {
                    doc.annotations[key] = TreeAnnotation(review: item, version: report.version, engine: report.engine)
                }
            }
        }
    }
}

public struct TreeLayoutPoint: Equatable, Sendable { public var x: Double; public var y: Double }
public struct OpeningTreeLayout: Sendable {
    public let points: [String: TreeLayoutPoint]
    public let width: Double
    public let height: Double
    public init(nodes: [OpeningTreeNode]) {
        let lookup = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var points: [String: TreeLayoutPoint] = [:]; var leaf = 0.0
        let maxDepth = nodes.map { $0.moves.count }.max() ?? 0
        func visit(_ id: String) -> Double {
            guard let node = lookup[id] else { return 0 }
            let x: Double
            if node.children.isEmpty { x = leaf * 126 + 70; leaf += 1 }
            else { let xs = node.children.map(visit); x = (xs.first! + xs.last!) / 2 }
            points[id] = TreeLayoutPoint(x: x, y: Double(maxDepth - node.moves.count) * 84 + 50)
            return x
        }
        for root in nodes.filter({ $0.parentID == nil }) { _ = visit(root.id) }
        self.points = points; width = max(300, leaf * 126 + 14); height = max(240, Double(maxDepth + 1) * 84 + 40)
    }
}
