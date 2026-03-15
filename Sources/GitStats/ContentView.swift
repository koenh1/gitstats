import GitKit
import SwiftUI
import WebKit

struct ContentView: View {
    @State private var viewModel = AnalysisViewModel()

    var body: some View {
        HSplitView {
            // Sidebar
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 350)

            // Main content
            mainContent
                .frame(minWidth: 500)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("GitStats")
                    .font(.title.bold())
                Text("Code Archaeology")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Repository section
                    sidebarSection("Repository") {
                        repositoryPicker
                    }
                    .disabled(viewModel.isAnalyzing)

                    // Settings section
                    sidebarSection("Settings") {
                        settingsPanel
                    }
                    .disabled(viewModel.isAnalyzing)

                    // Contributors section
                    if !viewModel.discoveredContributors.isEmpty {
                        sidebarSection("Contributors") {
                            contributorsSection
                        }
                        .disabled(viewModel.isAnalyzing)
                    }

                    // Actions
                    analyzeButton

                    // Progress
                    if viewModel.isAnalyzing, let progress = viewModel.progress {
                        progressView(progress)
                    }

                    // Error
                    if let error = viewModel.errorMessage {
                        errorView(error)
                    }
                }
                .padding()
            }

            Spacer()

            // Export button at bottom
            if viewModel.hasResult {
                Divider()
                Button(action: viewModel.exportSVG) {
                    Label("Export SVG", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
        .background(.ultraThinMaterial)
    }

    private func sidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            content()
        }
    }

    private var repositoryPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: viewModel.selectRepository) {
                Label(
                    viewModel.repoPath != nil ? "Change Repository" : "Select Repository",
                    systemImage: "folder"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .controlSize(.regular)

            if let path = viewModel.repoPath {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(path.lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text(path.path)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sample count
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Commits to sample")
                        .font(.caption)
                    Spacer()
                    if viewModel.totalCommitCount > 0 {
                        Text("\(Int(viewModel.sampleCount)) of \(viewModel.totalCommitCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                Slider(
                    value: $viewModel.sampleCount,
                    in: 1...max(10, Double(viewModel.totalCommitCount)),
                    step: 1
                )
                .disabled(viewModel.totalCommitCount == 0)
            }

            // Granularity
            VStack(alignment: .leading, spacing: 4) {
                Text("Time granularity")
                    .font(.caption)
                Picker("", selection: $viewModel.granularity) {
                    Text("Year").tag(AnalysisConfig.TimeGranularity.year)
                    Text("Quarter").tag(AnalysisConfig.TimeGranularity.quarter)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Chart display mode
            VStack(alignment: .leading, spacing: 4) {
                Text("Display")
                    .font(.caption)
                Picker("", selection: $viewModel.chartMode) {
                    Text("By Period").tag(ChartMode.byPeriod)
                    Text("By Author").tag(ChartMode.byAuthor)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: viewModel.chartMode) {
                    if viewModel.hasResult {
                        viewModel.rerenderChart()
                    }
                }
            }

            // File extensions
            extensionsSection
        }
    }

    private var extensionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("File extensions")
                    .font(.caption)
                Spacer()
                if !viewModel.discoveredExtensions.isEmpty {
                    Button("All", action: viewModel.selectAll)
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    Text("·").foregroundStyle(.tertiary).font(.caption2)
                    Button("None", action: viewModel.selectNone)
                        .font(.caption2)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if viewModel.isLoadingExtensions {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6).frame(width: 12, height: 12)
                    Text("Scanning repo…").font(.caption2).foregroundStyle(.secondary)
                }
            } else if viewModel.discoveredExtensions.isEmpty {
                Text("Select a repository to discover file types")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.discoveredExtensions) { item in
                            Toggle(isOn: Bindable(item).isSelected) {
                                HStack(spacing: 4) {
                                    Text(item.ext)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(item.isTextType ? .primary : .secondary)
                                    Spacer()
                                    if item.isTextType && item.lineCount > 0 {
                                        Text(formatCount(item.lineCount) + " lines")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.tertiary)
                                    }
                                    Text(
                                        formatCount(item.fileCount)
                                            + (item.fileCount == 1 ? " file" : " files")
                                    )
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary)
                                }
                            }
                            .toggleStyle(.checkbox)
                            .onChange(of: item.isSelected) {
                                if viewModel.hasResult {
                                    viewModel.rerenderChart()
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
    }

    private var contributorsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Select contributors")
                    .font(.caption)
                Spacer()
                Button("All") { viewModel.selectAllContributors() }
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Button("None") { viewModel.selectNoContributors() }
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.discoveredContributors) { item in
                        Toggle(isOn: Bindable(item).isSelected) {
                            HStack(spacing: 4) {
                                Text(item.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(
                                    "\(item.commitCount) " + (item.commitCount == 1 ? "commit" : "commits")
                                )
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                            }
                        }
                        .toggleStyle(.checkbox)
                        .onChange(of: item.isSelected) {
                            if viewModel.hasResult {
                                viewModel.rerenderChart()
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
    }

    private var analyzeButton: some View {
        Button(action: viewModel.toggleAnalysis) {
            HStack {
                if viewModel.isAnalyzing {
                    Image(systemName: "stop.fill")
                } else {
                    Image(systemName: "waveform.path.ecg")
                }
                Text(viewModel.isAnalyzing ? "Cancel Analysis" : "Analyze Repository")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isAnalyzing ? .red : .accentColor)
        .controlSize(.large)
        .disabled(viewModel.repoPath == nil)
    }

    private func progressView(_ progress: AnalysisProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress.fraction)
                .progressViewStyle(.linear)

            Text("Commit \(progress.completed)/\(progress.total)  ·  \(progress.currentCommit)…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        }
        .padding(8)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        } else {
            return "\(value)"
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        Group {
            if let html = viewModel.interactiveHTML {
                SVGPreviewView(htmlString: html)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)

            Text("Select a repository and analyze it\nto see the code archaeology chart")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SVG Preview using WKWebView

struct SVGPreviewView: NSViewRepresentable {
    let htmlString: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(htmlString, baseURL: nil)
    }
}
