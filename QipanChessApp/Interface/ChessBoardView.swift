import Analysis
import GameCore
import SwiftUI

struct ChessBoardView: View {
    @ObservedObject var session: GameSession
    let analysis: PositionAnalysis

    var body: some View {
        GeometryReader { proxy in
            let length = min(proxy.size.width, proxy.size.height)
            let squareSize = length / 8

            ZStack {
                boardGrid(squareSize: squareSize)

                if session.showsBestLineOnBoard {
                    bestLineOverlay(squareSize: squareSize)
                        .allowsHitTesting(false)
                        .transition(.opacity)
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

    private func boardGrid(squareSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array((0..<8).reversed()), id: \.self) { rank in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { file in
                        if let square = Square(file: file, rank: rank) {
                            squareButton(square, squareSize: squareSize)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bestLineOverlay(squareSize: CGFloat) -> some View {
        let routes: [(move: Move, step: Int, color: Color)] = [
            analysis.bestLine.currentMove.map { ($0, 1, AppTheme.primaryRoute) },
            analysis.bestLine.bestReply.map { ($0, 2, AppTheme.replyRoute) }
        ].compactMap { $0 }

        ZStack {
            ForEach(routes, id: \.step) { route in
                let from = center(of: route.move.from, squareSize: squareSize)
                let to = center(of: route.move.to, squareSize: squareSize)

                Path { path in
                    path.move(to: from)
                    path.addLine(to: to)
                }
                .stroke(
                    route.color.opacity(0.86),
                    style: StrokeStyle(
                        lineWidth: max(3, squareSize * 0.085),
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .shadow(color: .black.opacity(0.36), radius: 1.5, y: 1)

                routeRing(color: route.color, squareSize: squareSize)
                    .position(from)
                routeRing(color: route.color, squareSize: squareSize)
                    .position(to)

                routeBadge(
                    step: route.step,
                    color: route.color,
                    squareSize: squareSize
                )
                .position(badgePosition(for: route.move.to, squareSize: squareSize))
            }
        }
        .accessibilityHidden(true)
    }

    private func routeRing(color: Color, squareSize: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(0.16))
            .overlay {
                Circle()
                    .stroke(color.opacity(0.94), lineWidth: max(2, squareSize * 0.045))
            }
            .frame(width: squareSize * 0.48, height: squareSize * 0.48)
    }

    private func routeBadge(step: Int, color: Color, squareSize: CGFloat) -> some View {
        Text("\(step)")
            .font(.system(size: squareSize * 0.18, weight: .heavy, design: .rounded))
            .foregroundStyle(Color.black.opacity(0.82))
            .frame(width: squareSize * 0.32, height: squareSize * 0.32)
            .background(color)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1))
            .shadow(color: .black.opacity(0.32), radius: 1, y: 1)
    }

    private func center(of square: Square, squareSize: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(square.file) + 0.5) * squareSize,
            y: (CGFloat(7 - square.rank) + 0.5) * squareSize
        )
    }

    private func badgePosition(for square: Square, squareSize: CGFloat) -> CGPoint {
        CGPoint(
            x: (CGFloat(square.file) + 0.79) * squareSize,
            y: (CGFloat(7 - square.rank) + 0.21) * squareSize
        )
    }

    private func squareButton(_ square: Square, squareSize: CGFloat) -> some View {
        Button {
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
        .accessibilityHint(session.legalTargets.contains(square) ? "轻点移动到此格" : "轻点选择")
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

        if square.rank == 0 {
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

        if square.file == 0 {
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
