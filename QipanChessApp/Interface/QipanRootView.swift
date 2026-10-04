import Analysis
import GameCore
import SwiftUI

@MainActor
public struct QipanRootView: View {
    @StateObject private var session: GameSession
    @StateObject private var analysis: AnalysisCoordinator
    @StateObject private var library: GameLibrary
    @StateObject private var review: GameReviewCoordinator
    @StateObject private var trees: OpeningTreeStore
    @StateObject private var sync: OpeningTreeSyncCoordinator
    @StateObject private var treeReview = OpeningTreeReviewCoordinator()
    @State private var selectedTreeID: UUID?
    @State private var repertoireSide: PieceColor = .white
    @State private var researchRecordID = UUID()
    @State private var windowWidth: CGFloat = 1360
    @State private var windowHeight: CGFloat = 820
    @State private var showsGameLibrary = false
    @State private var showsPositionSetup = false
    @AppStorage("qipan.showMoveClassification") private var showsMoveClassification = true
    @State private var workspaceError: String?
    @State private var appMode: ChessAppMode = .analysis
    @State private var isCompactSideDockExpanded = false
    @State private var humanColor: PieceColor = .white
    @State private var aiDifficulty: AIDifficulty = .standard
    @State private var aiStrategy: StrategyType = .balanced
    @State private var isAIThinking = false
    @State private var aiErrorMessage: String?
    @State private var aiGameGeneration = 0
    @State private var selectedStrategy: StrategyType? = .balanced

    private let backgroundEnabled: Bool
    public init(dataDirectory: URL? = nil, startsBuilding: Bool = false, backgroundEnabled: Bool = true) {
        self.backgroundEnabled = backgroundEnabled
        let library = GameLibrary(directory: dataDirectory?.appendingPathComponent("Library"))
        let trees = OpeningTreeStore(directory: dataDirectory?.appendingPathComponent("OpeningTrees"))
        let sync = OpeningTreeSyncCoordinator(library: library, trees: trees, directory: dataDirectory?.appendingPathComponent("ChessCom"))
        trees.curateByAdvantage()
        let startsInBuilder = startsBuilding || ProcessInfo.processInfo.arguments.contains("--opening-tree-builder")
        let savedMode = UserDefaults.standard.string(forKey: "qipan.lastMode").flatMap(ChessAppMode.init(rawValue:)) ?? .analysis
        _appMode = State(initialValue: startsInBuilder ? .treeBuilder : (ProcessInfo.processInfo.arguments.contains("--free-analysis") ? .analysis : savedMode))
        let session = GameSession()
        if let lastID = UserDefaults.standard.string(forKey: "qipan.lastGame"),
           let game = library.games.first(where: { $0.id.uuidString == lastID }) {
            try? session.load(game)
        }
        let review = GameReviewCoordinator()
        review.restore(library.review(for: session.record))
        _session = StateObject(wrappedValue: session)
        _analysis = StateObject(wrappedValue: AnalysisCoordinator(initialPosition: session.position))
        _library = StateObject(wrappedValue: library)
        _review = StateObject(wrappedValue: review)
        _trees = StateObject(wrappedValue: trees)
        _sync = StateObject(wrappedValue: sync)
        let selected = trees.boundTree(for: session.record) ?? trees.trees.filter { ($0.repertoireSide ?? .white) == .white }.max(by: { $0.sources.count < $1.sources.count })?.id
        _selectedTreeID = State(initialValue: selected)
        _repertoireSide = State(initialValue: trees.tree(selected)?.repertoireSide ?? .white)
    }

    private var workspaceContent: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 1180 && appMode == .treeBuilder {
                    constructionLayout
                } else if proxy.size.width >= 1180 {
                    threeColumnLayout
                } else if proxy.size.width >= 720 && appMode == .treeBuilder {
                    verticalConstructionLayout
                } else if proxy.size.width >= 720 {
                    mediumLayout
                } else {
                    compactLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.appBackground)
            .onAppear { windowHeight = proxy.size.height; windowWidth = proxy.size.width }
            .onChange(of: proxy.size.height) { _, height in windowHeight = height }
            .onChange(of: proxy.size.width) { _, width in windowWidth = width }
        }
        .onChange(of: session.position) { _, newPosition in
            updateAnalysis(for: session.position == newPosition ? newPosition : session.position)
        }
        .onChange(of: session.record) { _, record in
            if !record.moves.isEmpty || record.initialFEN != GamePosition.starting.fen || library.games.contains(where: { $0.id == record.id }) {
                if library.save(record) { UserDefaults.standard.set(record.id.uuidString, forKey: "qipan.lastGame") }
            }
            if appMode == .treeBuilder { matchCurrentTree() }
            else if appMode == .analysis && !session.moveHistory.isEmpty { matchAnalysisTree() }
            updateReview(for: record)
            if appMode != .treeBuilder { trees.synchronize(record: record, kind: sourceKind, report: library.review(for: record)) }
        }
        .onChange(of: review.report) { _, report in
            if let report, report.analysisKey == session.record.analysisKey {
                library.saveReview(report, for: session.record.id)
                if appMode == .treeBuilder { trees.saveKnownAnnotations(record: session.record, report: report, treeID: selectedTreeID) }
                else { trees.synchronize(record: session.record, kind: sourceKind, report: report) }
            }
        }
        .sheet(isPresented: $showsPositionSetup) {
            PositionSetupView(position: session.position) { position in
                if !session.record.moves.isEmpty { _ = library.save(session.record) }
                loadGame(GameRecord(position: position))
                selectedTreeID = nil
            }
        }
        .sheet(isPresented: $showsGameLibrary) {
            GameLibraryView(session: session, library: library, onLoad: loadGame)
        }
        .confirmationDialog("选择升变棋子", isPresented: Binding(
            get: { !session.pendingPromotions.isEmpty },
            set: { if !$0 { session.cancelPromotion() } }
        ), titleVisibility: .visible) {
            ForEach(session.pendingPromotions) { move in
                Button(promotionName(move.promotion)) { _ = session.make(move) }
            }
            Button("取消", role: .cancel) { session.cancelPromotion() }
        }
        .alert("棋局操作失败", isPresented: Binding(get: { workspaceError != nil }, set: { if !$0 { workspaceError = nil } })) {
            Button("好") { workspaceError = nil }
        } message: { Text(workspaceError ?? "") }
    }

    private var interactionContent: some View {
        workspaceContent
        .onChange(of: appMode) { _, mode in
            UserDefaults.standard.set(mode.rawValue, forKey: "qipan.lastMode")
            aiGameGeneration += 1; isAIThinking = false; aiErrorMessage = nil
            if mode == .analysis { review.cancel(); matchAnalysisTree() }
            if mode == .versusAI { session.seek(to: session.record.moves.count) }
            if mode == .treeBuilder { matchCurrentTree(); review.cancel(); analysis.suspend(for: session.position); session.isBoardFlipped = repertoireSide == .black }
            updateReview(for: session.record)
            updateAnalysis(for: session.position)
            updateBackgroundPriority()
        }
        .onChange(of: humanColor) { _, _ in
            guard appMode == .versusAI else { return }
            aiGameGeneration += 1; isAIThinking = false
            session.isBoardFlipped = humanColor == .black
        }
        .onChange(of: aiStrategy) { _, newStrategy in
            selectedStrategy = .balanced
            analysis.refreshSelectedStrategy(
                for: session.position,
                strategy: .balanced,
                depth: analysisDepth
            )
        }
    }

    @State private var replacingNode: OpeningTreeNode?
    @State private var replacingTreeID: UUID?
    public var body: some View {
        interactionContent
        .disclosureGroupStyle(WholeRowDisclosureStyle())
        .onChange(of: review.isRunning) { _, _ in updateBackgroundPriority() }
        .onChange(of: isAIThinking) { _, _ in updateBackgroundPriority() }
        .onChange(of: analysis.snapshot.state) { _, _ in updateBackgroundPriority() }
        .onChange(of: trees.trees.count) { _, _ in if appMode == .treeBuilder { matchCurrentTree() } }
        .onChange(of: selectedTreeID) { _, _ in
            treeReview.cancel()
            updateReview(for: session.record)
        }
        .onChange(of: treeReview.revision) { _, _ in updateReview(for: session.record) }
        .onChange(of: treeReview.isRunning) { _, _ in
            updateBackgroundPriority()
            updateReview(for: session.record)
        }
        .onChange(of: repertoireSide) { _, side in
            session.isBoardFlipped = side == .black
            if appMode == .treeBuilder { replacingNode = nil; matchCurrentTree(); updateReview(for: session.record) }
            else if appMode == .analysis {
                selectedTreeID = trees.trees.first { $0.repertoireSide == side }?.id
            }
        }
        .task {
            if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--opening-tree-seed"), ProcessInfo.processInfo.arguments.indices.contains(index + 1) {
                sync.importSeed(URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1]))
            }
            if appMode == .treeBuilder { matchCurrentTree(); session.isBoardFlipped = repertoireSide == .black }
            updateBackgroundPriority()
            if backgroundEnabled { sync.resumeIfNeeded() }
            updateReview(for: session.record)
            updateAnalysis(for: session.position)
        }
        .task(id: aiTaskIdentity) {
            await makeAIMoveIfNeeded()
        }
    }

    private var threeColumnLayout: some View {
        HStack(alignment: .top, spacing: 18) {
            modeDock
                .frame(width: 245)
                .frame(maxHeight: .infinity)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    controls
                    board
                    if appMode == .treeBuilder { treeCanvas.frame(height: 340) }
                }
            }
            .frame(width: max(280, windowWidth - 18 * 4 - 245 - 320))

            ScrollView {
                feedbackPanel
                    .padding(.bottom, 16)
            }
            .frame(width: 320)
        }
        .padding(18)
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 14) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    controls
                    board
                    compactSideDock
                    if appMode == .analysis { treeCanvas.frame(height: 320) }
                }.padding(.bottom, 16)
            }
            .frame(minWidth: 0, maxWidth: .infinity)
            ScrollView { feedbackPanel.padding(.bottom, 16) }
                .frame(width: min(340, max(280, windowWidth * 0.31)))
        }.padding(16)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if appMode == .treeBuilder {
                    compactSideDock
                    treeCanvas.frame(height: 420)
                }
                controls
                board
                feedbackPanel
                if appMode == .analysis { treeCanvas.frame(height: 300) }
                if appMode != .treeBuilder { compactSideDock }
            }.padding(14)
        }
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChessBoardView(
                session: session,
                analysis: analysis.snapshot,
                openingHintMove: nil,
                selectedStrategy: .balanced,
                showsSingleStrategyOnly: true,
                isInteractionEnabled: isBoardInteractionEnabled,
                reviewedMove: showsMoveClassification ? review.moves.first(where: { $0.index == session.cursor }) : nil
            )
            .frame(maxWidth: max(280, min(680, windowHeight - (appMode == .analysis ? 325 : 285))))
            .frame(maxWidth: .infinity)
            GameHistoryStrip(session: session, review: review, enabled: appMode != .versusAI,
                             allowsDrawClaim: appMode != .versusAI || session.position.sideToMove == humanColor,
                             allowsFullReview: appMode != .treeBuilder)
            if let error = library.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private var modeDock: some View {
        VStack(spacing: 12) {
            ScrollView { activeSideDock }
        }
    }

    @ViewBuilder
    private var activeSideDock: some View {
        if appMode != .versusAI {
            VStack(spacing: 12) {
                treePanel
                if appMode == .analysis && windowWidth >= 720 { treeCanvas.frame(height: max(300, min(420, windowHeight - 370))) }
            }
        } else {
            VStack(spacing: 14) {
            AIPlayDockView(
                position: session.position,
                humanColor: $humanColor,
                difficulty: $aiDifficulty,
                strategy: $aiStrategy,
                isAIThinking: isAIThinking,
                errorMessage: aiErrorMessage,
                onNewGame: beginNewGame
            )
            DisclosureGroup("个人开局树") { treePanel }
            }
        }
    }

    private var modePickerCard: some View {
        Picker("模式", selection: $appMode) {
            ForEach(ChessAppMode.allCases) { mode in
                Label(mode.title, systemImage: mode.systemImage).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(10)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var treePanel: some View {
        OpeningTreePanel(trees: trees, session: session, library: library, sync: sync,
            treeReview: treeReview, onCalculate: calculateTree, selectedTreeID: $selectedTreeID, repertoireSide: $repertoireSide, constructing: appMode == .treeBuilder, onSave: saveTreeRoute, onSaveAutomatically: saveCurrentOpening, onStart: { replacingNode = nil; beginNewGame() }, onEdit: editTreeNode, editingSAN: replacingNode?.san)
    }
    @ViewBuilder private var treeCanvas: some View {
        if let tree = trees.tree(selectedTreeID) {
            OpeningTreeCanvas(tree: tree, selectedMoves: session.moveHistory, selectedFEN: session.record.initialFEN,
                full: appMode == .treeBuilder || session.cursor == 0, onSelect: { if appMode != .versusAI { selectTreeNode($0) } },
                onZoom: { value in trees.update(tree.id) { $0.savedZoom = value } }, allNodes: trees.nodes(for: tree.id), fullLayout: (appMode == .treeBuilder || session.cursor == 0) ? trees.layout(for: tree.id) : nil).id(tree.id)
        } else {
            VStack(spacing: 12) { Image(systemName: "tree.fill").font(.largeTitle); Text(appMode == .treeBuilder ? "先在棋盘试走，再保存你的开局树。" : "选择一棵开局树，查看自己的路线。").font(.callout) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
    private var constructionLayout: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 16) {
                ScrollView { treePanel }.frame(width: 260)
                treeCanvas.frame(width: max(280, windowWidth - 36 - 32 - 260 - 390)).frame(maxHeight: .infinity)
                ScrollView { VStack(spacing: 14) { controls; board; feedbackPanel } }.frame(width: 390)
            }
        }.padding(18)
    }
    private var verticalConstructionLayout: some View {
        VStack(spacing: 14) {
            header
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 14) {
                        treeCanvas.frame(height: max(300, windowHeight * 0.48))
                        treePanel
                    }
                }.frame(minWidth: 0, maxWidth: .infinity)
                ScrollView {
                    VStack(spacing: 14) { controls; board; feedbackPanel }
                }.frame(width: min(390, windowWidth * 0.46))
            }
        }.padding(16)
    }
    private var feedbackPanel: some View {
        VStack(spacing: 14) {
            if appMode != .versusAI || session.position.sideToMove == humanColor {
                OpeningEnginePanel(position: session.position, analysis: analysis.snapshot,
                    onRequest: { analysis.refreshSelectedStrategy(for: session.position, strategy: .balanced, depth: analysisDepth) },
                    onPlay: { move in _ = session.make(move) })
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AI 思考中", systemImage: "cpu").font(.headline)
                    Text("正在选择下一步走法…").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
                    .padding(14).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 14))
            }
            if appMode == .analysis {
                FreeAnalysisOverview(session: session, analysis: analysis, review: review)
            } else {
                MoveFeedbackPanel(session: session, review: review, allowsNavigation: appMode != .versusAI, allowsFullReview: appMode != .treeBuilder)
            }
        }
    }

    private var compactSideDock: some View {
        DisclosureGroup(isExpanded: $isCompactSideDockExpanded) {
            activeSideDock
                .padding(.top, 10)
        } label: {
            Label(
                appMode == .versusAI ? "对弈设置与开局树" : "个人开局树",
                systemImage: appMode == .versusAI ? "cpu.fill" : "tree.fill"
            )
                .font(.headline)
        }
        .padding(13)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var header: some View {
        VStack(spacing: 10) {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("神之一手")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text(appMode == .analysis ? "三个候选着 · 棋谱按需复盘" : "走棋后自动评价 · 棋局自动保存")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if appMode != .treeBuilder {
                Button { showsGameLibrary = true } label: {
                    Label("棋局库", systemImage: "tray.full")
                }.buttonStyle(.bordered).controlSize(.small)
            }

            HStack(spacing: 7) {
                if isAIThinking {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(session.position.sideToMove == .white ? Color.white : Color.black)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.secondary, lineWidth: 0.7))
                }
                Text(isAIThinking ? "AI 思考中" : "\(session.position.sideToMove.displayName)回合")
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(AppTheme.panelBackground)
            .clipShape(Capsule())
        }
        modePickerCard
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if appMode == .analysis {
                    Button { showsPositionSetup = true } label: { Label("摆棋", systemImage: "square.grid.3x3") }.buttonStyle(.bordered).controlSize(.small)
                }
                undoButton; flipButton; resetButton
                Spacer(minLength: 0)
            }
            HStack(spacing: 12) {
                if appMode != .treeBuilder { heatmapToggle }
                bestLineToggle
                Spacer(minLength: 0)
            }.font(.caption)
        }
        .padding(12)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var heatmapToggle: some View {
        Toggle(isOn: $session.showsControlHeatmap) {
            Label("控制热力图", systemImage: "flame.fill")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var undoButton: some View {
        Button {
            undoCurrentTurn()
        } label: {
            Label("悔棋", systemImage: "arrow.uturn.backward")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!session.canUndo)
        .keyboardShortcut("z", modifiers: .command)
    }

    private var flipButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                session.isBoardFlipped.toggle()
            }
        } label: {
            Label("黑白反转", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var bestLineToggle: some View {
        Toggle(isOn: $session.showsBestLineOnBoard) {
            Label(
                "候选着标注",
                systemImage: "arrow.triangle.branch"
            )
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var resetButton: some View {
        Button {
            beginNewGame()
        } label: {
            Label(appMode == .treeBuilder ? "从头构建" : (appMode == .analysis ? "重新开始" : "新对局"), systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var isBoardInteractionEnabled: Bool {
        if appMode != .versusAI { return !showsGameLibrary }
        return !isAIThinking && !showsGameLibrary
            && session.position.sideToMove == humanColor
            && !isGameOver
    }

    private var isGameOver: Bool { session.outcome != nil }

    private var aiTaskIdentity: String {
        "\(appMode.rawValue)|\(humanColor.rawValue)|\(aiDifficulty.rawValue)|\(aiStrategy.rawValue)|\(aiGameGeneration)|\(showsGameLibrary)|\(session.position.fen)"
    }

    private func beginNewGame() {
        if !session.record.moves.isEmpty { _ = library.save(session.record) }
        review.restore(nil)
        aiGameGeneration += 1
        isAIThinking = false
        aiErrorMessage = nil
        selectedStrategy = aiStrategy
        session.showsBestLineOnBoard = false
        session.reset()
        if let selectedTreeID { trees.bind(selectedTreeID, to: session.record) }
        analysis.reset(for: session.position)
        if appMode == .versusAI { session.isBoardFlipped = humanColor == .black }
        else if appMode == .treeBuilder { matchCurrentTree(); session.isBoardFlipped = repertoireSide == .black }
        if appMode != .treeBuilder && (appMode != .versusAI || session.position.sideToMove == humanColor) {
            analysis.refreshSelectedStrategy(
                for: session.position,
                strategy: .balanced,
                depth: analysisDepth
            )
        }
    }

    private func undoCurrentTurn() {
        aiGameGeneration += 1
        aiErrorMessage = nil
        session.undo()

        if appMode == .versusAI,
           session.canUndo,
           session.position.sideToMove != humanColor {
            session.undo()
        }
    }

    private func makeAIMoveIfNeeded() async {
        guard appMode == .versusAI,
              !showsGameLibrary,
              !isGameOver,
              session.position.sideToMove != humanColor
        else {
            isAIThinking = false
            return
        }

        let requestedPosition = session.position
        let requestedFEN = requestedPosition.fen
        let requestedGeneration = aiGameGeneration
        isAIThinking = true
        aiErrorMessage = nil

        do {
            let move = try await analysis.bestMove(
                for: requestedPosition,
                depth: aiDifficulty.depth,
                strategy: aiStrategy
            )
            guard !Task.isCancelled,
                  appMode == .versusAI,
                  !showsGameLibrary,
                  requestedGeneration == aiGameGeneration,
                  session.position.fen == requestedFEN
            else { return }

            if let move {
                _ = session.make(move)
            }
            isAIThinking = false
        } catch {
            guard !Task.isCancelled,
                  requestedGeneration == aiGameGeneration,
                  session.position.fen == requestedFEN
            else { return }
            isAIThinking = false
            aiErrorMessage = error.localizedDescription
        }
    }

    private func updateAnalysis(for position: GamePosition) {
        guard !treeReview.isRunning else { return }
        guard appMode != .treeBuilder else {
            analysis.reset(for: position)
            _ = analysis.restoreCachedStrategy(for: position, strategy: .balanced, depth: analysisDepth)
            return
        }
        if appMode != .versusAI {
            analysis.refreshSelectedStrategy(
                for: position,
                strategy: .balanced,
                depth: analysisDepth
            )
            return
        }

        guard position.sideToMove == humanColor else { analysis.reset(for: position); return }
        analysis.refreshSelectedStrategy(
            for: position,
            strategy: .balanced,
            depth: analysisDepth
        )
    }

    private func loadGame(_ record: GameRecord) {
        do {
            if !session.record.moves.isEmpty { _ = library.save(session.record) }
            review.cancel()
            aiGameGeneration += 1; isAIThinking = false; appMode = .analysis
            try session.load(record)
            analysis.reset(for: session.position)
            review.restore(library.review(for: record))
            updateReview(for: record)
            selectedTreeID = trees.boundTree(for: record) ?? selectedTreeID
            _ = library.save(record)
            UserDefaults.standard.set(record.id.uuidString, forKey: "qipan.lastGame")
            updateAnalysis(for: session.position)
        } catch { workspaceError = error.localizedDescription }
    }
    private func updateReview(for record: GameRecord) {
        let cached = trees.cachedReview(for: record, engine: analysis.snapshot.engineName, minimumDepth: 0)
        if let report = review.report, !ReviewEngineIdentity.matches(report.engine, analysis.snapshot.engineName) {
            review.restore(nil)
        }
        // Cached steps are filtered by the coordinator. Every missing current step
        // is graded, including free analysis and already saved opening-tree nodes.
        review.updateLive(record: record, cursor: session.cursor, cached: cached, allowAnalysis: !treeReview.isRunning)
    }
    private func matchAnalysisTree() {
        guard !session.moveHistory.isEmpty else {
            if trees.tree(selectedTreeID) == nil { selectedTreeID = trees.trees.first { $0.repertoireSide == repertoireSide }?.id }
            return
        }
        let candidates = trees.trees.filter { $0.repertoireSide == repertoireSide || $0.repertoireSide == nil }
        let prefix = session.moveHistory
        let initialFEN = session.record.initialFEN
        selectedTreeID = candidates.max { a, b in
            func length(_ doc: OpeningTreeDocument) -> Int {
                doc.sources.filter { $0.initialFEN == initialFEN }.map { source in
                    zip(source.moves, prefix).prefix { $0 == $1 }.count
                }.max() ?? 0
            }
            return length(a) < length(b)
        }.flatMap { doc in doc.sources.contains { $0.initialFEN == session.record.initialFEN && $0.moves.first == prefix.first } ? doc.id : nil }
        trees.bind(selectedTreeID, to: session.record)
    }
    private func matchCurrentTree() {
        selectedTreeID = trees.matchingTree(fen: session.record.initialFEN, moves: session.moveHistory, side: repertoireSide)
        trees.bind(selectedTreeID, to: session.record)
    }
    private func saveCurrentOpening() {
        guard let id = trees.resolveTree(fen: session.record.initialFEN, moves: session.moveHistory, side: repertoireSide) else { return }
        saveTreeRoute(id)
    }
    private func saveTreeRoute(_ treeID: UUID) {
        guard session.cursor > 0 else { return }
        var record = session.record
        record.moves = session.moveHistory; record.cursor = record.moves.count; record.branches = []
        var report: GameReviewReport?
        if let current = review.report {
            let moves = review.moves.filter { $0.index > 0 && $0.index <= record.moves.count && $0.move == record.moves[$0.index - 1] }
            report = GameReviewReport(version: current.version, analysisKey: record.analysisKey,
                depth: moves.map(\.depth).min() ?? 14, engine: current.engine, completedAt: current.completedAt, moves: moves)
        }
        if let old = replacingNode, replacingTreeID == treeID,
           record.initialFEN == old.initialFEN, record.moves.count >= old.moves.count,
           Array(record.moves.prefix(old.moves.count - 1)) == Array(old.moves.dropLast()),
           record.moves[old.moves.count - 1] != old.move {
            trees.deleteBranch(treeID, node: old, includeNode: true)
        }
        replacingNode = nil; replacingTreeID = nil
        selectedTreeID = treeID
        let group = OpeningTreeDocument.firstMoveGroup(fen: record.initialFEN, moves: record.moves, side: repertoireSide)
        trees.update(treeID) { if $0.groupingKey == nil { $0.groupingKey = group.key }; if $0.organizedByAdvantage != true { $0.repertoireSide = repertoireSide } }
        trees.bind(treeID, to: session.record)
        trees.synchronize(record: record, kind: .research, report: report, treeID: treeID, restoreDeleted: true)
    }
    private var sourceKind: TreeSourceKind { appMode == .versusAI ? .game : .research }
    private func calculateTree(_ recomputeAll: Bool) {
        guard let id = selectedTreeID else { return }
        review.cancel()
        analysis.suspend(for: session.position, preservingTimeline: true)
        treeReview.start(treeID: id, store: trees, recomputeAll: recomputeAll)
    }
    private func updateBackgroundPriority() {
        sync.foregroundBusy = treeReview.isRunning || appMode == .treeBuilder || isAIThinking || review.isRunning || analysis.snapshot.state == .analyzing
    }
    private func editTreeNode(_ node: OpeningTreeNode) {
        guard let id = selectedTreeID, let parent = node.parentID,
              let before = trees.nodes(for: id, includeHidden: true).first(where: { $0.id == parent }) else { return }
        selectTreeNode(before); replacingNode = node; replacingTreeID = id
    }
    private func selectTreeNode(_ node: OpeningTreeNode) {
        guard appMode != .versusAI else { return }
        replacingNode = nil; replacingTreeID = nil
        do {
            var record = GameRecord(position: try GamePosition(fen: node.initialFEN))
            record.id = researchRecordID; record.moves = node.moves; record.cursor = node.moves.count
            record.tags["Event"] = "个人开局树研究"
            if session.record.id == researchRecordID {
                record.branches = session.record.branches
                if session.record.moves != node.moves && !session.record.moves.isEmpty && !record.branches.contains(where: { $0.moves == session.record.moves }) {
                    record.branches.append(GameBranch(name: "研究路线", moves: session.record.moves, comments: session.record.comments))
                }
            }
            review.cancel(); aiGameGeneration += 1
            try session.load(record)
            if appMode == .treeBuilder { matchCurrentTree(); session.isBoardFlipped = repertoireSide == .black }
            trees.bind(selectedTreeID, to: record)
            analysis.reset(for: session.position); review.restore(library.review(for: record))
            updateReview(for: record); updateAnalysis(for: session.position)
        } catch { workspaceError = error.localizedDescription }
    }
    private func promotionName(_ kind: PieceKind?) -> String {
        switch kind { case .queen: "后"; case .rook: "车"; case .bishop: "象"; case .knight: "马"; default: "后" }
    }

    private var analysisDepth: Int {
        14
    }
}
