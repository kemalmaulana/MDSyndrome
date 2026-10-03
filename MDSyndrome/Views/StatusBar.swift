import MarkdownCore
import SwiftUI

struct StatusBar: View {
    let stats: DocumentStats

    var body: some View {
        HStack(spacing: 12) {
            Text(stats.words == 1 ? "1 word" : "\(stats.words) words")
            Text("\(stats.characters) characters")
            Text("\(stats.lines) lines")
            Text("\(stats.readingMinutes) min read")
            Spacer()
        }
        .font(.caption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("status-bar")
    }
}
