import Analysis
import GameCore
import SwiftUI

@MainActor
public struct QipanRootView: View {
    @StateObject private var session: GameSession
    @StateObject private var analysis: AnalysisCoordinator

    public init() {
        let initialPosition = GamePosition.starting
        _session = StateObject(wrappedValue: GameSession(position: initialPosition))
        _analysis = StateObject(wrappedValue: AnalysisCoordinator(initialPosition: initialPosition))
    }

    public var body: some View {
        GeometryReader { proxy in
            Group {
                if proxy.size.width >= 860 {
                    wideLayout
                } else {
                    compactLayout
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.appBackground)
        }
        .onChange(of: session.position) { _, newPosition in
            analysis.refresh(for: newPosition)
        }
        .task {
            analysis.refresh(for: session.position)
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                ChessBoardView(session: session, analysis: analysis.snapshot)
            }
            .frame(maxWidth: 700)

            ScrollView {
                AnalysisPanel(analysis: analysis.snapshot)
                    .padding(.bottom, 16)
            }
            .frame(minWidth: 290, idealWidth: 340, maxWidth: 380)
        }
        .padding(22)
    }

    private var compactLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                controls
                ChessBoardView(session: session, analysis: analysis.snapshot)
                AnalysisPanel(analysis: analysis.snapshot)
            }
            .padding(14)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("棋盘分析")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("多设备国际象棋原型")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(session.position.sideToMove == .white ? Color.white : Color.black)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(.secondary, lineWidth: 0.7))
                Text("\(session.position.sideToMove.displayName)回合")
                    .font(.callout.weight(.semibold))
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(AppTheme.panelBackground)
            .clipShape(Capsule())
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                heatmapToggle
                bestLineToggle
                Spacer(minLength: 4)
                resetButton
            }
            VStack(alignment: .leading, spacing: 10) {
                heatmapToggle
                bestLineToggle
                HStack {
                    Spacer()
                    resetButton
                }
            }
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

    private var bestLineToggle: some View {
        Toggle(isOn: $session.showsBestLineOnBoard) {
            Label("两步最佳路线", systemImage: "line.diagonal")
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var resetButton: some View {
        Button {
            session.reset()
        } label: {
            Label("重新开始", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
