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
                    
                    // Files section
                    if viewModel.fileTreeRoot != nil {
                        sidebarSection("Files") {
                            filesSection
                        }
                        .disabled(viewModel.isAnalyzing)
                    }

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
                    ForEach(AnalysisConfig.TimeGranularity.allCases, id: \.self) { g in
                        Text(g.rawValue).tag(g)
                    }
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
            
            // Version markers toggle (only when markers exist)
            if !viewModel.versionMarkers.isEmpty {
                Toggle("Version markers", isOn: $viewModel.showVersionMarkers)
                    .font(.caption)
                    .onChange(of: viewModel.showVersionMarkers) {
                        if viewModel.hasResult {
                            viewModel.rerenderChart()
                        }
                    }
            }
        }
    }
    
    // MARK: - Files Section (Tree + Extension Preselection)
    
    private var filesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Extension preselection chips
            if !viewModel.discoveredExtensions.isEmpty {
                extensionPreselection
            }
            
            // File tree
            if let root = viewModel.fileTreeRoot {
                fileTreeView(root)
            }
        }
    }
    
    private var extensionPreselection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Preselect by extension")
                    .font(.caption)
                Spacer()
                Button("All") { viewModel.selectAllFiles() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                Text("·").foregroundStyle(.tertiary).font(.caption2)
                Button("None") { viewModel.selectNoFiles() }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
            }
            
            // Show all extensions as toggleable chips
            let allExts = viewModel.discoveredExtensions
            if !allExts.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(allExts) { item in
                        Button {
                            item.isSelected.toggle()
                            viewModel.applyExtensionPreselection()
                        } label: {
                            Text(item.ext)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    item.isSelected
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 4)
                                )
                                .foregroundStyle(item.isSelected ? Color.accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func fileTreeView(_ root: FileTreeNode) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(root.children) { child in
                        fileTreeRow(child, depth: 0)
                    }
                }
            }
            .frame(maxHeight: 250)
        }
    }
    
    private func fileTreeRow(_ node: FileTreeNode, depth: Int) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                // Indent
                if depth > 0 {
                    Spacer()
                        .frame(width: CGFloat(depth) * 16)
                }
                
                // Disclosure triangle for directories
                if node.isDirectory {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            node.isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption2)
                            .frame(width: 12, height: 12)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer().frame(width: 12)
                }
                
                // Three-state checkbox
                ThreeStateCheckbox(state: node.selectionState) {
                    node.toggle()
                    if viewModel.hasResult {
                        viewModel.rerenderChart()
                    }
                }
                
                // Icon
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(for: node.name))
                    .font(.caption)
                    .foregroundStyle(node.isDirectory ? .yellow : .secondary)
                
                // Name
                Text(node.name)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(
                        node.selectionState == .none ? .tertiary : .primary
                    )
                
                Spacer()
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture {
                if node.isDirectory {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        node.isExpanded.toggle()
                    }
                }
            }
            
            // Children (when expanded)
            if node.isDirectory && node.isExpanded {
                ForEach(node.children) { child in
                    fileTreeRow(child, depth: depth + 1)
                }
            }
        })
    }
    
    private func fileIcon(for name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "doc.text"
        case "js", "ts", "jsx", "tsx": return "doc.text"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "json", "yaml", "yml", "toml", "xml": return "gearshape"
        case "md", "txt", "rst": return "doc.plaintext"
        case "png", "jpg", "jpeg", "gif", "svg", "ico": return "photo"
        default: return "doc"
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
        let needsRun = viewModel.needsReanalysis
        
        return Button(action: viewModel.toggleAnalysis) {
            HStack {
                if viewModel.isAnalyzing {
                    Image(systemName: "stop.fill")
                } else {
                    Image(systemName: needsRun ? "waveform.path.ecg" : "checkmark.circle")
                }
                Text(
                    viewModel.isAnalyzing ? "Cancel Analysis"
                    : viewModel.hasResult && needsRun ? "Re-Analyze"
                    : viewModel.hasResult ? "Up to Date"
                    : "Analyze Repository"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(viewModel.isAnalyzing ? .red : needsRun ? .accentColor : .gray)
        .controlSize(.large)
        .disabled(viewModel.repoPath == nil || (!needsRun && !viewModel.isAnalyzing))
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
            } else if !viewModel.discoveredExtensions.isEmpty && !viewModel.isLoadingExtensions {
                preAnalysisDashboard
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
    
    // MARK: - Pre-Analysis Dashboard
    
    private var preAnalysisDashboard: some View {
        ScrollView {
            VStack(spacing: 28) {
                // Repo summary banner
                repoSummaryBanner
                
                // Charts in a horizontal pair
                HStack(alignment: .top, spacing: 24) {
                    // Extension pie chart
                    ExtensionPieChartView(
                        extensions: viewModel.discoveredExtensions.filter { $0.isTextType && $0.lineCount > 0 },
                        repoName: viewModel.repoName
                    )
                    .frame(minWidth: 300)
                    
                    // Contributor pie chart
                    ContributorPieChartView(
                        contributors: viewModel.discoveredContributors
                    )
                    .frame(minWidth: 300)
                }
                
                // Commit activity timeline
                CommitTimelineView(commitDates: viewModel.commitDates)
                    .frame(height: 180)
                    .padding(.horizontal, 8)
            }
            .padding(32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var repoSummaryBanner: some View {
        HStack(spacing: 0) {
            summaryStatItem(
                icon: "arrow.triangle.branch",
                value: "\(viewModel.totalCommitCount)",
                label: "Commits"
            )
            Divider().frame(height: 36)
            summaryStatItem(
                icon: "calendar",
                value: repoAgeString,
                label: "Active"
            )
            Divider().frame(height: 36)
            summaryStatItem(
                icon: "person.2",
                value: "\(viewModel.discoveredContributors.count)",
                label: "Contributors"
            )
            Divider().frame(height: 36)
            summaryStatItem(
                icon: "doc.text",
                value: "\(viewModel.totalFileCount)",
                label: "Files"
            )
            Divider().frame(height: 36)
            summaryStatItem(
                icon: "text.alignleft",
                value: formatCount(totalTextLines),
                label: "Lines of Code"
            )
        }
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func summaryStatItem(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var repoAgeString: String {
        guard let first = viewModel.firstCommitDate, let last = viewModel.lastCommitDate else { return "—" }
        let components = Calendar.current.dateComponents([.year, .month], from: first, to: last)
        let years = components.year ?? 0
        let months = components.month ?? 0
        if years > 0 {
            return months > 0 ? "\(years)y \(months)m" : "\(years)y"
        } else {
            return "\(max(1, months))m"
        }
    }
    
    private var totalTextLines: Int {
        viewModel.discoveredExtensions.filter(\.isTextType).reduce(0) { $0 + $1.lineCount }
    }
}

// MARK: - Three-State Checkbox

/// An NSViewRepresentable wrapping NSButton with allowsMixedState for three-state checkbox behavior.
struct ThreeStateCheckbox: NSViewRepresentable {
    let state: FileTreeNode.SelectionState
    let action: () -> Void
    
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(checkboxWithTitle: "", target: context.coordinator, action: #selector(Coordinator.clicked))
        button.allowsMixedState = true
        button.controlSize = .small
        return button
    }
    
    func updateNSView(_ button: NSButton, context: Context) {
        switch state {
        case .all: button.state = .on
        case .none: button.state = .off
        case .mixed: button.state = .mixed
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }
    
    class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func clicked() { action() }
    }
}

// MARK: - Flow Layout for extension chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }
    
    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }
        
        return (CGSize(width: maxX, height: y + rowHeight), positions)
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

// MARK: - Extension Pie Chart

struct ExtensionPieChartView: View {
    let extensions: [ExtensionItem]
    let repoName: String
    
    private static let colors: [Color] = [
        Color(hue: 0.58, saturation: 0.65, brightness: 0.85),  // blue
        Color(hue: 0.85, saturation: 0.55, brightness: 0.80),  // purple
        Color(hue: 0.35, saturation: 0.60, brightness: 0.75),  // green
        Color(hue: 0.08, saturation: 0.65, brightness: 0.90),  // orange
        Color(hue: 0.55, saturation: 0.50, brightness: 0.80),  // teal
        Color(hue: 0.95, saturation: 0.55, brightness: 0.85),  // pink
        Color(hue: 0.15, saturation: 0.60, brightness: 0.85),  // yellow
        Color(hue: 0.70, saturation: 0.45, brightness: 0.75),  // indigo
        Color(hue: 0.45, saturation: 0.55, brightness: 0.70),  // cyan
        Color(hue: 0.02, saturation: 0.60, brightness: 0.80),  // red
        Color(hue: 0.28, saturation: 0.50, brightness: 0.70),  // lime
        Color(hue: 0.78, saturation: 0.40, brightness: 0.70),  // lavender
    ]
    
    private var sortedExtensions: [ExtensionItem] {
        extensions.sorted { $0.lineCount > $1.lineCount }
    }
    
    private var totalLines: Int {
        extensions.reduce(0) { $0 + $1.lineCount }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Lines of Code by Extension")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            DonutChart(slices: sortedExtensions.enumerated().map { i, ext in
                DonutSlice(value: Double(ext.lineCount), color: Self.colors[i % Self.colors.count])
            })
            .frame(width: 200, height: 200)
            
            // Legend
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(sortedExtensions.enumerated()), id: \.element.id) { index, ext in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Self.colors[index % Self.colors.count])
                                .frame(width: 10, height: 10)
                            Text(ext.ext)
                                .font(.caption.monospaced())
                            Spacer()
                            Text(formatCount(ext.lineCount))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            let pct = totalLines > 0 ? Double(ext.lineCount) / Double(totalLines) * 100 : 0
                            Text(String(format: "%.0f%%", pct))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
    
    private func formatCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }
}

// MARK: - Contributor Pie Chart

struct ContributorPieChartView: View {
    let contributors: [ContributorItem]
    
    private static let colors: [Color] = [
        Color(hue: 0.08, saturation: 0.65, brightness: 0.90),  // orange
        Color(hue: 0.58, saturation: 0.65, brightness: 0.85),  // blue
        Color(hue: 0.35, saturation: 0.60, brightness: 0.75),  // green
        Color(hue: 0.85, saturation: 0.55, brightness: 0.80),  // purple
        Color(hue: 0.95, saturation: 0.55, brightness: 0.85),  // pink
        Color(hue: 0.15, saturation: 0.60, brightness: 0.85),  // yellow
        Color(hue: 0.55, saturation: 0.50, brightness: 0.80),  // teal
        Color(hue: 0.70, saturation: 0.45, brightness: 0.75),  // indigo
        Color(hue: 0.02, saturation: 0.60, brightness: 0.80),  // red
        Color(hue: 0.45, saturation: 0.55, brightness: 0.70),  // cyan
        Color(hue: 0.28, saturation: 0.50, brightness: 0.70),  // lime
        Color(hue: 0.78, saturation: 0.40, brightness: 0.70),  // lavender
    ]
    
    private var totalCommits: Int {
        contributors.reduce(0) { $0 + $1.commitCount }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Commits by Contributor")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            DonutChart(slices: contributors.enumerated().map { i, c in
                DonutSlice(value: Double(c.commitCount), color: Self.colors[i % Self.colors.count])
            })
            .frame(width: 200, height: 200)
            
            // Legend
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(contributors.enumerated()), id: \.element.id) { index, contributor in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Self.colors[index % Self.colors.count])
                                .frame(width: 10, height: 10)
                            Text(contributor.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text("\(contributor.commitCount)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            let pct = totalCommits > 0 ? Double(contributor.commitCount) / Double(totalCommits) * 100 : 0
                            Text(String(format: "%.0f%%", pct))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 32, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxHeight: 160)
        }
    }
}

// MARK: - Shared Donut Chart

struct DonutSlice {
    let value: Double
    let color: Color
}

struct DonutChart: View {
    let slices: [DonutSlice]
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outerRadius = min(size.width, size.height) / 2 - 2
            let innerRadius = outerRadius * 0.55
            let total = slices.reduce(0.0) { $0 + $1.value }
            guard total > 0 else { return }
            
            var startAngle = Angle.degrees(-90)
            
            for slice in slices {
                let fraction = slice.value / total
                let sweepAngle = Angle.degrees(fraction * 360)
                let endAngle = startAngle + sweepAngle
                
                var path = Path()
                path.addArc(center: center, radius: outerRadius,
                           startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.addArc(center: center, radius: innerRadius,
                           startAngle: endAngle, endAngle: startAngle, clockwise: true)
                path.closeSubpath()
                
                context.fill(path, with: .color(slice.color))
                context.stroke(path, with: .color(Color(nsColor: .windowBackgroundColor)), lineWidth: 1.5)
                
                startAngle = endAngle
            }
        }
    }
}

// MARK: - Commit Timeline

struct CommitTimelineView: View {
    let commitDates: [Date]
    
    private struct MonthBucket: Identifiable {
        let label: String  // e.g. "2023-01"
        let count: Int
        var id: String { label }
    }
    
    private var buckets: [MonthBucket] {
        guard !commitDates.isEmpty else { return [] }
        let calendar = Calendar(identifier: .gregorian)
        var counts: [String: Int] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        
        for date in commitDates {
            let key = formatter.string(from: date)
            counts[key, default: 0] += 1
        }
        
        // Generate continuous range of months from first to last
        guard let firstDate = commitDates.first, let lastDate = commitDates.last else { return [] }
        var result: [MonthBucket] = []
        var current = calendar.dateComponents([.year, .month], from: firstDate)
        let last = calendar.dateComponents([.year, .month], from: lastDate)
        
        while let year = current.year, let month = current.month {
            let key = String(format: "%04d-%02d", year, month)
            result.append(MonthBucket(label: key, count: counts[key] ?? 0))
            
            if year == last.year! && month == last.month! { break }
            
            if month == 12 {
                current.year = year + 1
                current.month = 1
            } else {
                current.month = month + 1
            }
        }
        
        return result
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("Commit Activity")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            
            let data = buckets
            if data.isEmpty {
                Text("No commit data")
                    .foregroundStyle(.tertiary)
            } else {
                let maxCount = data.map(\.count).max() ?? 1
                
                Canvas { context, size in
                    let barWidth = max(1, size.width / CGFloat(data.count) - 1)
                    let gap: CGFloat = 1
                    let chartHeight = size.height - 20  // leave room for labels
                    
                    for (i, bucket) in data.enumerated() {
                        let fraction = CGFloat(bucket.count) / CGFloat(maxCount)
                        let barHeight = max(fraction > 0 ? 1 : 0, fraction * chartHeight)
                        let x = CGFloat(i) * (barWidth + gap)
                        let y = chartHeight - barHeight
                        
                        let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                        let color = Color(hue: 0.58, saturation: 0.5 + 0.3 * Double(fraction), brightness: 0.85)
                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(color))
                    }
                    
                    // Year labels along the bottom
                    var lastYear = ""
                    for (i, bucket) in data.enumerated() {
                        let year = String(bucket.label.prefix(4))
                        if year != lastYear {
                            lastYear = year
                            let x = CGFloat(i) * (barWidth + gap)
                            let text = Text(year).font(.system(size: 9)).foregroundStyle(.tertiary)
                            context.draw(context.resolve(text), at: CGPoint(x: x, y: size.height - 4), anchor: .bottomLeading)
                        }
                    }
                }
                
                HStack {
                    if let first = data.first?.label, let last = data.last?.label {
                        Text(first)
                        Spacer()
                        Text("\(data.count) months")
                        Spacer()
                        Text(last)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
        }
    }
}
