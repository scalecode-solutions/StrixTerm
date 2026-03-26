#if canImport(SwiftUI)
import SwiftUI
import FredTermCore

/// A floating find bar overlay for terminal text search.
///
/// Provides browser-style inline search with result navigation,
/// case sensitivity toggle, and regex toggle.
@available(macOS 15.0, iOS 18.0, visionOS 2.0, *)
public struct FindBarView: View {
    @Binding var isVisible: Bool
    @State var searchText: String = ""
    @State var results: [SearchResult] = []
    @State var currentResultIndex: Int = 0
    @State var options: SearchOptions = SearchOptions()

    let terminal: Terminal
    let onHighlight: ((SearchResult?) -> Void)?

    /// Debounce task for auto-search-as-you-type.
    @State private var searchTask: Task<Void, Never>?

    public init(
        isVisible: Binding<Bool>,
        terminal: Terminal,
        onHighlight: ((SearchResult?) -> Void)? = nil
    ) {
        self._isVisible = isVisible
        self.terminal = terminal
        self.onHighlight = onHighlight
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Search text field
            TextField("Find in terminal...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        #if os(macOS)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        #else
                        .fill(Color(uiColor: .systemBackground))
                        #endif
                )
                .frame(minWidth: 180, maxWidth: 280)
                .onSubmit {
                    navigateNext()
                }
                .onChange(of: searchText) {
                    debouncedSearch()
                }
                .accessibilityLabel("Search terminal text")
                .accessibilityHint("Type to search for text in the terminal")

            // Result count label
            Text(resultCountLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(minWidth: 60)
                .accessibilityLabel(resultAccessibilityLabel)

            // Navigation buttons
            Button(action: navigatePrevious) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(results.isEmpty)
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .accessibilityLabel("Previous result")

            Button(action: navigateNext) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
            .disabled(results.isEmpty)
            .keyboardShortcut("g", modifiers: .command)
            .accessibilityLabel("Next result")

            Divider()
                .frame(height: 16)

            // Case sensitivity toggle
            Toggle(isOn: $options.caseSensitive) {
                Text("Aa")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .onChange(of: options.caseSensitive) {
                performSearch()
            }
            .accessibilityLabel("Case sensitive")
            .accessibilityHint(options.caseSensitive ? "Case sensitive search is on" : "Case sensitive search is off")

            // Regex toggle
            Toggle(isOn: $options.regex) {
                Text(".*")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .onChange(of: options.regex) {
                performSearch()
            }
            .accessibilityLabel("Regular expression")
            .accessibilityHint(options.regex ? "Regex search is on" : "Regex search is off")

            Divider()
                .frame(height: 16)

            // Close button
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                #if os(macOS)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                #else
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                #endif
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Find bar")
    }

    // MARK: - Result Label

    private var resultCountLabel: String {
        if searchText.isEmpty {
            return ""
        }
        if results.isEmpty {
            return "No results"
        }
        return "\(currentResultIndex + 1) of \(results.count)"
    }

    private var resultAccessibilityLabel: String {
        if searchText.isEmpty {
            return "No search query"
        }
        if results.isEmpty {
            return "No results found"
        }
        return "Result \(currentResultIndex + 1) of \(results.count)"
    }

    // MARK: - Search Logic

    /// Debounced search: waits 200ms after the last keystroke before searching.
    private func debouncedSearch() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            guard !Task.isCancelled else { return }
            performSearch()
        }
    }

    /// Execute the search against the terminal buffer.
    private func performSearch() {
        guard !searchText.isEmpty else {
            results = []
            currentResultIndex = 0
            onHighlight?(nil)
            return
        }

        let searchResults = terminal.search(query: searchText, options: options)
        results = searchResults
        if results.isEmpty {
            currentResultIndex = 0
            onHighlight?(nil)
        } else {
            currentResultIndex = 0
            highlightCurrent()
        }
    }

    /// Navigate to the next search result.
    private func navigateNext() {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex + 1) % results.count
        highlightCurrent()
    }

    /// Navigate to the previous search result.
    private func navigatePrevious() {
        guard !results.isEmpty else { return }
        currentResultIndex = (currentResultIndex - 1 + results.count) % results.count
        highlightCurrent()
    }

    /// Highlight the current result and scroll to it.
    private func highlightCurrent() {
        guard currentResultIndex < results.count else { return }
        let result = results[currentResultIndex]
        onHighlight?(result)
        terminal.scrollToLine(result.lineIndex)
    }

    /// Close the find bar.
    private func close() {
        searchTask?.cancel()
        searchText = ""
        results = []
        currentResultIndex = 0
        onHighlight?(nil)
        isVisible = false
    }
}

#endif
