import Analysis
import GameCore
import SwiftUI
import UniformTypeIdentifiers

struct PGNFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, UTType(filenameExtension: "pgn") ?? .plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let text = String(data: data, encoding: .utf8) else { throw ChessDocumentError.invalidPGN("需要 UTF-8 文本") }
        self.text = text
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct GameLibraryView: View {
    @ObservedObject var session: GameSession
    @ObservedObject var library: GameLibrary
    let onLoad: (GameRecord) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var importText = ""
    @State private var error: String?
    @State private var importing = false
    @State private var exporting = false
    @State private var white = ""
    @State private var black = ""
    @State private var comment = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("棋局库").font(.title2.bold())
                Spacer()
                Button("返回棋盘") { dismiss() }.buttonStyle(.bordered)
            }.padding()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                    if let error = library.errorMessage { Text(error).foregroundStyle(.red).font(.callout) }
                    libraryContent
                }.padding()
            }
        }
        .frame(minWidth: 320, idealWidth: 850, maxWidth: .infinity, minHeight: 500, idealHeight: 740, maxHeight: .infinity)
        .background(AppTheme.appBackground)
        .onAppear { white = session.record.tags["White"] ?? ""; black = session.record.tags["Black"] ?? ""; comment = session.record.comments[session.cursor] ?? "" }
        .fileImporter(isPresented: $importing, allowedContentTypes: PGNFileDocument.readableContentTypes) { result in
            do {
                let url = try result.get(); let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                guard data.count <= 50_000_000, let text = String(data: data, encoding: .utf8) else {
                    throw ChessDocumentError.invalidPGN("需要不超过 50 MB 的 UTF-8 棋谱")
                }
                try importGame(text)
            } catch { self.error = error.localizedDescription }
        }
        .fileExporter(isPresented: $exporting, document: PGNFileDocument(text: PGN.encode(session.record)),
                      contentType: .plainText, defaultFilename: "QipanChess.pgn") { result in
            if case .failure(let failure) = result { error = failure.localizedDescription }
        }
    }
    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前棋局").font(.headline)
            HStack { TextField("白方", text: $white); TextField("黑方", text: $black) }
                .textFieldStyle(.roundedBorder)
            ViewThatFits(in: .horizontal) {
                HStack { saveGameButton; exportGameButton; importGameButton }
                VStack(alignment: .leading) { saveGameButton; HStack { exportGameButton; importGameButton } }
            }.buttonStyle(.bordered)
            Text("每次走棋和回放进度都会自动保存到本机，重启后恢复上次棋局。")
                .font(.caption).foregroundStyle(.secondary)
            Text("导入 PGN 或 FEN").font(.headline)
            TextEditor(text: $importText).font(.system(.caption, design: .monospaced)).frame(height: 115)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.3)))
            Button("载入文本") {
                do { try importGame(importText) } catch { self.error = error.localizedDescription }
            }.buttonStyle(.borderedProminent)
            Divider()
            Text("第 \(session.cursor) 手的备注").font(.headline)
            TextField("记录你的计算和计划", text: $comment, axis: .vertical).textFieldStyle(.roundedBorder)
            Button("保存备注") { session.setComment(comment) }
            if !session.record.branches.isEmpty {
                Text("保留的分析路线").font(.headline)
                ForEach(session.record.branches) { branch in
                    Button("\(branch.name) · \(branch.moves.count) 手") {
                        do {
                            var copy = session.record
                            copy.branches.removeAll { $0.id == branch.id }
                            copy.branches.append(GameBranch(name: "原路线", moves: copy.moves, comments: copy.comments))
                            copy.moves = branch.moves; copy.comments = branch.comments; copy.cursor = min(copy.cursor, branch.moves.count)
                            copy.tags["Result"] = "*"
                            onLoad(try copy.validated()); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.buttonStyle(.bordered)
                }
            }
            Divider()
            Text("本地棋局 · \(library.games.count) 盘").font(.headline)
            if library.games.isEmpty { Text("走出第一步后，这里会出现你的棋局。").foregroundStyle(.secondary) }
            ForEach(library.games) { game in
                Button { onLoad(game); dismiss() } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.title).font(.callout.bold())
                            Text("\(game.moves.count) 手 · \(game.tags["Result"] ?? "*") · \(game.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(10).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }
        }
    }
    private var saveGameButton: some View {
        Button("保存棋局") { session.setPlayers(white: white, black: black); _ = library.save(session.record) }
    }
    private var exportGameButton: some View { Button("导出 PGN") { exporting = true } }
    private var importGameButton: some View { Button("导入文件") { importing = true } }

    private func importGame(_ input: String) throws {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChessDocumentError.invalidPGN("请输入棋谱或局面") }
        let game: GameRecord
        if text.split(whereSeparator: \.isWhitespace).count == 6 && text.contains("/") && !text.contains("[") {
            game = GameRecord(position: try GamePosition(fen: text))
        } else {
            let collection = try PGN.decodeCollection(text)
            guard let first = collection.games.first else { throw ChessDocumentError.invalidPGN(collection.failures.first?.message ?? "没有可用棋局") }
            for item in collection.games { _ = library.importRecord(item) }
            game = library.importRecord(first)
            if !collection.failures.isEmpty { error = "已导入 \(collection.games.count) 盘，\(collection.failures.count) 盘无法读取。"; onLoad(game); return }
        }
        onLoad(game); _ = library.save(game); dismiss()
    }

}

struct ReviewChart: View {
    let moves: [ReviewedMove]
    let selected: Int
    var perspective: PieceColor = .white
    let onSelect: (Int) -> Void
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }.stroke(.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                Path { path in
                    for (i, move) in moves.enumerated() {
                        let point = CGPoint(x: CGFloat(move.index - 1) / CGFloat(max(1, (moves.last?.index ?? 1) - 1)) * geometry.size.width,
                                            y: geometry.size.height * CGFloat(0.5 - move.whiteEvaluation * (perspective == .white ? 1 : -1) / 20))
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(AppTheme.accent, lineWidth: 2)
                ForEach(moves) { move in
                    Button { onSelect(move.index) } label: {
                        MoveQualityBadge(classification: move.classification, size: selected == move.index ? 22 : 16)
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .position(x: CGFloat(move.index - 1) / CGFloat(max(1, (moves.last?.index ?? 1) - 1)) * geometry.size.width,
                                  y: geometry.size.height * CGFloat(0.5 - move.whiteEvaluation * (perspective == .white ? 1 : -1) / 20))
                        .accessibilityLabel("第 \(move.index) 手，\(move.classification.title)")
                }
            }
        }.animation(.easeInOut(duration: 0.25), value: moves).padding(12).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topLeading) { Text("\(perspective.displayName)视角 · ±10").font(.caption2).padding(6) }
    }
}
