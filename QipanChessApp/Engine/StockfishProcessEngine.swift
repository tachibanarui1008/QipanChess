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
        try send("isready")
        try await waitForLine("readyok")
    }

    public func analyze(position: GamePosition, limit: AnalysisLimit) async throws -> EngineResult {
        while analysisInProgress {
            try await Task.sleep(for: .milliseconds(20))
        }
        analysisInProgress = true
        defer { analysisInProgress = false }

        try await start()
        guard let lineReader else { throw ChessEngineError.unexpectedEndOfOutput }

        try send("position fen \(position.fen)")
        try send("go depth \(limit.depth)")

        var latestScore: EngineScore?
        var latestDepth = 0
        var latestPV: [Move] = []
        var latestTime = 0
        var latestNodes = 0

        while true {
            let line = try await lineReader.nextLine()

            if line.hasPrefix("info ") {
                let update = parseInfo(line)
                if let score = update.score { latestScore = score }
                if let depth = update.depth { latestDepth = depth }
                if !update.principalVariation.isEmpty { latestPV = update.principalVariation }
                if let time = update.elapsedMilliseconds { latestTime = time }
                if let nodes = update.nodes { latestNodes = nodes }
                continue
            }

            if line.hasPrefix("bestmove ") {
                let fields = line.split(separator: " ")
                let bestMove = fields.count > 1 ? Move(uci: String(fields[1])) : nil
                guard let score = latestScore else {
                    if bestMove == nil {
                        return EngineResult(
                            score: .centipawns(0),
                            depth: latestDepth,
                            bestMove: nil,
                            principalVariation: [],
                            elapsedMilliseconds: latestTime,
                            nodes: latestNodes
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
                    nodes: latestNodes
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
            case "score" where index + 2 < fields.count:
                let kind = fields[index + 1]
                let value = Int(fields[index + 2]) ?? 0
                update.score = kind == "mate" ? .mate(value) : .centipawns(value)
                index += 3
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
    var principalVariation: [Move] = []
    var elapsedMilliseconds: Int?
    var nodes: Int?
}
#endif
