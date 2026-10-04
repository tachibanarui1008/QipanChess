import Analysis
import GameCore
import SwiftUI

struct GameHistoryStrip: View {
    @ObservedObject var session: GameSession
    @ObservedObject var review: GameReviewCoordinator
    var enabled = true
    var allowsDrawClaim = true
    var allowsFullReview = false
    var body: some View {
        let positions = session.allPositions
        let ratings = Dictionary(uniqueKeysWithValues: review.moves.map { ($0.index, $0) })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("棋谱 · \(session.cursor)/\(session.record.moves.count)").font(.caption)
                Spacer()
                HStack(spacing: 10) {
                    navigation("backward.end.fill", "首步", disabled: !session.canUndo) { session.seek(to: 0) }
                    navigation("chevron.left", "上一步", disabled: !session.canUndo) { session.undo() }
                    navigation("chevron.right", "下一步", disabled: !session.canRedo) { session.redo() }
                    navigation("forward.end.fill", "末步", disabled: !session.canRedo) { session.seek(to: session.record.moves.count) }
                }
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(session.record.moves.enumerated()), id: \.offset) { index, move in
                            Button { session.seek(to: index + 1) } label: {
                                HStack(spacing: 4) {
                                    Text(label(for: move, position: positions[index])).font(.caption.monospaced())
                                    if let item = ratings[index + 1] {
                                        MoveQualityBadge(classification: item.classification, size: 18)
                                    } else if review.gradingIndex == index + 1 {
                                        ProgressView().controlSize(.mini)
                                    }
                                }.padding(6).background(session.cursor == index + 1 ? AppTheme.accent.opacity(0.15) : AppTheme.panelBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain).disabled(!enabled).id(index + 1)
                        }
                    }
                }.onChange(of: session.cursor) { _, cursor in proxy.scrollTo(cursor, anchor: .center) }
            }
            if allowsFullReview {
                Divider()
                FullGameReviewSection(session: session, review: review, allowsNavigation: enabled)
            }
            if let outcome = session.outcome { Text(outcome).font(.callout.bold()) }
            if allowsDrawClaim && session.canClaimDraw { Button("申请和棋") { session.claimDraw() }.buttonStyle(.bordered) }
        }.padding(12).background(AppTheme.panelBackground).clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private func navigation(_ icon: String, _ title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon) }.buttonStyle(.plain).disabled(!enabled || disabled).help(title).accessibilityLabel(title)
    }
    private func label(for move: Move, position: GamePosition) -> String {
        "\(position.plyCount / 2 + 1)\(position.sideToMove == .white ? "." : "…") " + SAN.string(for: move, in: position)
    }
}
