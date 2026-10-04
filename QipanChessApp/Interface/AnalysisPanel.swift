import Analysis
import GameCore
import SwiftUI

struct AnalysisPanel: View {
    let analysis: PositionAnalysis
    let timeline: [AdvantagePoint]
    @Binding var selectedStrategy: StrategyType?
    @Binding var calculationStrategy: StrategyType
    let showsSingleStrategyOnly: Bool
    @State private var displayedAnalysis: PositionAnalysis

    init(
        analysis: PositionAnalysis,
        timeline: [AdvantagePoint],
        selectedStrategy: Binding<StrategyType?>,
        calculationStrategy: Binding<StrategyType>,
        showsSingleStrategyOnly: Bool = false
    ) {
        self.analysis = analysis
        self.timeline = timeline
        _selectedStrategy = selectedStrategy
        _calculationStrategy = calculationStrategy
        self.showsSingleStrategyOnly = showsSingleStrategyOnly
        _displayedAnalysis = State(initialValue: analysis)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            evaluationCard
            timelineCard
            strategyPredictionCard
            engineCard
            legendCard
        }
        .onChange(of: analysis) { _, newAnalysis in
            guard shouldPresent(newAnalysis.state) else { return }
            if !newAnalysis.strategies.isEmpty,
               selectedStrategy == nil
                    || !newAnalysis.strategies.contains(where: { $0.type == selectedStrategy }) {
                selectedStrategy = newAnalysis.strategies.first(where: { $0.type == .balanced })?.type
                    ?? newAnalysis.strategies.first?.type
            }
            withAnimation(.easeInOut(duration: 0.28)) {
                displayedAnalysis = newAnalysis
            }
        }
    }

    private var timelineCard: some View {
        panel(title: "优势时间轴", systemImage: "chart.xyaxis.line") {
            AdvantageTimelineView(points: timeline)
        }
    }

    private var evaluationCard: some View {
        panel(title: "局势评价", systemImage: "gauge.with.dots.needle.33percent") {
            HStack(alignment: .firstTextBaseline) {
                Text(advantageTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                HStack(spacing: 5) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                    }
                    Text(evaluationStatusTitle)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 66, alignment: .trailing)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.86))
                    Capsule()
                        .fill(Color.white.opacity(0.94))
                        .frame(width: proxy.size.width * whiteShare)
                    Rectangle()
                        .fill(AppTheme.accent)
                        .frame(width: 2)
                        .offset(x: proxy.size.width / 2 - 1)
                }
            }
            .frame(height: 11)

            HStack {
                Text("白方")
                Spacer()
                Text("黑方")
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            Text("中性视角 · 直接显示当前占优方")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private var strategyPredictionCard: some View {
        panel(title: strategyPanelTitle, systemImage: "point.3.connected.trianglepath.dotted") {
            VStack(alignment: .leading, spacing: 7) {
                Text("选择计算棋风")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("选择计算棋风", selection: $calculationStrategy) {
                    ForEach(StrategyType.allCases) { style in
                        Text(style.shortName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            switch displayedAnalysis.state {
            case .analyzing, .idle:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(showsSingleStrategyOnly ? "正在计算当前棋风路线…" : "正在生成三种风险路线…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .unavailable, .failed:
                Text(showsSingleStrategyOnly
                     ? "引擎可用后显示当前棋风路线"
                     : "引擎可用后显示激进、稳健和保守路线")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .ready:
                if visibleStrategies.isEmpty {
                    Text("当前局面没有可走着法")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 9) {
                        ForEach(visibleStrategies) { strategy in
                            strategyButton(strategy)
                        }
                    }

                    Label(strategyPanelFooter, systemImage: "hand.tap")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var engineCard: some View {
        panel(title: "引擎状态", systemImage: "cpu") {
            HStack(spacing: 8) {
                Circle()
                    .fill(engineStateColor)
                    .frame(width: 9, height: 9)
                Text(analysis.engineName)
                    .font(.callout.weight(.semibold))
                Spacer()
                Text(engineStateTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(engineStateDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var legendCard: some View {
        panel(title: "控制范围图例", systemImage: "square.grid.3x3.fill") {
            HStack(spacing: 14) {
                legend(color: AppTheme.whiteControl, text: "白方")
                legend(color: AppTheme.blackControl, text: "黑方")
                legend(color: AppTheme.overlapControl, text: "重叠")
            }
            Text("颜色越深，控制该格的棋子越多。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func strategyButton(_ strategy: ChessStrategy) -> some View {
        let color = strategyColor(strategy.type)
        let isSelected = selectedStrategy == strategy.type

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedStrategy = strategy.type
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: strategySystemImage(strategy.type))
                        .foregroundStyle(color)
                    Text(strategy.type.displayName)
                        .font(.callout.weight(.bold))
                    Spacer()
                    Text("风险 \(strategy.riskLevel.displayName)")
                        .font(.caption2.bold())
                        .foregroundStyle(strategy.type == .conservative ? Color.black.opacity(0.72) : .white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color)
                        .clipShape(Capsule())
                }

                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("第一步推荐")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(strategy.firstMove.notation)
                            .font(.body.monospaced().weight(.semibold))
                    }
                    Spacer()
                    Image(systemName: "arrow.right")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("对手最佳回应")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(strategy.secondMove?.notation ?? "无合法回应")
                            .font(.callout.monospaced())
                    }
                }

                HStack(spacing: 8) {
                    Text(evaluationTitle(strategy.evaluation))
                    Spacer()
                    Text(evaluationDeltaTitle(strategy))
                    if let winProbability = strategy.winProbability {
                        Text("胜率 \(winProbability.formatted(.percent.precision(.fractionLength(0))))")
                    }
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

                Text(strategy.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(isSelected ? 0.14 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(color.opacity(isSelected ? 0.95 : 0.22), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            "\(strategy.type.displayName)，第一步 \(strategy.firstMove.notation)，风险\(strategy.riskLevel.displayName)"
        )
        .accessibilityHint("轻点后在棋盘显示该路线")
    }

    private func strategyColor(_ type: StrategyType) -> Color {
        switch type {
        case .aggressive: AppTheme.aggressiveStrategy
        case .balanced: AppTheme.balancedStrategy
        case .conservative: AppTheme.conservativeStrategy
        }
    }

    private func strategySystemImage(_ type: StrategyType) -> String {
        switch type {
        case .aggressive: "flame.fill"
        case .balanced: "scale.3d"
        case .conservative: "shield.fill"
        }
    }

    private func evaluationTitle(_ advantage: PositionAdvantage) -> String {
        switch advantage {
        case .balanced:
            "评价 均衡"
        case .side(let color, let magnitude):
            "评价 \(color.displayName) +\(String(format: "%.2f", magnitude))"
        case .mate(let color, let moves):
            "\(color.displayName) \(moves) 步将杀"
        }
    }

    private func evaluationDeltaTitle(_ strategy: ChessStrategy) -> String {
        guard strategy.type != .balanced else { return "AI 基准" }
        return "较最佳 \(String(format: "%+.2f", strategy.evaluationDelta))"
    }

    private func panel<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.72))
                .frame(width: 14, height: 14)
            Text(text).font(.caption)
        }
    }

    private var advantageTitle: String {
        switch displayedAnalysis.evaluation.advantage {
        case .balanced:
            "局势均衡"
        case .side(let color, let magnitude):
            "\(color.displayName)优势 \(String(format: "%.2f", magnitude))"
        case .mate(let color, let moves):
            "\(color.displayName) \(moves) 步将杀"
        }
    }

    private var whiteShare: Double {
        switch displayedAnalysis.evaluation.advantage {
        case .balanced:
            return 0.5
        case .side(let color, let magnitude):
            let shift = min(magnitude, 5) / 12
            return color == .white ? 0.5 + shift : 0.5 - shift
        case .mate(let color, _):
            return color == .white ? 0.94 : 0.06
        }
    }

    private var evaluationStatusTitle: String {
        if isRefreshing { return "更新中" }
        return displayedAnalysis.evaluation.depth.map { "深度 \($0)" } ?? "深度 —"
    }

    private var isRefreshing: Bool {
        guard case .analyzing = analysis.state,
              case .ready = displayedAnalysis.state
        else { return false }
        return true
    }

    private func shouldPresent(_ state: AnalysisState) -> Bool {
        switch state {
        case .ready, .unavailable, .failed:
            true
        case .idle, .analyzing:
            false
        }
    }

    private var engineStateColor: Color {
        switch analysis.state {
        case .ready: .green
        case .analyzing: .orange
        case .idle: .secondary
        case .unavailable: .gray
        case .failed: .red
        }
    }

    private var engineStateTitle: String {
        switch analysis.state {
        case .ready: "分析完成"
        case .analyzing: "分析中"
        case .idle: "等待局面"
        case .unavailable: "未接入"
        case .failed: "分析失败"
        }
    }

    private var engineStateDetail: String {
        switch analysis.state {
        case .ready:
            let time = analysis.elapsedMilliseconds.map { "\($0)ms" } ?? "—"
            let depth = analysis.evaluation.depth.map(String.init) ?? "—"
            let nodes = analysis.nodes.map { $0.formatted(.number.notation(.compactName)) } ?? "—"
            let analysisMode: String
            if let strategy = analysis.strategies.first {
                analysisMode = "单棋风 · \(strategy.type.displayName)"
            } else {
                analysisMode = "单路线"
            }
            return "\(analysisMode) · 深度 \(depth) · 用时 \(time) · 节点 \(nodes)"
        case .analyzing:
            return "正在更新当前局面的引擎建议。"
        case .idle:
            return "移动棋子后开始分析。"
        case .unavailable(let message), .failed(let message):
            return message
        }
    }

    private var strategyPanelTitle: String {
        visibleStrategies.count == 1 ? "AI 当前棋风" : "AI 策略预测"
    }

    private var strategyPanelFooter: String {
        if let strategy = visibleStrategies.first,
           visibleStrategies.count == 1 {
            return "当前只计算\(strategy.type.displayName)；切换棋风后只重算新路线"
        }
        return "点击路线可在棋盘查看对应着法和最佳回应"
    }

    private var visibleStrategies: [ChessStrategy] {
        guard showsSingleStrategyOnly, let selectedStrategy else {
            return displayedAnalysis.strategies
        }
        return displayedAnalysis.strategies.filter { $0.type == selectedStrategy }
    }
}
