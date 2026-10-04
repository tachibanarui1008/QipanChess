import Foundation

public struct GameBranch: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var moves: [Move]
    public var comments: [Int: String]
    public init(name: String, moves: [Move], comments: [Int: String] = [:]) {
        self.id = UUID(); self.name = name; self.moves = moves; self.comments = comments
    }
}

public struct GameRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var tags: [String: String]
    public var initialFEN: String
    public var moves: [Move]
    public var comments: [Int: String]
    public var branches: [GameBranch]
    public var cursor: Int

    public init(position: GamePosition = .starting) {
        id = UUID(); createdAt = Date(); updatedAt = createdAt
        tags = ["Event": "个人棋局", "White": "白方", "Black": "黑方", "Result": "*"]
        initialFEN = position.fen; moves = []; comments = [:]; branches = []; cursor = 0
    }
    public var title: String { "\(tags["White"] ?? "白方") — \(tags["Black"] ?? "黑方")" }
    public var analysisKey: String { ([initialFEN] + moves.map(\.uci)).joined(separator: "|") }
    public func positions() throws -> [GamePosition] {
        var position = try GamePosition(fen: initialFEN)
        var result = [position]
        for move in moves {
            guard MoveGenerator.legalMoves(from: move.from, in: position).contains(move) else {
                throw ChessDocumentError.illegalMove(move.uci)
            }
            position.make(move); result.append(position)
        }
        return result
    }
    public func validated() throws -> GameRecord {
        guard moves.count <= 10_000, branches.count <= 1_000 else {
            throw ChessDocumentError.invalidPGN("棋谱过长")
        }
        _ = try positions()
        for branch in branches {
            var copy = self; copy.moves = branch.moves; copy.branches = []
            _ = try copy.positions()
        }
        guard (0...moves.count).contains(cursor) else { throw ChessDocumentError.invalidPGN("回放位置无效") }
        return self
    }
}

public enum PGN {
    public static func decode(_ input: String) throws -> GameRecord {
        guard input.utf8.count <= 2_000_000 else { throw ChessDocumentError.invalidPGN("文件超过 2 MB") }
        let tagPattern = #"\[\s*(\w+)\s+"((?:\\.|[^"\\])*)"\s*\]"#
        let regex = try NSRegularExpression(pattern: tagPattern)
        let ns = input as NSString
        var headers: Set<Int> = []
        var scan = 0, block = false, headerLineComment = false
        while scan < ns.length {
            let c = ns.character(at: scan)
            if block { if c == 125 { block = false }; scan += 1; continue }
            if headerLineComment { if c == 10 || c == 13 { headerLineComment = false }; scan += 1; continue }
            if c == 123 { block = true; scan += 1; continue }
            if c == 59 { headerLineComment = true; scan += 1; continue }
            if c == 91 {
                headers.insert(scan); scan += 1
                var quoted = false, escaped = false
                while scan < ns.length {
                    let t = ns.character(at: scan); scan += 1
                    if escaped { escaped = false; continue }
                    if t == 92 && quoted { escaped = true; continue }
                    if t == 34 { quoted.toggle() }
                    if t == 93 && !quoted { break }
                }
            } else { scan += 1 }
        }
        let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length)).filter { headers.contains($0.range.location) }
        var tags: [String: String] = [:]
        var body = input
        for match in matches {
            let key = ns.substring(with: match.range(at: 1))
            guard tags[key] == nil else { throw ChessDocumentError.invalidPGN("请一次导入一盘棋") }
            tags[key] = ns.substring(with: match.range(at: 2))
                .replacingOccurrences(of: #"\""#, with: "\"")
                .replacingOccurrences(of: #"\\"#, with: #"\"#)
        }
        for match in matches.reversed() {
            if let range = Range(match.range, in: body) { body.removeSubrange(range) }
        }
        if let variant = tags["Variant"], !["standard", "chess"].contains(variant.lowercased()) { throw ChessDocumentError.invalidPGN("暂不支持棋种：\(variant)") }
        let initial = try GamePosition(fen: tags["FEN"] ?? GamePosition.starting.fen)
        var record = GameRecord(position: initial)
        record.tags.merge(tags) { _, new in new }
        var tokens: [String] = []
        var token = ""
        var comment = false
        var lineComment = false
        func flush() { if !token.isEmpty { tokens.append(token); token = "" } }
        for character in body {
            if lineComment {
                if character.isNewline { lineComment = false }
                continue
            }
            if comment {
                if character == "}" { tokens.append("{" + token + "}"); token = ""; comment = false }
                else { token.append(character) }
            } else if character == "{" { flush(); comment = true }
            else if character == ";" { flush(); lineComment = true }
            else if character == "(" || character == ")" { flush(); tokens.append(String(character)) }
            else if character.isWhitespace { flush() }
            else { token.append(character) }
        }
        guard !comment else { throw ChessDocumentError.invalidPGN("注释未闭合") }
        flush()
        var index = 0
        var branches: [GameBranch] = []
        var finalResult: String?
        func parse(prefix: [Move], nested: Bool, depth: Int) throws -> ([Move], [Int: String]) {
            guard depth < 32 else { throw ChessDocumentError.invalidPGN("变例嵌套过深") }
            var moves = prefix
            var position = initial
            for move in prefix { position.make(move) }
            var comments: [Int: String] = [:]
            var ended = false
            while index < tokens.count {
                let raw = tokens[index]; index += 1
                if raw == ")" {
                    guard nested else { throw ChessDocumentError.invalidPGN("多余的变例括号") }
                    return (moves, comments)
                }
                if raw == "(" {
                    guard !moves.isEmpty else { throw ChessDocumentError.invalidPGN("变例没有对应着法") }
                    let (branchMoves, branchComments) = try parse(prefix: Array(moves.dropLast()), nested: true, depth: depth + 1)
                    branches.append(GameBranch(name: "导入变例 \(branches.count + 1)", moves: branchMoves, comments: branchComments))
                    continue
                }
                if raw.hasPrefix("{") {
                    let text = String(raw.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    comments[moves.count, default: ""] += (comments[moves.count] == nil ? "" : "\n") + text
                    continue
                }
                if raw.hasPrefix("$") { continue }
                var text = raw.replacingOccurrences(of: #"^\d+\.{1,3}"#, with: "", options: .regularExpression)
                if text == "..." || text.isEmpty { continue }
                if ["1-0", "0-1", "1/2-1/2", "*"].contains(text) {
                    if !nested { finalResult = text }
                    ended = true; continue
                }
                guard !ended else { throw ChessDocumentError.invalidPGN("结果后出现走法，请一次导入一盘棋") }
                text = text.replacingOccurrences(of: "e.p.", with: "")
                if text.isEmpty { continue }
                guard moves.count < 10_000 else { throw ChessDocumentError.invalidPGN("棋谱过长") }
                let move = try SAN.move(text, in: position)
                moves.append(move); position.make(move)
            }
            guard !nested else { throw ChessDocumentError.invalidPGN("变例括号未闭合") }
            return (moves, comments)
        }
        (record.moves, record.comments) = try parse(prefix: [], nested: false, depth: 0)
        record.branches = branches
        if let finalResult {
            if let headerResult = tags["Result"], headerResult != finalResult {
                throw ChessDocumentError.invalidPGN("棋局结果与标签不一致")
            }
            record.tags["Result"] = finalResult
        }
        guard ["*", "1-0", "0-1", "1/2-1/2"].contains(record.tags["Result"] ?? "*") else {
            throw ChessDocumentError.invalidPGN("结果无效")
        }
        record.cursor = record.moves.count
        return try record.validated()
    }

    public static func encode(_ record: GameRecord) -> String {
        guard let initial = try? GamePosition(fen: record.initialFEN) else { return "" }
        var tags = record.tags
        if record.initialFEN != GamePosition.starting.fen { tags["SetUp"] = "1"; tags["FEN"] = record.initialFEN }
        else { tags.removeValue(forKey: "SetUp"); tags.removeValue(forKey: "FEN") }
        tags["Result"] = tags["Result"] ?? "*"
        func escaped(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: " ")
        }
        let header = tags.keys.sorted().map { "[\($0) \"\(escaped(tags[$0]!))\"]" }.joined(separator: "\n")
        let pending = record.branches.filter { $0.moves != record.moves }
        var emitted: Set<UUID> = []
        func line(_ moves: [Move], comments: [Int: String], from start: Int, depth: Int) -> String {
            var position = initial
            for move in moves.prefix(start) { position.make(move) }
            var words: [String] = []
            if start == 0, let comment = comments[0] { words.append("{\(comment.replacingOccurrences(of: "}", with: "").replacingOccurrences(of: "{", with: ""))}") }
            for i in start..<moves.count {
                if position.sideToMove == .white { words.append("\(position.plyCount / 2 + 1).") }
                else if i == start { words.append("\(position.plyCount / 2 + 1)...") }
                words.append(SAN.string(for: moves[i], in: position))
                position.make(moves[i])
                if let comment = comments[i + 1] { words.append("{\(comment.replacingOccurrences(of: "}", with: "").replacingOccurrences(of: "{", with: ""))}") }
                if depth < 32 {
                    let alternatives = pending.filter {
                        !emitted.contains($0.id) && $0.moves.count > i
                        && Array($0.moves.prefix(i)) == Array(moves.prefix(i))
                        && ($0.moves[i] != moves[i] || (i == moves.count - 1 && $0.moves.count > moves.count))
                    }
                    for branch in alternatives where !emitted.contains(branch.id) {
                        emitted.insert(branch.id)
                        words.append("(" + line(branch.moves, comments: branch.comments, from: i, depth: depth + 1) + ")")
                    }
                }
            }
            return words.joined(separator: " ")
        }
        return header + "\n\n" + line(record.moves, comments: record.comments, from: 0, depth: 0) + " " + (tags["Result"] ?? "*") + "\n"
    }
}

public struct PGNImportFailure: Equatable, Sendable {
    public let index: Int
    public let message: String
}
public struct PGNCollection: Sendable {
    public let games: [GameRecord]
    public let failures: [PGNImportFailure]
}
extension PGN {
    /// Split only at top-level game boundaries; brackets inside comments are not headers.
    public static func decodeCollection(_ input: String) throws -> PGNCollection {
        guard input.utf8.count <= 50_000_000 else { throw ChessDocumentError.invalidPGN("文件超过 50 MB，请分批导入") }
        let chars = Array(input); var start = 0; var i = 0; var depth = 0
        var comment = false; var lineComment = false; var body = false; var finished = false
        var chunks: [String] = []
        func append(_ end: Int) {
            let value = String(chars[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { chunks.append(value) }
            start = end; body = false; finished = false; depth = 0
        }
        while i < chars.count {
            let c = chars[i]
            if comment { if c == "}" { comment = false }; i += 1; continue }
            if lineComment { if c.isNewline { lineComment = false }; i += 1; continue }
            if c == "{" { comment = true; i += 1; continue }
            if c == ";" { lineComment = true; i += 1; continue }
            if c == "[" && depth == 0 {
                if body { append(i) }
                i += 1; var quoted = false; var escaped = false
                while i < chars.count {
                    let t = chars[i]; i += 1
                    if escaped { escaped = false; continue }
                    if t == "\\" && quoted { escaped = true; continue }
                    if t == "\"" { quoted.toggle() }
                    if t == "]" && !quoted { break }
                }
                continue
            }
            if c == "(" { depth += 1; i += 1; continue }
            if c == ")" { depth = max(0, depth - 1); i += 1; continue }
            if c.isWhitespace { i += 1; continue }
            let tokenStart = i
            while i < chars.count && !chars[i].isWhitespace && !["{", ";", "(", ")", "["].contains(chars[i]) { i += 1 }
            if i == tokenStart { i += 1; continue }
            if depth == 0 {
                if finished { append(tokenStart) }
                body = true
                let token = String(chars[tokenStart..<i])
                if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) { finished = true }
            }
        }
        append(chars.count)
        var games: [GameRecord] = []; var failures: [PGNImportFailure] = []
        for (index, chunk) in chunks.enumerated() {
            do { games.append(try decode(chunk)) }
            catch { failures.append(PGNImportFailure(index: index + 1, message: error.localizedDescription)) }
        }
        return PGNCollection(games: games, failures: failures)
    }
}
