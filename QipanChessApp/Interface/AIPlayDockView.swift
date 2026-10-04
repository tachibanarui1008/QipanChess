import Analysis
import GameCore
import SwiftUI

struct AIPlayDockView: View {
    let position: GamePosition
    @Binding var humanColor: PieceColor
    @Binding var difficulty: AIDifficulty
    @Binding var strategy: StrategyType
    let isAIThinking: Bool
    let errorMessage: String?
    let onNewGame: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("对弈设置", systemImage: "cpu.fill")
                .font(.system(.title3, design: .rounded, weight: .bold))

            VStack(alignment: .leading, spacing: 7) {
                Text("选择执棋方")
                    .font(.headline)
                Picker("选择执棋方", selection: $humanColor) {
                    ForEach(PieceColor.allCases, id: \.self) { color in
                        Text("执\(color.displayName)").tag(color)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("AI 难度")
                    .font(.headline)
                Picker("AI 难度", selection: $difficulty) {
                    ForEach(AIDifficulty.allCases) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                Text(difficulty.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusCard

            VStack(alignment: .leading, spacing: 8) {
                Label("自由选择走法", systemImage: "hand.tap.fill")
                    .font(.callout.weight(.semibold))
                Text("轮到你时，可以像自由分析一样点击任意合法棋子和落点。AI 回合棋盘会暂时锁定，Stockfish 落子后再交还给你。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Spacer(minLength: 0)

            Button(action: onNewGame) {
                Label("开始新对局", systemImage: "arrow.counterclockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppTheme.accent)

            Text("始终只计算当前棋风的一条路线；切换棋风后只重新计算新路线。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(AppTheme.panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.primary.opacity(0.07), lineWidth: 1)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 11) {
            statusIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.callout.weight(.bold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(errorMessage == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(statusColor.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isAIThinking {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: statusSystemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(statusColor)
        }
    }

    private var statusTitle: String {
        if let gameResultTitle { return gameResultTitle }
        if errorMessage != nil { return "AI 暂时无法落子" }
        if isAIThinking { return "AI 正在思考"
        }
        return position.sideToMove == humanColor ? "轮到你落子" : "等待 AI 落子"
    }

    private var statusDetail: String {
        if let errorMessage { return errorMessage }
        if let gameResultTitle { return gameResultTitle }
        if isAIThinking {
            return "Stockfish 正在计算 \(difficulty.title)难度的应手。"
        }
        return "你执\(humanColor.displayName)，AI 按引擎最佳选择应手。"
    }

    private var gameResultTitle: String? {
        if MoveGenerator.isCheckmate(for: position.sideToMove, in: position) {
            return "\(position.sideToMove.opposite.displayName)将杀获胜"
        }
        if MoveGenerator.isStalemate(for: position.sideToMove, in: position) {
            return "和棋：无子可动"
        }
        return nil
    }

    private var statusSystemImage: String {
        if gameResultTitle != nil { return "flag.checkered" }
        if errorMessage != nil { return "exclamationmark.triangle.fill" }
        return position.sideToMove == humanColor ? "person.fill" : "cpu"
    }

    private var statusColor: Color {
        if gameResultTitle != nil { return .green }
        if errorMessage != nil { return .red }
        return position.sideToMove == humanColor ? AppTheme.accent : .blue
    }

    private var strategyDetail: String {
        switch strategy {
        case .aggressive:
            "偏向主动进攻、王区压力和战术机会。"
        case .balanced:
            "优先采用引擎评价最高、最稳定的路线。"
        case .conservative:
            "偏向防守、换子和降低局面复杂度。"
        }
    }
}
