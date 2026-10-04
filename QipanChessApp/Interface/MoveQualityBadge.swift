import Analysis
import SwiftUI

extension ReviewQuality {
    var badgeColor: Color {
        let value = UInt32(colorHex, radix: 16) ?? 0x81b64c
        return Color(red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255,
                     blue: Double(value & 255) / 255)
    }
}

struct MoveQualityBadge: View {
    let classification: ReviewQuality
    var size: CGFloat = 22
    var body: some View {
        Group {
            #if os(macOS)
            if NSImage(named: "MoveBadge-\(classification.rawValue)") != nil {
                Image("MoveBadge-\(classification.rawValue)", bundle: .main).resizable().interpolation(.high)
            } else { fallback }
            #else
            Image("MoveBadge-\(classification.rawValue)", bundle: .main).resizable().interpolation(.high)
            #endif
        }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: max(0.75, size * 0.035)))
            .accessibilityLabel("\(classification.title)，\(classification.symbol)")
            .help(classification.title + "：" + classification.meaning)
    }
    private var fallback: some View {
        ZStack { Circle().fill(classification.badgeColor); Text(classification.symbol).font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white) }
    }

}

struct MoveClassificationLabel: View {
    let classification: ReviewQuality
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: 6) {
            MoveQualityBadge(classification: classification, size: size)
            Text(classification.title).font(.caption.weight(.semibold))
        }
        .foregroundStyle(classification.badgeColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(classification.title + "，" + classification.meaning)
    }
}

struct MoveClassificationLegend: View {
    var body: some View {
        DisclosureGroup("棋步标记图例") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(ReviewQuality.allCases, id: \.self) { classification in
                    VStack(alignment: .leading, spacing: 4) {
                        MoveClassificationLabel(classification: classification, size: 24)
                        Text(classification.meaning).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding(.top, 8)
        }.font(.caption)
    }
}

func qualityColor(_ quality: ReviewQuality) -> Color { quality.badgeColor }
