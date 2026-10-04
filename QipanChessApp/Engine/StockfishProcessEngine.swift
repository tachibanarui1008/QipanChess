#if os(macOS)
import Foundation
import GameCore

private final class UCIAsyncLineReader: @unchecked Sendable {
    private let handle: FileHandle
    private let queue = DispatchQueue(label: "qipan.stockfish.output")
    private var buffer = Data()

    init(handle: FileHandle) {
        self.handle = handle
    }

    func nextLine() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                while true {
                    if let newline = buffer.firstIndex(of: 0x0A) {
                        let lineData = buffer[..<newline]
                        let line = String(decoding: lineData, as: UTF8.self)
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        buffer.removeSubrange(...newline)
                        continuation.resume(returning: line)
                        return
                    }

                    let data = handle.availableData
                    guard !data.isEmpty else {
                        continuation.resume(throwing: ChessEngineError.unexpectedEndOfOutput)
                        return
                    }
                    buffer.append(data)
                }
            }
        }
    }
}

public actor StockfishProcessEngine: ChessEngine {
    nonisolated public let name = "Stockfish 18"

    private let executableURL: URL?
    private var process: Process?
    private var standardInput: Pipe?
    private var standardOutput: Pipe?
    private var lineReader: UCIAsyncLineReader?
    private var analysisInProgress = false
    private var activeSearchID: UUID?

    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL
    }

    public func start() async throws {
        if process?.isRunning == true { return }
        guard let executableURL else {
            throw ChessEngineError.executableNotConfigured
        }
        guard FileManager.default.isExecutableFile(atPath: executableURL.path) else {
            throw ChessEngineError.executableNotRunnable(executableURL.path)
        }

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executableURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw ChessEngineError.failedToLaunch(error.localizedDescription)
        }

        let reader = UCIAsyncLineReader(handle: output.fileHandleForReading)
        self.process = process
        self.standardInput = input
        self.standardOutput = output
        self.lineReader = reader

        try send("uci")
        try await waitForLine("uciok")
        try send("setoption name Threads value 2")
        try send("setoption name Hash value 64")
        try send("setoption name UCI_ShowWDL value true")
        try send("isready")
        try await waitForLine("readyok")
    }

    public func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        while analysisInProgress {
            try await Task.sleep(for: .milliseconds(20))
        }
        try Task.checkCancellation()
        analysisInProgress = true
        defer { analysisInProgress = false }

        try await start()
        try Task.checkCancellation()
        guard let lineReader else { throw ChessEngineError.unexpectedEndOfOutput }

        try send("setoption name MultiPV value \(limit.multiPV)")
        if let history = limit.history {
            let moves = history.moves.map(\.uci).joined(separator: " ")
            try send("position fen \(history.initialFEN)" + (moves.isEmpty ? "" : " moves \(moves)"))
        } else { try send("position fen \(position.fen)") }
        let rootMoves = limit.rootMoves.map(\.uci).joined(separator: " ")
        try send("go depth \(limit.depth)" + (rootMoves.isEmpty ? "" : " searchmoves \(rootMoves)"))

        let searchID = UUID()
        activeSearchID = searchID
        defer { activeSearchID = nil }
        return try await withTaskCancellationHandler {
            try await readResult(from: lineReader)
        } onCancel: {
            Task { await self.cancelSearch(searchID) }
        }
    }

    private func cancelSearch(_ id: UUID) {
        guard activeSearchID == id else { return }
        try? send("stop")
    }

    private func readResult(from lineReader: UCIAsyncLineReader) async throws -> EngineResult {
        var latestScore: EngineScore?
        var latestDepth = 0
        var latestPV: [Move] = []
        var latestTime = 0
        var latestNodes = 0
        var latestVariations: [Int: UCIInfoUpdate] = [:]

        while true {
            let line = try await lineReader.nextLine()

            if line.hasPrefix("info ") {
                if line.contains(" lowerbound") || line.contains(" upperbound") { continue }
                let update = parseInfo(line)
                if update.multiPV == 1 {
                    if let score = update.score { latestScore = score }
                    if let depth = update.depth { latestDepth = depth }
                    if !update.principalVariation.isEmpty { latestPV = update.principalVariation }
                    if let time = update.elapsedMilliseconds { latestTime = time }
                    if let nodes = update.nodes { latestNodes = nodes }
                }
                if update.score != nil, !update.principalVariation.isEmpty {
                    latestVariations[update.multiPV] = update
                }
                continue
            }

            if line.hasPrefix("bestmove ") {
                // Drain the cancelled search before allowing another UCI request.
                try Task.checkCancellation()
                let fields = line.split(separator: " ")
                let bestMove = fields.count > 1 ? Move(uci: String(fields[1])) : nil
                let variations = latestVariations
                    .keys
                    .sorted()
                    .compactMap { rank -> EngineVariation? in
                        guard let update = latestVariations[rank],
                              let score = update.score
                        else { return nil }
                        return EngineVariation(
                            rank: rank,
                            score: score,
                            depth: update.depth ?? latestDepth,
                            principalVariation: update.principalVariation,
                            winProbability: update.winProbability,
                            wdl: update.wdl
                        )
                    }
                guard let score = latestScore else {
                    if bestMove == nil {
                        return EngineResult(
                            score: .centipawns(0),
                            depth: latestDepth,
                            bestMove: nil,
                            principalVariation: [],
                            elapsedMilliseconds: latestTime,
                            nodes: latestNodes,
                            variations: variations
                        )
                    }
                    throw ChessEngineError.noAnalysisResult
                }
                return EngineResult(
                    score: score,
                    depth: latestDepth,
                    bestMove: bestMove ?? latestPV.first,
                    principalVariation: latestPV,
                    elapsedMilliseconds: latestTime,
                    nodes: latestNodes,
                    variations: variations
                )
            }
        }
    }

    public func stop() async {
        if process?.isRunning == true {
            try? send("quit")
            process?.terminate()
        }
        process = nil
        standardInput = nil
        standardOutput = nil
        lineReader = nil
        analysisInProgress = false
    }

    private func waitForLine(_ expected: String) async throws {
        guard let lineReader else { throw ChessEngineError.unexpectedEndOfOutput }
        while true {
            if try await lineReader.nextLine() == expected { return }
        }
    }

    private func send(_ command: String) throws {
        guard let data = "\(command)\n".data(using: .utf8),
              let standardInput
        else { throw ChessEngineError.failedToLaunch("标准输入不可用") }
        try standardInput.fileHandleForWriting.write(contentsOf: data)
    }

    private func parseInfo(_ line: String) -> UCIInfoUpdate {
        let fields = line.split(separator: " ").map(String.init)
        var update = UCIInfoUpdate()
        var index = 0

        while index < fields.count {
            switch fields[index] {
            case "depth" where index + 1 < fields.count:
                update.depth = Int(fields[index + 1])
                index += 2
            case "time" where index + 1 < fields.count:
                update.elapsedMilliseconds = Int(fields[index + 1])
                index += 2
            case "nodes" where index + 1 < fields.count:
                update.nodes = Int(fields[index + 1])
                index += 2
            case "multipv" where index + 1 < fields.count:
                update.multiPV = Int(fields[index + 1]) ?? 1
                index += 2
            case "score" where index + 2 < fields.count:
                let kind = fields[index + 1]
                let value = Int(fields[index + 2]) ?? 0
                update.score = kind == "mate" ? .mate(value) : .centipawns(value)
                index += 3
            case "wdl" where index + 3 < fields.count:
                let wins = Double(fields[index + 1]) ?? 0
                let draws = Double(fields[index + 2]) ?? 0
                let losses = Double(fields[index + 3]) ?? 0
                let total = wins + draws + losses
                update.winProbability = total > 0 ? wins / total : nil
                update.wdl = EngineWDL(wins: Int(wins), draws: Int(draws), losses: Int(losses))
                index += 4
            case "pv":
                update.principalVariation = fields[(index + 1)...].compactMap(Move.init(uci:))
                index = fields.count
            default:
                index += 1
            }
        }
        return update
    }
}

private struct UCIInfoUpdate {
    var score: EngineScore?
    var depth: Int?
    var multiPV = 1
    var principalVariation: [Move] = []
    var elapsedMilliseconds: Int?
    var nodes: Int?
    var winProbability: Double?
    var wdl: EngineWDL?
}
#endif
