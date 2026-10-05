import SwiftUI

/// The find bar above the preview: a field, "3 of 12", previous / next, match case, Done.
struct PreviewSearchBar: View {
    @Bindable var search: PreviewSearch
    @FocusState private var fieldHasFocus: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in preview", text: $search.query)
                .textFieldStyle(.plain)
                .focused($fieldHasFocus)
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.shift) { search.previous() } else { search.next() }
                    return .handled
                }
                .accessibilityIdentifier("preview-search-field")
            Text(search.status)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("preview-search-status")
            Button { search.previous() } label: { Image(systemName: "chevron.up") }
                .help("Previous match (⇧⌘G)")
                .disabled(search.matches.isEmpty)
            Button { search.next() } label: { Image(systemName: "chevron.down") }
                .help("Next match (⌘G)")
                .disabled(search.matches.isEmpty)
            Toggle(isOn: $search.caseSensitive) { Text("Aa") }
                .toggleStyle(.button)
                .help("Match case")
            Button("Done") { search.close() }
                .keyboardShortcut(.cancelAction)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .onAppear { fieldHasFocus = true }
        .onChange(of: search.focusToken) { _, _ in fieldHasFocus = true }
        .onChange(of: search.query) { _, _ in search.queryChanged() }
        .onChange(of: search.caseSensitive) { _, _ in search.queryChanged() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("preview-search-bar")
    }
}
