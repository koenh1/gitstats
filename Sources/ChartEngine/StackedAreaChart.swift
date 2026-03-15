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

    public let series: [Series]
    public let commitDates: [Date]
    public let maxLineCount: Double
    public let allPeriods: [String]  // sorted chronologically

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

    /// Builds stacked chart data from an array of buckets.
    public static func build(from buckets: [Bucket]) -> ChartData {
        guard !buckets.isEmpty else {
            return ChartData(series: [], commitDates: [], maxLineCount: 0, allPeriods: [])
        }

        // Collect unique commit dates (sorted) and periods (sorted)
        var commitDateSet: Set<Date> = []
        var periodSet: Set<String> = []
        for b in buckets {
            commitDateSet.insert(b.commitDate)
            periodSet.insert(b.period)
        }
        let commitDates = commitDateSet.sorted()
        let periods = periodSet.sorted()

        // Build lookup: commitDate -> period -> lineCount
        var lookup: [Date: [String: Int]] = [:]
        for b in buckets {
            lookup[b.commitDate, default: [:]][b.period] = b.lineCount
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
                series: [], commitDates: commitDates, maxLineCount: 0, allPeriods: periods)
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

        return ChartData(
            series: seriesList,
            commitDates: commitDates,
            maxLineCount: maxTotal,
            allPeriods: periods
        )
    }
}
