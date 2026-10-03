import AppKit
import SwiftUI

struct CodeBlockView: View {
    let language: String?
    let code: String
    @Environment(\.previewTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let language {
                    Text(language).font(.caption).foregroundStyle(theme.secondaryText.color)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("Copy code")
                .accessibilityLabel("Copy code")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            ScrollView(.horizontal) {
                Text(code)
                    .font(.system(size: theme.codeFontSize, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize()
                    .padding(12)
            }
        }
        .background(theme.codeBackground.color, in: RoundedRectangle(cornerRadius: 6))
    }
}
