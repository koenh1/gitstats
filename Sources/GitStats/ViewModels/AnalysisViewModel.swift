import AppKit
import ChartEngine
import GitKit
import SwiftUI
import UniformTypeIdentifiers

/// Represents a discovered file extension with its selection state.
@Observable
final class ExtensionItem: Identifiable {
    let ext: String
    let fileCount: Int
    let lineCount: Int
    let isTextType: Bool
    var isSelected: Bool

    var id: String { ext }

    init(ext: String, fileCount: Int, lineCount: Int, isTextType: Bool) {
        self.ext = ext
        self.fileCount = fileCount
        self.lineCount = lineCount
        self.isTextType = isTextType
        self.isSelected = isTextType  // only text types selected by default
    }
}

/// Represents a discovered contributor with their commit count.
@Observable
final class ContributorItem: Identifiable {
    let name: String
    let commitCount: Int
    var isSelected: Bool

    var id: String { name }

    init(name: String, commitCount: Int) {
        self.name = name
        self.commitCount = commitCount
        self.isSelected = true  // all contributors selected by default
    }
}

enum ChartMode: String, CaseIterable {
    case byPeriod = "By Period"
    case byAuthor = "By Author"
}

@Observable
final class AnalysisViewModel {
    var repoPath: URL?
    var repoName: String = ""

    // Config
    var sampleCount: Double = 50
    var totalCommitCount: Int = 0
    var granularity: AnalysisConfig.TimeGranularity = .quarter
    var chartMode: ChartMode = .byPeriod
    var discoveredExtensions: [ExtensionItem] = []
    var discoveredContributors: [ContributorItem] = []
    var isLoadingExtensions: Bool = false

    // State
    var isAnalyzing: Bool = false
    var progress: AnalysisProgress?
    var svgString: String?  // Pure SVG for export
    var interactiveHTML: String?  // HTML+JS for WKWebView display
    var errorMessage: String?
    private var analysisTask: Task<Void, Never>?
    private var allBuckets: [LineAgeBucket] = []  // stored for re-rendering

    var hasResult: Bool { svgString != nil }

    var selectedExtensions: Set<String> {
        Set(discoveredExtensions.filter(\.isSelected).map(\.ext))
    }

    var selectedAuthors: Set<String>? {
        let selected = Set(discoveredContributors.filter(\.isSelected).map(\.name))
        // If all are selected, return nil (= no filter)
        if selected.count == discoveredContributors.count { return nil }
        return selected
    }

    func selectRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a Git Repository"
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            repoPath = url
            repoName = url.lastPathComponent
            svgString = nil
            interactiveHTML = nil
            errorMessage = nil
            loadExtensions()
        }
    }

    func selectAll() {
        for item in discoveredExtensions { item.isSelected = true }
    }

    func selectNone() {
        for item in discoveredExtensions { item.isSelected = false }
    }

    func selectAllContributors() {
        for item in discoveredContributors { item.isSelected = true }
    }

    func selectNoContributors() {
        for item in discoveredContributors { item.isSelected = false }
    }

    private func loadExtensions() {
        guard let repoPath else { return }
        isLoadingExtensions = true
        discoveredExtensions = []
        discoveredContributors = []

        Task {
            do {
                let repo = try GitRepository(path: repoPath)
                let commits = try await repo.allCommits()
                let stats = try await repo.fileExtensionStats()

                await MainActor.run {
                    self.totalCommitCount = commits.count
                    self.sampleCount = min(self.sampleCount, Double(commits.count))
                    self.discoveredExtensions = stats.map { s in
                        ExtensionItem(
                            ext: s.ext,
                            fileCount: s.fileCount,
                            lineCount: s.lineCount,
                            isTextType: s.isTextType
                        )
                    }
                    // Discover contributors from commits
                    var authorCounts: [String: Int] = [:]
                    for commit in commits {
                        authorCounts[commit.author, default: 0] += 1
                    }
                    self.discoveredContributors = authorCounts
                        .sorted { $0.value > $1.value }  // most commits first
                        .map { ContributorItem(name: $0.key, commitCount: $0.value) }
                    self.isLoadingExtensions = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to read extensions: \(error.localizedDescription)"
                    self.isLoadingExtensions = false
                }
            }
        }
    }

    /// Toggle between starting and cancelling analysis.
    func toggleAnalysis() {
        if isAnalyzing {
            cancelAnalysis()
        } else {
            runAnalysis()
        }
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        analysisTask = nil
        isAnalyzing = false
        progress = nil
    }

    private func runAnalysis() {
        guard let repoPath else { return }

        let selected = selectedExtensions
        guard !selected.isEmpty else {
            errorMessage = "Select at least one file extension"
            return
        }

        isAnalyzing = true
        errorMessage = nil
        svgString = nil
        interactiveHTML = nil
        progress = nil

        let config = AnalysisConfig(
            sampleCount: Int(sampleCount),
            fileExtensions: selected,
            granularity: granularity
        )

        analysisTask = Task {
            do {
                let repo = try GitRepository(path: repoPath)
                let engine = AnalysisEngine(repo: repo)

                let buckets = try await engine.analyze(config: config) { [weak self] prog in
                    Task { @MainActor in
                        self?.progress = prog
                    }
                }

                try Task.checkCancellation()

                await MainActor.run {
                    self.allBuckets = buckets
                    self.rerenderChart()
                    self.isAnalyzing = false
                    self.analysisTask = nil
                }
            } catch is CancellationError {
                // User cancelled — no error to show
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isAnalyzing = false
                    self.analysisTask = nil
                }
            }
        }
    }

    /// Re-renders the chart from stored buckets, filtering by currently selected extensions and authors.
    /// Called after analysis and whenever extension or contributor selection changes.
    func rerenderChart() {
        let selectedExts = selectedExtensions
        let selectedAuth = selectedAuthors
        guard !allBuckets.isEmpty, !selectedExts.isEmpty else {
            svgString = nil
            interactiveHTML = nil
            return
        }
        
        // Filter buckets by selected extensions and authors
        let filtered = allBuckets.filter { bucket in
            guard selectedExts.contains(bucket.fileExtension) else { return false }
            if let authors = selectedAuth {
                return authors.contains(bucket.commitAuthor)
            }
            return true
        }
        
        // Aggregate: combine line counts for same (commitDate, groupKey)
        // groupKey is either the period or the author depending on chartMode
        var aggregated: [String: [String: Int]] = [:] // dateKey -> groupKey -> count
        var dateByKey: [String: Date] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        for bucket in filtered {
            let dateKey = dateFormatter.string(from: bucket.commitDate)
            let groupKey = chartMode == .byAuthor ? bucket.commitAuthor : bucket.period
            dateByKey[dateKey] = bucket.commitDate
            aggregated[dateKey, default: [:]][groupKey, default: 0] += bucket.lineCount
        }
        
        let chartBuckets = aggregated.flatMap { (dateKey, periods) -> [StackedAreaChart.Bucket] in
            guard let date = dateByKey[dateKey] else { return [] }
            return periods.map { (period, count) in
                StackedAreaChart.Bucket(commitDate: date, period: period, lineCount: count)
            }
        }
        
        let chartData = StackedAreaChart.build(from: chartBuckets)
        
        var rendererConfig = SVGRenderer.Config()
        rendererConfig.title = "Code Archaeology: \(repoName)"
        let renderer = SVGRenderer(config: rendererConfig)
        svgString = renderer.render(chartData)
        interactiveHTML = renderer.renderInteractiveHTML(chartData)
    }

    func exportSVG() {
        guard let svgString else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = "\(repoName)-archaeology.svg"
        panel.canCreateDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try svgString.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Failed to export: \(error.localizedDescription)"
            }
        }
    }
}
