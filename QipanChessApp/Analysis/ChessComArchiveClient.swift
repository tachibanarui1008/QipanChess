import Foundation

public struct ArchiveFetch: Sendable { public var data: Data; public var etag: String?; public var modified: String? }
public protocol ArchiveTransport: Sendable { func fetch(url: URL, etag: String?, modified: String?) async throws -> ArchiveFetch? }
public enum ArchiveError: LocalizedError {
    case response(Int), invalidUsername, malformed
    public var errorDescription: String? {
        switch self {
        case .response(404): "找不到该账号或归档。"
        case .response(403): "公开接口暂时拒绝请求，可稍后重试或导入 PGN。"
        case .response(let n): "Chess.com 接口返回 \(n)。"
        case .invalidUsername: "请输入有效的 Chess.com 用户名。"
        case .malformed: "归档格式无效。"
        }
    }
}
public struct URLSessionArchiveTransport: ArchiveTransport {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public func fetch(url: URL, etag: String?, modified: String?) async throws -> ArchiveFetch? {
        for attempt in 0..<4 {
            try Task.checkCancellation()
            var request = URLRequest(url: url); request.timeoutInterval = 30
            request.setValue("QipanChess/1.0 (public personal chess archive)", forHTTPHeaderField: "User-Agent")
            if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw ArchiveError.malformed }
            if http.statusCode == 304 { return nil }
            if http.statusCode == 429 && attempt < 3 {
                let delay = min(60, max(1, Double(http.value(forHTTPHeaderField: "Retry-After") ?? "") ?? pow(2, Double(attempt + 1))))
                try await Task.sleep(for: .seconds(delay)); continue
            }
            guard http.statusCode == 200 else { throw ArchiveError.response(http.statusCode) }
            return ArchiveFetch(data: data, etag: http.value(forHTTPHeaderField: "ETag"), modified: http.value(forHTTPHeaderField: "Last-Modified"))
        }
        throw ArchiveError.response(429)
    }
}
public actor ChessComArchiveClient {
    private let directory: URL
    private let transport: any ArchiveTransport
    private struct Cache: Codable { var data: Data; var etag: String?; var modified: String? }
    public init(directory: URL, transport: any ArchiveTransport = URLSessionArchiveTransport()) { self.directory = directory; self.transport = transport }
    public func username(_ value: String) throws -> String {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !clean.isEmpty, clean.count <= 64, clean.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { throw ArchiveError.invalidUsername }
        return clean
    }
    public func archives(for value: String) async throws -> [URL] {
        let name = try username(value)
        let data = try await cached(url: URL(string: "https://api.chess.com/pub/player/\(name)/games/archives")!, key: name + "-archives")
        struct Response: Decodable { var archives: [String] }
        return try JSONDecoder().decode(Response.self, from: data).archives.compactMap { text in
            guard let url = URL(string: text), url.scheme == "https", url.host == "api.chess.com", url.path.hasPrefix("/pub/player/\(name)/games/") else { return nil }; return url
        }.sorted { $0.absoluteString > $1.absoluteString }
    }
    public func month(_ url: URL) async throws -> [ChessComGame] {
        guard url.scheme == "https", url.host == "api.chess.com" else { throw ArchiveError.malformed }
        let data = try await cached(url: url, key: url.path.replacingOccurrences(of: "/", with: "-"))
        struct Response: Decodable { var games: [ChessComGame] }
        return try JSONDecoder().decode(Response.self, from: data).games
    }
    private func cached(url: URL, key: String) async throws -> Data {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(key + ".json")
        let old = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Cache.self, from: $0) }
        do {
            if let fresh = try await transport.fetch(url: url, etag: old?.etag, modified: old?.modified) {
                let value = Cache(data: fresh.data, etag: fresh.etag, modified: fresh.modified)
                try JSONEncoder().encode(value).write(to: file, options: .atomic); return fresh.data
            }
            guard let old else { throw ArchiveError.malformed }; return old.data
        } catch is CancellationError { throw CancellationError() }
        catch {
            if let old, !(error is ArchiveError) { return old.data }
            throw error
        }
    }
}
public struct ChessComGame: Decodable, Sendable {
    public var url: String
    public var pgn: String?
    public var rules: String?
    public var time_class: String?
    public var end_time: Int?
}
