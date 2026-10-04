import Analysis
import Charts
import GameCore
import SwiftUI

struct AdvantageTimelineView: View {
    let points: [AdvantagePoint]
    var perspective: PieceColor = .white
    var selectedPly: Int? = nil
    private var current: AdvantagePoint? {
        if let selectedPly { return points.last { $0.ply <= selectedPly } }
        return points.last
    }
    private func value(_ point: AdvantagePoint) -> Double {
        point.magnitude(from: perspective)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(current?.summary ?? "等待第一份局势评价")
                    .font(.callout.weight(.semibold))
                Spacer()
                Text("\(points.count) 步记录")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if points.isEmpty {
                ContentUnavailableView(
                    "时间轴等待落子",
                    systemImage: "chart.xyaxis.line",
                    description: Text("走棋后会记录已有的局势评价，无需额外分析。")
                )
                .frame(height: 154)
            } else {
                Chart(points) { point in
                    RuleMark(y: .value("均衡", 0))
                        .foregroundStyle(.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    AreaMark(
                        x: .value("步数", point.ply),
                        yStart: .value("均衡线", 0),
                        yEnd: .value("优势", value(point))
                    )
                    .foregroundStyle(AppTheme.accent.opacity(0.14))
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("步数", point.ply),
                        y: .value("优势", value(point))
                    )
                    .foregroundStyle(AppTheme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)

                    if let classification = point.classification {
                        PointMark(
                            x: .value("步数", point.ply),
                            y: .value("优势", value(point))
                        )
                        .symbol {
                            MoveQualityBadge(classification: classification, size: point.id == current?.id ? 22 : 16)
                        }
                    }
                }
                .chartYScale(domain: -8...8)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [-6.0, 0.0, 6.0]) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                        AxisValueLabel {
                            if let score = value.as(Double.self) {
                                Text(axisTitle(for: score))
                                    .font(.caption2)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let ply = value.as(Int.self) {
                                Text(ply == 0 ? "开始" : "\(ply)")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                    }
                }
                .frame(height: 154)
                .animation(.easeInOut(duration: 0.25), value: points)
                .accessibilityLabel("优势时间轴")
                .accessibilityValue(current?.summary ?? "等待评价")
            }

            Text("上方表示\(perspective.displayName)占优，下方表示\(perspective.displayName)处于劣势；视角跟随棋盘下方的一方。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func axisTitle(for score: Double) -> String {
        if score > 0 { return "优势" }
        if score < 0 { return "劣势" }
        return "均衡"
    }
}
