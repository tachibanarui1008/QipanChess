import SwiftUI
struct WholeRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack {
                    Image(systemName: "chevron.right").font(.caption.bold()).rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityValue(configuration.isExpanded ? "已展开" : "已折叠")
            if configuration.isExpanded { configuration.content.padding(.leading, 16) }
        }
    }
}
