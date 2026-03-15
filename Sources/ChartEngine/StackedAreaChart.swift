import Foundation

/// Represents computed chart data ready for SVG rendering.
public struct ChartData {
    /// Each series represents one time period (e.g. "2023-Q1").
    public struct Series {
        public let period: String
        public let color: String  // hex color
        /// Points along the x-axis. Each point has (x: normalized 0-1, yBottom, yTop) in line-count space.
        public let points: [(x: Double, yBottom: Double, yTop: Double)]
    }
    
    /// A version marker with an x-position (0-1) and label.
    public struct VersionMarker {
        public let x: Double       // normalized 0-1 position on x-axis
        public let label: String   // short label (major.minor)
        public let tooltipText: String  // full tooltip: date + author + version
    }

    public let series: [Series]
    public let commitDates: [Date]
    public let maxLineCount: Double
    public let allPeriods: [String]  // sorted chronologically
    public let versionMarkers: [VersionMarker]
    public let legendTitle: String   // "Period Added" or "Author"

    public var isEmpty: Bool { series.isEmpty }
}

/// Builds chart data from raw line-age buckets.
public struct StackedAreaChart {

    public struct Bucket {
        public let commitDate: Date
        public let period: String
        public let lineCount: Int

        public init(commitDate: Date, period: String, lineCount: Int) {
            self.commitDate = commitDate
            self.period = period
            self.lineCount = lineCount
        }
    }

    /// Builds stacked chart data from an array of buckets, with optional version markers.
    public static func build(
        from buckets: [Bucket],
        versionMarkers: [(date: Date, label: String, fullVersion: String, author: String, source: String)] = []
    ) -> ChartData {
        guard !buckets.isEmpty else {
            return ChartData(series: [], commitDates: [], maxLineCount: 0, allPeriods: [], versionMarkers: [], legendTitle: "Period Added")
        }

        // Collect unique commit dates (sorted) and periods (sorted)
        var commitDateSet: Set<Date> = []
        var periodSet: Set<String> = []
        for b in buckets {
            commitDateSet.insert(b.commitDate)
            periodSet.insert(b.period)
        }
        let commitDates = commitDateSet.sorted()

        // Build lookup: commitDate -> period -> lineCount
        var lookup: [Date: [String: Int]] = [:]
        for b in buckets {
            lookup[b.commitDate, default: [:]][b.period] = b.lineCount
        }

        // Sort periods: if they look like date-based periods (e.g. "2023-Q1"), sort
        // chronologically. Otherwise (author names), sort by total line count descending
        // so the most prolific contributor is at the bottom of the stack.
        let periods: [String]
        let looksChronological = periodSet.contains { $0.hasPrefix("20") || $0.hasPrefix("19") }
        let legendTitle = looksChronological ? "Period Added" : "Author"
        if looksChronological {
            periods = periodSet.sorted()
        } else {
            // Sum total lines per period across all commits
            var totalByPeriod: [String: Int] = [:]
            for (_, periodCounts) in lookup {
                for (period, count) in periodCounts {
                    totalByPeriod[period, default: 0] += count
                }
            }
            periods = periodSet.sorted { totalByPeriod[$0, default: 0] > totalByPeriod[$1, default: 0] }
        }

        // Find max total for y-axis
        var maxTotal: Double = 0
        for date in commitDates {
            let total = periods.reduce(0) { sum, p in
                sum + Double(lookup[date]?[p] ?? 0)
            }
            maxTotal = max(maxTotal, total)
        }

        guard maxTotal > 0 else {
            return ChartData(
                series: [], commitDates: commitDates, maxLineCount: 0, allPeriods: periods, versionMarkers: [], legendTitle: legendTitle)
        }

        // Build stacked series
        var seriesList: [ChartData.Series] = []

        for (periodIndex, period) in periods.enumerated() {
            let color = ColorPalette.color(at: periodIndex, of: periods.count)
            var points: [(x: Double, yBottom: Double, yTop: Double)] = []

            for (dateIndex, date) in commitDates.enumerated() {
                let x =
                    commitDates.count > 1
                    ? Double(dateIndex) / Double(commitDates.count - 1)
                    : 0.5

                // Compute yBottom = sum of all previous periods at this date
                var yBottom: Double = 0
                for pi in 0..<periodIndex {
                    yBottom += Double(lookup[date]?[periods[pi]] ?? 0)
                }
                let value = Double(lookup[date]?[period] ?? 0)
                let yTop = yBottom + value

                points.append((x: x, yBottom: yBottom, yTop: yTop))
            }

            seriesList.append(
                ChartData.Series(
                    period: period,
                    color: color,
                    points: points
                ))
        }

        // Compute version marker positions
        let chartMarkers: [ChartData.VersionMarker]
        if !versionMarkers.isEmpty, let firstDate = commitDates.first, let lastDate = commitDates.last {
            let span = lastDate.timeIntervalSince(firstDate)
            let dateFmt = DateFormatter()
            dateFmt.dateStyle = .medium
            chartMarkers = span > 0 ? versionMarkers.compactMap { vm in
                let x = vm.date.timeIntervalSince(firstDate) / span
                guard x >= 0 && x <= 1 else { return nil }
                var tooltip = "\(vm.fullVersion)\n\(dateFmt.string(from: vm.date))"
                if !vm.author.isEmpty {
                    tooltip += "\n\(vm.author)"
                }
                tooltip += "\n(source: \(vm.source))"
                return ChartData.VersionMarker(x: x, label: vm.label, tooltipText: tooltip)
            } : []
        } else {
            chartMarkers = []
        }

        return ChartData(
            series: seriesList,
            commitDates: commitDates,
            maxLineCount: maxTotal,
            allPeriods: periods,
            versionMarkers: chartMarkers,
            legendTitle: legendTitle
        )
    }
}
