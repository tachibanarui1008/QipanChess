import Analysis
import GameCore
import SwiftUI

struct AnalysisPanel: View {
    let analysis: PositionAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            evaluationCard
            bestLineCard
            engineCard
            legendCard
        }
    }

    private var evaluationCard: some View {
        panel(title: "局势评价", systemImage: "gauge.with.dots.needle.33percent") {
            HStack(alignment: .firstTextBaseline) {
                Text(advantageTitle)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .monospacedDigit()
                Spacer()
                Text(analysis.evaluation.depth.map { "深度 \($0)" } ?? "深度 —")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
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

    private var bestLineCard: some View {
        panel(title: "最佳路线", systemImage: "list.number") {
            switch analysis.state {
            case .analyzing, .idle:
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text("正在计算双方最佳着法…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            case .unavailable, .failed:
                Text("引擎可用后显示双方最佳路线")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .ready:
                if analysis.bestLine.currentMove == nil {
                    Text("当前局面没有可走着法")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    moveRow(
                        color: analysis.bestLine.currentSide,
                        title: "\(analysis.bestLine.currentSide.displayName)最佳着法",
                        move: analysis.bestLine.currentMove,
                        emphasized: true
                    )
                    moveRow(
                        color: analysis.bestLine.currentSide.opposite,
                        title: "\(analysis.bestLine.currentSide.opposite.displayName)最佳应对",
                        move: analysis.bestLine.bestReply,
                        emphasized: false
                    )

                    if !analysis.bestLine.continuation.isEmpty {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("后续参考")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(analysis.bestLine.continuation.map(\.notation).joined(separator: "   "))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
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

    private func moveRow(
        color: PieceColor,
        title: String,
        move: Move?,
        emphasized: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(color == .white ? Color.white : Color.black)
                .frame(width: 18, height: 18)
                .overlay(Circle().stroke(.secondary.opacity(0.7), lineWidth: 0.7))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(move?.notation ?? "等待应对路线")
                    .font(.body.monospaced().weight(emphasized ? .semibold : .regular))
            }
            Spacer()
            if emphasized {
                Text("当前")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent)
                    .clipShape(Capsule())
            }
        }
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
        switch analysis.evaluation.advantage {
        case .balanced:
            "局势均衡"
        case .side(let color, let magnitude):
            "\(color.displayName)优势 \(String(format: "%.2f", magnitude))"
        case .mate(let color, let moves):
            "\(color.displayName) \(moves) 步将杀"
        }
    }

    private var whiteShare: Double {
        switch analysis.evaluation.advantage {
        case .balanced:
            return 0.5
        case .side(let color, let magnitude):
            let shift = min(magnitude, 5) / 12
            return color == .white ? 0.5 + shift : 0.5 - shift
        case .mate(let color, _):
            return color == .white ? 0.94 : 0.06
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
            return "深度 \(depth) · 用时 \(time) · 节点 \(nodes)"
        case .analyzing:
            return "正在计算当前局势和双方最佳路线。"
        case .idle:
            return "移动棋子后开始分析。"
        case .unavailable(let message), .failed(let message):
            return message
        }
    }
}
