import Analysis
import GameCore
import SwiftUI
import UniformTypeIdentifiers

struct OpeningTreePanel: View {
    @ObservedObject var trees: OpeningTreeStore
    @ObservedObject var session: GameSession
    @ObservedObject var library: GameLibrary
    @ObservedObject var sync: OpeningTreeSyncCoordinator
    @ObservedObject var treeReview: OpeningTreeReviewCoordinator
    let onCalculate: (Bool) -> Void
    @Binding var selectedTreeID: UUID?
    @Binding var repertoireSide: PieceColor
    var constructing: Bool
    let onSave: (UUID) -> Void
    let onSaveAutomatically: () -> Void
    let onStart: () -> Void
    let onEdit: (OpeningTreeNode) -> Void
    var editingSAN: String? = nil
    @State private var confirmsDeleteTree = false
    @State private var showsNewTree = false
    @State private var newName = ""
    @State private var editedName = ""
    @State private var note = ""
    @State private var showsConnection = false
    @State private var saveMessage: String?
    @State private var importingTrees = false
    @State private var exportingTrees = false
    @State private var exportDocument = OpeningTreeFileDocument()
    @State private var exportName = "QipanChess-开局树.json"
    @State private var pendingImport: OpeningTreeArchive?
    @State private var confirmsImport = false
    @State private var transferMessage: String?
    @State private var transferError: String?
    @State private var sharingTrees = false
    @State private var shareURL: URL?
    private var tree: OpeningTreeDocument? { trees.tree(selectedTreeID) }
    private var nodeID: String { OpeningTreeDocument.nodeID(fen: session.record.initialFEN, moves: session.moveHistory) }
    private var available: [OpeningTreeDocument] { trees.trees.filter { $0.repertoireSide == repertoireSide || $0.repertoireSide == nil } }
    private var currentGroup: (key: String, name: String) {
        OpeningTreeDocument.firstMoveGroup(fen: session.record.initialFEN, moves: session.moveHistory, side: repertoireSide)
    }
    private var known: Bool { selectedTreeID.map { id in trees.nodes(for: id, includeHidden: true).contains { $0.id == nodeID } } ?? false }
    private var matchesFirstMove: Bool {
        guard let tree, let first = session.moveHistory.first else { return false }
        return tree.sources.contains { $0.initialFEN == session.record.initialFEN && $0.moves.first == first }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            selector
            transferActions
            if constructing { routeActions }
            if let tree { calculationActions; details(tree) }
            if !constructing && available.isEmpty { newTreeForm }
            importResources
            if let error = trees.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(16).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 16))
        .onChange(of: nodeID) { _, _ in note = tree?.notes[nodeID] ?? ""; saveMessage = nil }
        .onChange(of: selectedTreeID) { _, _ in editedName = tree?.name ?? ""; note = tree?.notes[nodeID] ?? ""; saveMessage = nil }
        .confirmationDialog("删除整棵开局树？可撤销，本地棋局会保留。", isPresented: $confirmsDeleteTree) {
            Button("删除开局树", role: .destructive) { if let id = selectedTreeID, trees.deleteTree(id) { selectedTreeID = nil } }
        }
        .onAppear { editedName = tree?.name ?? ""; note = tree?.notes[nodeID] ?? "" }
        .fileImporter(isPresented: $importingTrees, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let granted = url.startAccessingSecurityScopedResource()
                defer { if granted { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= OpeningTreeArchive.maximumBytes else { throw ChessDocumentError.invalidPGN("开局树文件不能超过 50 MB") }
                let archive = try OpeningTreeArchive.decode(Data(contentsOf: url))
                transferError = nil; transferMessage = nil
                if archive.trees.contains(where: { trees.tree($0.id) != nil }) {
                    pendingImport = archive; confirmsImport = true
                } else { importTrees(archive, replacing: false) }
            } catch { transferError = error.localizedDescription }
        }
        .fileExporter(isPresented: $exportingTrees, document: exportDocument, contentType: .json, defaultFilename: exportName) { result in
            switch result {
            case .success: transferMessage = "开局树已导出"
            case .failure(let error): transferError = error.localizedDescription
            }
        }
        .confirmationDialog("文件中有本机已有的开局树。替换会使用文件中的完整版本，包括备注和删除状态；本机原文件会备份。", isPresented: $confirmsImport, titleVisibility: .visible) {
            Button("备份并替换已有树") {
                if let archive = pendingImport { importTrees(archive, replacing: true) }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        }
        #if os(iOS)
        .sheet(isPresented: $sharingTrees, onDismiss: {
            if let url = shareURL { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            shareURL = nil
        }) {
            if let url = shareURL { OpeningTreeShareSheet(url: url) }
        }
        #endif
    }
    private var calculationActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("开局树标注计算", systemImage: "cpu").font(.callout.bold())
            if treeReview.isRunning {
                ProgressView(value: Double(treeReview.completed), total: Double(max(1, treeReview.total)))
                Button("停止计算") { treeReview.cancel() }
            } else {
                Button("补齐缺失标注") { onCalculate(false) }.buttonStyle(.borderedProminent)
                Button("全部重算") { onCalculate(true) }.buttonStyle(.bordered)
            }
            Text("计算当前开局树的全部分枝（含隐藏分枝），共享步骤只算一次。完成的标注自动保存，可随开局树导出。")
                .font(.caption).foregroundStyle(.secondary)
            if let message = treeReview.message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }.controlSize(.small)
    }
    private var transferActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu {
                    Button("导出当前开局树") { if let tree { exportTrees([tree]) } }.disabled(tree == nil)
                    Button("导出全部开局树（\(trees.trees.count) 棵）") { exportTrees(trees.trees) }.disabled(trees.trees.isEmpty)
                } label: { Label("导出开局树", systemImage: "square.and.arrow.up") }
                Button { importingTrees = true } label: { Label("导入开局树", systemImage: "square.and.arrow.down") }
            }.controlSize(.small)
            Text("保留路线、备注、主线和已保存评分。可通过隔空投送或文件手动同步；请先保存当前研究。").font(.caption).foregroundStyle(.secondary)
            if let transferMessage { Text(transferMessage).font(.caption).foregroundStyle(.secondary) }
            if let transferError { Text(transferError).font(.caption).foregroundStyle(.red) }
        }
    }
    private func exportTrees(_ documents: [OpeningTreeDocument]) {
        do {
            let data = try OpeningTreeArchive(trees: documents).encoded()
            transferError = nil; transferMessage = nil
            exportName = documents.count == 1 ? "QipanChess-\(documents[0].id.uuidString).json" : "QipanChess-全部开局树.json"
            #if os(iOS)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OpeningTreeExport-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(exportName)
            try data.write(to: url, options: .atomic)
            shareURL = url; sharingTrees = true
            #else
            exportDocument = OpeningTreeFileDocument(data: data); exportingTrees = true
            #endif
        } catch { transferError = error.localizedDescription }
    }
    private func importTrees(_ archive: OpeningTreeArchive, replacing: Bool) {
        do {
            try trees.importArchive(archive, replacingExisting: replacing)
            if let first = archive.trees.first {
                if let side = first.repertoireSide { repertoireSide = side }
                selectedTreeID = first.id
                editedName = first.name; note = first.notes[nodeID] ?? ""
            }
            transferError = nil; transferMessage = "已导入 \(archive.trees.count) 棵开局树"
        } catch { transferError = error.localizedDescription }
    }
    private var selector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我的开局", systemImage: "tree.fill").font(.headline)
            HStack(spacing: 8) {
                sideButton(.white)
                sideButton(.black)
            }
            Text(repertoireSide == .white ? "开局收录终点对白方有利的路线。" : "开局收录终点对黑方有利的路线。").font(.caption).foregroundStyle(.secondary)
            if constructing {
                Label(tree?.name ?? (session.cursor == 0 ? "走出第一步，自动识别开局" : "新开局 · 保存时自动建树"), systemImage: "arrow.triangle.branch")
                    .font(.callout.bold())
            } else {
                Picker("开局树", selection: $selectedTreeID) {
                    Text("选择开局树").tag(nil as UUID?)
                    Section(repertoireSide.displayName + "有利") {
                        ForEach(available.filter { $0.repertoireSide == repertoireSide }) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Section("均衡／待评估") {
                        ForEach(available.filter { $0.repertoireSide == nil }) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            if trees.canUndoDeletion { Button("撤销上次删除") { selectedTreeID = trees.undoLastDeletion() }.font(.caption) }
            if let tree { Text("\(trees.nodes(for: tree.id).filter { $0.move != nil }.count) 步已收录").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func sideButton(_ side: PieceColor) -> some View {
        Button { repertoireSide = side } label: {
            HStack(spacing: 7) {
                Circle().fill(side == .white ? AppTheme.treeWhite : AppTheme.treeBlack).frame(width: 15, height: 15)
                    .overlay(Circle().stroke(AppTheme.treeBlack.opacity(0.3)))
                Text(side == .white ? "白方有利" : "黑方有利").font(.caption.bold())
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(repertoireSide == side ? AppTheme.accent.opacity(0.16) : Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(repertoireSide == side ? AppTheme.accent : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(repertoireSide == side ? .isSelected : [])
    }
    private var routeActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            if let editingSAN { Text("正在修改 \(editingSAN)，在棋盘走出替代走法后保存。").font(.caption).foregroundStyle(AppTheme.accent) }
            Label(session.cursor == 0 ? "开始构建" : (known ? "已收录路线" : "未保存的路线"), systemImage: known && session.cursor > 0 ? "checkmark.circle" : "pencil.and.outline")
                .font(.callout.bold()).foregroundStyle(known ? .secondary : AppTheme.accent)
            Text(known && session.cursor > 0 ? "浏览已有走法直接读取记录，不重复计算。" : "在棋盘上试走，回到任意一步可添加新的变化。保存后才会写入开局树。")
                .font(.caption).foregroundStyle(.secondary)
            if session.cursor > 0 {
                Button { onSaveAutomatically(); saveMessage = "路线已保存" } label: {
                    Label(tree == nil ? "保存新开局" : (known ? "保存当前路线" : "保存新分枝"), systemImage: "square.and.arrow.down")
                }.buttonStyle(.borderedProminent).tint(AppTheme.accent).controlSize(.small)
            }
            Button { onStart() } label: { Label("从起始局面试走", systemImage: "arrow.counterclockwise") }.buttonStyle(.plain).font(.caption)
            if let saveMessage { Label(saveMessage, systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
        }
    }
    @ViewBuilder private func details(_ tree: OpeningTreeDocument) -> some View {
        if let node = trees.nodes(for: tree.id, includeHidden: true).first(where: { $0.id == nodeID }), node.move != nil {
            Divider()
            HStack {
                Circle().fill(node.side == .black ? AppTheme.treeBlack : AppTheme.treeWhite).frame(width: 12, height: 12).overlay(Circle().stroke(.secondary.opacity(0.3)))
                Text((node.side?.displayName ?? "") + " · " + node.san).font(.callout.bold())
            }
            if let item = node.annotation?.review { MoveClassificationLabel(classification: item.classification); Text(item.explanation).font(.caption).foregroundStyle(.secondary) }
            else { Text("待分析").font(.caption).foregroundStyle(.secondary) }
            if constructing {
                TextField("这一步的想法与计划", text: $note, axis: .vertical).textFieldStyle(.roundedBorder)
                Button("保存备注") { trees.update(tree.id) { $0.notes[nodeID] = note }; saveMessage = "备注已保存" }.controlSize(.small)
                Button("修改这一步") { onEdit(node) }.controlSize(.small)
                Menu("删除步骤") {
                    Button("删除这一步之后的所有走法", role: .destructive) { trees.deleteBranch(tree.id, node: node); saveMessage = "已删除后续走法，可撤销" }.disabled(node.children.isEmpty)
                    Button("连同这一步一起删除", role: .destructive) { trees.deleteBranch(tree.id, node: node, includeNode: true); onEdit(node) }
                }.font(.caption)
                Button("隐藏此分枝") { trees.update(tree.id) { $0.hidden.insert(nodeID) } }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            } else if let text = tree.notes[nodeID], !text.isEmpty { Text(text).font(.caption) }
        }
        if constructing {
            DisclosureGroup("开局树设置") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("删除整棵开局树", role: .destructive) { confirmsDeleteTree = true }
                    TextField("树名", text: $editedName).textFieldStyle(.roundedBorder)
                    Button("保存名称") { let name = editedName.trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty { trees.update(tree.id) { $0.name = name } } }
                    Stepper("收录前 \(tree.maxPlies / 2) 回合", value: Binding(get: { max(1, tree.maxPlies / 2) }, set: { value in trees.update(tree.id) { $0.maxPlies = value * 2 } }), in: 1...200)
                    if !tree.hidden.isEmpty {
                        DisclosureGroup("恢复隐藏分枝 · \(tree.hidden.count)") {
                            ForEach(trees.nodes(for: tree.id, includeHidden: true).filter { tree.hidden.contains($0.id) }) { node in
                                Button("恢复 \(node.san) · 第 \(node.moves.count) 手") { trees.update(tree.id) { $0.hidden.remove(node.id) } }
                            }
                        }
                    }
                }.font(.caption).padding(.top, 8)
            }.font(.caption)
        }
    }
    private var newTreeForm: some View {
        DisclosureGroup("新建开局树", isExpanded: $showsNewTree) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("给自己的开局命名", text: $newName).textFieldStyle(.roundedBorder)
                Text(repertoireSide.displayName + " · " + (session.cursor > 0 ? "包含当前试走路线" : "请先在棋盘走出第一步")).font(.caption).foregroundStyle(.secondary)
                Button("新建并保存路线") {
                    let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, session.cursor > 0 else { return }
                    let existing = session.cursor > 0 ? available.first { $0.groupingKey == currentGroup.key } : nil
                    let id = existing?.id ?? trees.create(name: name, groupingKey: session.cursor > 0 ? currentGroup.key : nil, side: repertoireSide)
                    selectedTreeID = id
                    trees.bind(id, to: session.record)
                    if session.cursor > 0 { onSave(id) }
                    showsNewTree = false; newName = ""; saveMessage = "开局树已保存"
                }.buttonStyle(.borderedProminent).controlSize(.small).disabled(session.cursor == 0 || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(.top, 8)
        }.font(.caption)
    }
    private var importResources: some View {
        DisclosureGroup("补充开局资源", isExpanded: $showsConnection) {
            VStack(alignment: .leading, spacing: 10) {
                Text("公开棋谱仅用于补充你的白方与黑方开局路线。").font(.caption).foregroundStyle(.secondary)
                TextField("公开用户名", text: $sync.username).textFieldStyle(.roundedBorder).disabled(sync.isFetching || sync.isAnalyzing)
                if sync.isFetching { Button("停止导入") { sync.stopFetching() } }
                else { Button("导入开局资源") { sync.synchronize() }.disabled(sync.isAnalyzing) }
                if sync.isAnalyzing { Button(sync.isPaused ? "继续整理" : "暂停整理") { if sync.isPaused { sync.resume() } else { sync.pause() } } }
                Text(sync.isFetching || sync.isAnalyzing ? sync.message : "开局资源已在本地保存，可离线使用。").font(.caption).foregroundStyle(.secondary)
                if !sync.issues.isEmpty { Text("\(sync.issues.count) 条资源未能导入").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.top, 8)
        }.font(.caption)
    }
}
