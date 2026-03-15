# GitStats

A macOS app for **code archaeology** — visualize how your codebase evolved over time by analyzing git blame data across sampled commits.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## What It Does

GitStats samples commits from a repository's history, runs `git blame` on each, and produces an interactive **stacked area chart** showing how lines of code are distributed across time periods. This reveals:

- **Code age** — how much of today's codebase was written in each quarter/year
- **Author contributions** — who wrote which portions of the code over time
- **Churn patterns** — whether old code is being replaced or accumulating

### Pre-Analysis Dashboard

Before running analysis, GitStats shows an overview of your repository:

- **Summary banner** — total commits, repo age, contributor count, file count, total LOC
- **Extension breakdown** — donut chart of lines of code by file type
- **Contributor breakdown** — donut chart of commits by author
- **Commit activity timeline** — monthly bar chart of commit frequency

## Architecture

```
GitStats (Swift Package)
├── GitKit          — Git operations (blame, log, file listing)
├── ChartEngine     — SVG chart rendering with interactive tooltips
└── GitStats        — SwiftUI macOS app (views + view models)
```

### Key Components

| Module | File | Purpose |
|--------|------|---------|
| **GitKit** | `GitRepository.swift` | Git operations via shell (`git log`, `git blame`, `git ls-tree`) |
| **GitKit** | `AnalysisEngine.swift` | Samples commits, runs parallel blame, aggregates into buckets |
| **GitKit** | `AuthorNormalizer.swift` | Normalizes author names (case, separators, formats) |
| **ChartEngine** | `StackedAreaChart.swift` | Builds chart data model from line-age buckets |
| **ChartEngine** | `SVGRenderer.swift` | Renders stacked area chart as SVG with interactive HTML tooltips |
| **ChartEngine** | `ColorPalette.swift` | Curated color palette for chart series |
| **GitStats** | `ContentView.swift` | Main UI — sidebar controls + chart display |
| **GitStats** | `AnalysisViewModel.swift` | App state, analysis orchestration, chart re-rendering |
| **GitStats** | `FileTreeNode.swift` | Hierarchical file selection model with three-state checkboxes |

## Building & Running

```bash
# Run directly
swift run GitStats

# Or open in Xcode
open Package.swift
```

Requires **macOS 14+** and **Xcode 15+**.

## Usage

1. **Select a repository** — click "Select Repository" and choose a local git repo
2. **Review the dashboard** — see repo stats, extension/contributor breakdowns, and commit activity
3. **Configure analysis** — adjust sample count, time granularity, and file/author selection
4. **Run analysis** — click "Analyze Repository" to start blame sampling
5. **Explore the chart** — hover over the interactive chart for per-commit breakdowns
6. **Export** — save the chart as SVG

### File Selection

The sidebar provides a **collapsible file tree** with three-state checkboxes:
- ✅ All files in directory selected
- ☐ No files selected
- ▣ Some files selected (mixed state)

Use the **extension preselection chips** to quickly toggle all files of a type.

### Display Modes

- **By Period** — color-codes lines by when they were written (quarter/year/month)
- **By Author** — color-codes lines by who wrote them

## Built With

This project was built using [Antigravity](https://antigravity.dev), an agentic AI coding assistant powered by **Claude Opus 4.6** from Anthropic. The entire codebase — from the Git analysis engine and SVG chart renderer to the SwiftUI interface and interactive features — was developed through pair programming with the AI agent.

## License

MIT
