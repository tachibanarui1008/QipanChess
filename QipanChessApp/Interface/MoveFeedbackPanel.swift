import Analysis
import GameCore
import SwiftUI

struct MoveFeedbackPanel: View {
    @ObservedObject var session: GameSession
    @ObservedObject var review: GameReviewCoordinator
    let allowsNavigation: Bool
    var allowsFullReview = true
    @AppStorage("qipan.showMoveClassification") private var showsClassification = true
    private var item: ReviewedMove? { review.moves.first { $0.index == session.cursor } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LastMoveFeedback(session: session, review: review)
            if let message = review.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            if review.isRunning, let index = review.gradingIndex, index != session.cursor {
                Text("正在评价第 \(index) 手…").font(.caption).foregroundStyle(.secondary)
            }
            if !review.moves.isEmpty {
                Divider()
                Text("局势走势").font(.headline)
                ReviewChart(moves: review.moves, selected: session.cursor, perspective: session.isBoardFlipped ? .black : .white) { if allowsNavigation { session.seek(to: $0) } }.frame(height: 120)
            }
            DisclosureGroup("标记说明") {
                Toggle("显示棋盘标记", isOn: $showsClassification)
                MoveClassificationLegend()
                Text("根据 Stockfish 胜／和／负计算预期得分，采用公开分档；不含 Chess.com 未公开的玩家等级模型。妙着与关键好棋为本地规则识别。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Always identify the current move, even while its grade is being computed.
struct LastMoveFeedback: View {
    @ObservedObject var session: GameSession
    @ObservedObject var review: GameReviewCoordinator
    private var current: ReviewedMove? { review.moves.first { $0.index == session.cursor } }
    private var moveTitle: String {
        guard session.cursor > 0, session.cursor <= session.record.moves.count else { return "等待落子" }
        let before = session.allPositions[session.cursor - 1]
        let san = SAN.string(for: session.record.moves[session.cursor - 1], in: before)
        return "第 \(session.cursor) 手 · \(before.sideToMove.displayName) · \(san)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("上一步评价").font(.headline)
            if session.cursor == 0 {
                Text("走出第一步后，这里显示落子评价。").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 10) {
                    if let item = current {
                        MoveQualityBadge(classification: item.classification, size: 32)
                    } else {
                        Image(systemName: review.isRunning ? "clock" : "ellipsis.circle")
                            .font(.title2).foregroundStyle(.secondary).frame(width: 32, height: 32)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(current?.classification.title ?? (review.isRunning ? "正在评价…" : "等待评价"))
                            .font(.headline).contentTransition(.opacity)
                        Text(moveTitle).font(.callout).foregroundStyle(.secondary).contentTransition(.opacity)
                    }
                }
                Text(current?.explanation ?? (review.isRunning ? "正在计算这一步与最佳着的差距。" : "这一步尚未得到评分。"))
                    .font(.callout).contentTransition(.opacity)
                Text(current.map { "落子方评价 \($0.before.text) → \($0.after.text)" } ?? " ")
                    .font(.caption.monospaced()).foregroundStyle(.secondary).contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.25), value: current)
    }
}

/// Combines position searches with cached and live move reviews.
struct FreeAnalysisOverview: View {
    @ObservedObject var session: GameSession
    @ObservedObject var analysis: AnalysisCoordinator
    @ObservedObject var review: GameReviewCoordinator
    @AppStorage("qipan.showMoveClassification") private var showsClassification = true

    private var points: [AdvantagePoint] {
        let initialPly = session.allPositions.first?.plyCount ?? 0
        var points = Dictionary(uniqueKeysWithValues: analysis.timeline.map { ($0.ply, $0) })
        for item in review.moves {
            let score = item.whiteEvaluation
            let advantage: PositionAdvantage = abs(score) < 0.15 ? .balanced : .side(score >= 0 ? .white : .black, magnitude: abs(score))
            let ply = initialPly + item.index
            points[ply] = AdvantagePoint(ply: ply, advantage: advantage, classification: item.classification)
        }
        return points.values.sorted { $0.ply < $1.ply }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LastMoveFeedback(session: session, review: review)
            Divider()
            Text("局势走势 · \(session.isBoardFlipped ? "黑方" : "白方")视角").font(.headline)
            AdvantageTimelineView(points: points, perspective: session.isBoardFlipped ? .black : .white, selectedPly: session.position.plyCount)
            DisclosureGroup("标记说明") {
                Toggle("显示棋盘标记", isOn: $showsClassification)
                MoveClassificationLegend()
                Text("已有评价直接读取，缺失评价会在走棋后自动计算。开局树补算与整盘分析可批量更新标注。").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FullGameReviewSection: View {
    @ObservedObject var session: GameSession
    @ObservedObject var review: GameReviewCoordinator
    var allowsNavigation = true
    @State private var preset: ReviewPreset = .deep
    var body: some View {
        DisclosureGroup("整盘深入分析") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("搜索强度", selection: $preset) {
                    ForEach(ReviewPreset.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if review.isRunning {
                    ProgressView(value: Double(review.moves.count), total: Double(max(1, review.total)))
                    Text("已分析 \(review.moves.count) / \(review.total) 步").font(.caption)
                    Button("停止分析") { review.cancel() }
                } else {
                    Button("按当前棋谱重新分析整盘") { review.start(record: session.record, preset: preset) }
                        .disabled(session.record.moves.isEmpty)
                }
                Text("分析当前完整主线，包括回放位置之后的走法；追加走法或修改分枝后，可以重新分析并更新棋盘标记与局势走势。").font(.caption).foregroundStyle(.secondary)
                if let message = review.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                ForEach(review.moves.filter { $0.classification.isKeyMove }) { move in
                    Button { if allowsNavigation { session.seek(to: move.index) } } label: {
                        HStack {
                            Text("第 \(move.index) 手 · \(move.san)")
                            Spacer()
                            MoveClassificationLabel(classification: move.classification, size: 20)
                        }
                    }.buttonStyle(.plain).disabled(!allowsNavigation)
                }
            }.padding(.top, 8)
        }
    }
}
