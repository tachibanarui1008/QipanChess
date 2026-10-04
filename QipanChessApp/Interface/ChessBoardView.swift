import Analysis
import GameCore
import SwiftUI

struct ChessBoardView: View {
    @ObservedObject var session: GameSession
    let analysis: PositionAnalysis
    let openingHintMove: Move?
    let selectedStrategy: StrategyType?
    let showsSingleStrategyOnly: Bool
    let isInteractionEnabled: Bool
    var reviewedMove: ReviewedMove? = nil

    var body: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height)
            let squareSize = length / 8

            ZStack {
                boardGrid(squareSize: squareSize)

                if session.showsBestLineOnBoard {
                    strategyOverlay(squareSize: squareSize)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let openingHintMove {
                    openingHintOverlay(move: openingHintMove, squareSize: squareSize)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
                if let reviewedMove, reviewedMove.move == session.lastMove {
                    reviewOverlay(reviewedMove, squareSize: squareSize)
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .frame(width: length, height: length)
            .clipShape(RoundedRectangle(cornerRadius: max(8, length * 0.018), style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: max(8, length * 0.018), style: .continuous)
                    .stroke(.black.opacity(0.2), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 16, y: 7)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("国际象棋棋盘")
    }

    private func reviewOverlay(_ reviewedMove: ReviewedMove, squareSize: CGFloat) -> some View {
        let classification = reviewedMove.classification
        let destination = center(of: reviewedMove.move.to, squareSize: squareSize)
        return ZStack {
            Rectangle()
                .fill(classification.badgeColor.opacity(0.25))
                .frame(width: squareSize, height: squareSize)
                .position(destination)
            MoveQualityBadge(classification: classification, size: max(18, squareSize * 0.43))
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .position(x: destination.x + squareSize * 0.25, y: destination.y - squareSize * 0.25)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("上一手，\(reviewedMove.san)，\(classification.title)")
    }

    private func boardGrid(squareSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(displayedRanks, id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(displayedFiles, id: \.self) { file in
                        if let square = Square(file: file, rank: rank) {
                            squareButton(square, squareSize: squareSize)
                        }
                    }
                }
            }
        }
    }

    private var displayedRanks: [Int] {
        session.isBoardFlipped ? Array(0..<8) : Array((0..<8).reversed())
    }

    private var displayedFiles: [Int] {
        session.isBoardFlipped ? Array((0..<8).reversed()) : Array(0..<8)
    }

    @ViewBuilder
    private func strategyOverlay(squareSize: CGFloat) -> some View {
        ZStack {
            ForEach(analysis.candidates) { candidate in
                let color = candidate.quality.badgeColor
                bestMoveArrow(from: center(of: candidate.move.from, squareSize: squareSize),
                    to: center(of: candidate.move.to, squareSize: squareSize), color: color,
                    squareSize: squareSize, opacity: candidate.rank == 1 ? 0.95 : 0.70,
                    widthScale: candidate.rank == 1 ? 1.1 : 0.8)
                routeBadge(label: String(candidate.rank), color: color, squareSize: squareSize, foregroundColor: .white)
                    .position(badgePosition(for: candidate.move.to, squareSize: squareSize))
            }

        }
        .accessibilityHidden(true)
    }

    private var visibleStrategies: [ChessStrategy] {
        guard showsSingleStrategyOnly, let selectedStrategy else {
            return analysis.strategies
        }
        return analysis.strategies.filter { $0.type == selectedStrategy }
    }

    private func openingHintOverlay(move: Move, squareSize: CGFloat) -> some View {
        let from = center(of: move.from, squareSize: squareSize)
        let to = center(of: move.to, squareSize: squareSize)

        return ZStack {
            bestMoveArrow(
                from: from,
                to: to,
                color: AppTheme.openingHint,
                squareSize: squareSize
            )
            .shadow(color: .black.opacity(0.36), radius: 1.5, y: 1)

            routeBadge(
                label: "谱",
                color: AppTheme.openingHint,
                squareSize: squareSize
            )
            .position(badgePosition(for: move.to, squareSize: squareSize))
        }
        .accessibilityHidden(true)
    }

    private func bestMoveArrow(
        from: CGPoint,
        to: CGPoint,
        color: Color,
        squareSize: CGFloat,
        opacity: Double = 1,
        dashed: Bool = false,
        widthScale: CGFloat = 1
    ) -> some View {
        let deltaX = to.x - from.x
        let deltaY = to.y - from.y
        let distance = max(hypot(deltaX, deltaY), 1)
        let unitX = deltaX / distance
        let unitY = deltaY / distance
        let perpendicularX = -unitY
        let perpendicularY = unitX
        let startInset = squareSize * 0.18
        let tipInset = squareSize * 0.12
        let headLength = min(squareSize * 0.30, distance * 0.32)
        let headHalfWidth = min(squareSize * 0.17, distance * 0.18)
        let start = CGPoint(
            x: from.x + unitX * startInset,
            y: from.y + unitY * startInset
        )
        let tip = CGPoint(
            x: to.x - unitX * tipInset,
            y: to.y - unitY * tipInset
        )
        let headBase = CGPoint(
            x: tip.x - unitX * headLength,
            y: tip.y - unitY * headLength
        )

        return ZStack {
            Path { path in
                path.move(to: start)
                path.addLine(to: headBase)
            }
            .stroke(
                color.opacity(opacity),
                style: StrokeStyle(
                    lineWidth: max(3, squareSize * 0.09 * widthScale),
                    lineCap: .round,
                    lineJoin: .round,
                    dash: dashed ? [squareSize * 0.12, squareSize * 0.09] : []
                )
            )

            Path { path in
                path.move(to: tip)
                path.addLine(to: CGPoint(
                    x: headBase.x + perpendicularX * headHalfWidth,
                    y: headBase.y + perpendicularY * headHalfWidth
                ))
                path.addLine(to: CGPoint(
                    x: headBase.x - perpendicularX * headHalfWidth,
                    y: headBase.y - perpendicularY * headHalfWidth
                ))
                path.closeSubpath()
            }
            .fill(color.opacity(opacity))
        }
    }

    private func routeBadge(
        label: String,
        color: Color,
        squareSize: CGFloat,
        foregroundColor: Color = Color.black.opacity(0.82)
    ) -> some View {
        Text(label)
            .font(.system(size: squareSize * 0.18, weight: .heavy, design: .rounded))
            .foregroundStyle(foregroundColor)
            .frame(width: squareSize * 0.32, height: squareSize * 0.32)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 1, y: 1)
    }

    private func strategyColor(_ type: StrategyType) -> Color {
        switch type {
        case .aggressive: AppTheme.aggressiveStrategy
        case .balanced: AppTheme.balancedStrategy
        case .conservative: AppTheme.conservativeStrategy
        }
    }

    private func center(of square: Square, squareSize: CGFloat) -> CGPoint {
        let displayFile = session.isBoardFlipped ? 7 - square.file : square.file
        let displayRank = session.isBoardFlipped ? square.rank : 7 - square.rank
        return CGPoint(
            x: (CGFloat(displayFile) + 0.5) * squareSize,
            y: (CGFloat(displayRank) + 0.5) * squareSize
        )
    }

    private func badgePosition(for square: Square, squareSize: CGFloat) -> CGPoint {
        let displayFile = session.isBoardFlipped ? 7 - square.file : square.file
        let displayRank = session.isBoardFlipped ? square.rank : 7 - square.rank
        return CGPoint(
            x: (CGFloat(displayFile) + 0.79) * squareSize,
            y: (CGFloat(displayRank) + 0.21) * squareSize
        )
    }

    private func squareButton(_ square: Square, squareSize: CGFloat) -> some View {
        Button {
            guard isInteractionEnabled else { return }
            session.select(square)
        } label: {
            ZStack {
                baseColor(for: square)

                if session.showsControlHeatmap {
                    controlColor(for: square)
                }

                if session.lastMove?.from == square || session.lastMove?.to == square {
                    Color.yellow.opacity(0.24)
                }

                if session.selectedSquare == square {
                    Color.yellow.opacity(0.38)
                }

                if session.legalTargets.contains(square) {
                    legalTargetMarker(at: square, squareSize: squareSize)
                }

                if let piece = session.position[square] {
                    Text(piece.symbol)
                        .font(.system(size: squareSize * 0.68, weight: .regular, design: .serif))
                        .foregroundStyle(piece.color == .white ? Color(white: 0.97) : Color(white: 0.10))
                        .shadow(
                            color: piece.color == .white ? .black.opacity(0.48) : .white.opacity(0.25),
                            radius: 0.7,
                            x: 0,
                            y: 0.7
                        )
                        .minimumScaleFactor(0.5)
                }

                coordinateLabels(for: square, squareSize: squareSize)
            }
            .frame(width: squareSize, height: squareSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel(for: square))
        .accessibilityHint(accessibilityHint(for: square))
    }

    private func baseColor(for square: Square) -> Color {
        (square.file + square.rank).isMultiple(of: 2) ? AppTheme.boardDark : AppTheme.boardLight
    }

    @ViewBuilder
    private func controlColor(for square: Square) -> some View {
        let whiteCount = analysis.controlMap.white[square, default: 0]
        let blackCount = analysis.controlMap.black[square, default: 0]
        let strength = min(0.72, 0.44 + Double(max(whiteCount, blackCount) - 1) * 0.10)

        if whiteCount > 0 && blackCount > 0 {
            AppTheme.overlapControl.opacity(strength)
        } else if whiteCount > 0 {
            AppTheme.whiteControl.opacity(strength)
        } else if blackCount > 0 {
            AppTheme.blackControl.opacity(strength)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func legalTargetMarker(at square: Square, squareSize: CGFloat) -> some View {
        if session.position[square] == nil {
            Circle()
                .fill(Color.black.opacity(0.34))
                .frame(width: squareSize * 0.25, height: squareSize * 0.25)
        } else {
            Circle()
                .stroke(Color.yellow.opacity(0.92), lineWidth: max(3, squareSize * 0.07))
                .padding(squareSize * 0.07)
        }
    }

    @ViewBuilder
    private func coordinateLabels(for square: Square, squareSize: CGFloat) -> some View {
        let labelColor = (square.file + square.rank).isMultiple(of: 2)
            ? AppTheme.boardLight.opacity(0.82)
            : AppTheme.boardDark.opacity(0.82)

        let bottomRank = session.isBoardFlipped ? 7 : 0
        let leadingFile = session.isBoardFlipped ? 7 : 0

        if square.rank == bottomRank {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(String("abcdefgh"["abcdefgh".index("abcdefgh".startIndex, offsetBy: square.file)]))
                        .font(.system(size: squareSize * 0.16, weight: .bold, design: .rounded))
                        .foregroundStyle(labelColor)
                        .padding(3)
                }
            }
        }

        if square.file == leadingFile {
            VStack {
                HStack {
                    Text("\(square.rank + 1)")
                        .font(.system(size: squareSize * 0.16, weight: .bold, design: .rounded))
                        .foregroundStyle(labelColor)
                        .padding(3)
                    Spacer()
                }
                Spacer()
            }
        }
    }

    private func accessibilityLabel(for square: Square) -> String {
        guard let piece = session.position[square] else { return "\(square.notation)，空格" }
        return "\(square.notation)，\(piece.color.displayName)\(pieceName(piece.kind))"
    }

    private func accessibilityHint(for square: Square) -> String {
        guard isInteractionEnabled else { return "当前等待 AI 落子" }
        return session.legalTargets.contains(square) ? "轻点移动到此格" : "轻点选择"
    }

    private func pieceName(_ kind: PieceKind) -> String {
        switch kind {
        case .king: "王"
        case .queen: "后"
        case .rook: "车"
        case .bishop: "象"
        case .knight: "马"
        case .pawn: "兵"
        }
    }
}
