import Analysis
import GameCore
import SwiftUI

struct OpeningEnginePanel: View {
    let position: GamePosition
    let analysis: PositionAnalysis
    let onRequest: () -> Void
    let onPlay: (Move) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(position.sideToMove.displayName + " · 三个候选着", systemImage: "list.number").font(.headline)
            switch analysis.state {
            case .ready:
                ForEach(analysis.candidates) { candidate in
                    Button { onPlay(candidate.move) } label: {
                        HStack(spacing: 10) {
                            Text("\(candidate.rank)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            Text(candidate.san).font(.callout.bold()).frame(minWidth: 45, alignment: .leading)
                            MoveClassificationLabel(classification: candidate.quality)
                            Spacer(minLength: 4)
                            Text(candidate.score).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.padding(10).frame(maxWidth: .infinity).background(candidate.quality.badgeColor.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                    }.buttonStyle(.plain).help("在棋盘走出 " + candidate.san)
                }
                if analysis.candidates.isEmpty { Text("当前没有候选走法").font(.caption) }
                else {
                    Text("点击走出这一步 · 评价从当前行棋方看").font(.caption2).foregroundStyle(.secondary)
                    if analysis.candidates.count < 3 { Text("当前完成分析的候选不足三个").font(.caption2).foregroundStyle(.secondary) }
                }
            case .analyzing:
                HStack { ProgressView().controlSize(.small); Text("正在比较候选走法…").font(.caption) }
            case .failed(let message), .unavailable(let message):
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("重试", action: onRequest)
            case .idle:
                Button("获取三个候选着", action: onRequest).buttonStyle(.bordered)
            }
        }.frame(minHeight: 190, alignment: .topLeading).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
