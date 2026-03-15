import Foundation

/// Renders `ChartData` to an SVG string.
public struct SVGRenderer {
    
    public struct Config {
        public var width: Double
        public var height: Double
        public var margins: Margins
        public var title: String
        public var backgroundColor: String
        public var axisColor: String
        public var textColor: String
        public var fontFamily: String
        
        public struct Margins {
            public var top: Double
            public var right: Double
            public var bottom: Double
            public var left: Double
            
            public init(top: Double = 80, right: Double = 200, bottom: Double = 80, left: Double = 80) {
                self.top = top
                self.right = right
                self.bottom = bottom
                self.left = left
            }
        }
        
        public init(
            width: Double = 1200,
            height: Double = 600,
            margins: Margins = Margins(),
            title: String = "Code Archaeology: Lines of Code by Period",
            backgroundColor: String = "#1a1a2e",
            axisColor: String = "#4a4a6a",
            textColor: String = "#c0c0d0",
            fontFamily: String = "system-ui, -apple-system, sans-serif"
        ) {
            self.width = width
            self.height = height
            self.margins = margins
            self.title = title
            self.backgroundColor = backgroundColor
            self.axisColor = axisColor
            self.textColor = textColor
            self.fontFamily = fontFamily
        }
    }
    
    private let config: Config
    
    public init(config: Config = Config()) {
        self.config = config
    }
    
    /// Renders the chart data to a complete SVG string.
    public func render(_ data: ChartData) -> String {
        guard !data.isEmpty else {
            return emptySVG()
        }
        
        let plotWidth = config.width - config.margins.left - config.margins.right
        let plotHeight = config.height - config.margins.top - config.margins.bottom
        
        var svg = svgHeader()
        svg += background()
        svg += "<g transform=\"translate(\(config.margins.left), \(config.margins.top))\">\n"
        
        // Render areas (bottom to top, so later series paint on top)
        for series in data.series {
            svg += renderArea(series, plotWidth: plotWidth, plotHeight: plotHeight, maxY: data.maxLineCount)
        }
        
        // Version markers (vertical dashed lines with vertical labels)
        for marker in data.versionMarkers {
            let x = fmt(marker.x * plotWidth)
            
            // Dashed line
            svg += "<line x1=\"\(x)\" y1=\"-2\" x2=\"\(x)\" y2=\"\(fmt(plotHeight))\" "
            svg += "stroke=\"rgba(255,255,255,0.4)\" stroke-width=\"1\" stroke-dasharray=\"6,4\"/>\n"
            
            // Vertical label with tooltip
            svg += "<g cursor=\"default\">\n"
            svg += "  <title>\(escapeXML(marker.tooltipText))</title>\n"
            svg += "  <text x=\"\(x)\" y=\"-8\" "
            svg += "transform=\"rotate(-90, \(x), -8)\" "
            svg += "text-anchor=\"start\" fill=\"rgba(255,255,255,0.8)\" font-size=\"10\" font-weight=\"600\">"
            svg += "\(escapeXML(marker.label))</text>\n"
            svg += "</g>\n"
        }
        
        // Axes
        svg += renderXAxis(dates: data.commitDates, plotWidth: plotWidth, plotHeight: plotHeight)
        svg += renderYAxis(maxY: data.maxLineCount, plotWidth: plotWidth, plotHeight: plotHeight)
        
        svg += "</g>\n"
        
        // Title
        svg += renderTitle()
        
        // Legend
        svg += renderLegend(data: data)
        
        svg += "</svg>\n"
        return svg
    }
    
    /// Renders the chart with interactive HTML wrapper for WKWebView display.
    /// Includes a vertical crosshair and tooltip on hover.
    public func renderInteractiveHTML(_ data: ChartData) -> String {
        let svg = render(data)
        let tooltipData = buildTooltipJSON(data)
        let plotLeft = config.margins.left
        let plotRight = config.width - config.margins.right
        let plotTop = config.margins.top
        let plotBottom = config.height - config.margins.bottom
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <style>
            body {
                margin: 0;
                display: flex;
                justify-content: center;
                align-items: center;
                min-height: 100vh;
                background: #0d0d1a;
                position: relative;
            }
            svg { max-width: 100%; height: auto; }
            #crosshair {
                display: none;
                position: absolute;
                width: 1px;
                background: rgba(255,255,255,0.4);
                pointer-events: none;
                z-index: 10;
            }
            #tooltip {
                display: none;
                position: absolute;
                background: rgba(20, 20, 40, 0.95);
                border: 1px solid rgba(120, 120, 160, 0.4);
                border-radius: 8px;
                padding: 10px 14px;
                color: #d0d0e0;
                font-family: system-ui, -apple-system, sans-serif;
                font-size: 12px;
                pointer-events: none;
                z-index: 20;
                backdrop-filter: blur(8px);
                -webkit-backdrop-filter: blur(8px);
                box-shadow: 0 4px 20px rgba(0,0,0,0.5);
                min-width: 160px;
            }
            #tooltip .tt-date { font-weight: 700; font-size: 13px; margin-bottom: 6px; color: #e0e0f0; }
            #tooltip .tt-total { font-size: 11px; color: #a0a0b8; margin-bottom: 8px; padding-bottom: 6px; border-bottom: 1px solid rgba(120,120,160,0.2); }
            #tooltip .tt-row { display: flex; align-items: center; gap: 6px; padding: 2px 0; }
            #tooltip .tt-swatch { width: 10px; height: 10px; border-radius: 2px; flex-shrink: 0; }
            #tooltip .tt-period { flex: 1; }
            #tooltip .tt-count { font-variant-numeric: tabular-nums; color: #c0c0d0; }
        </style>
        </head>
        <body>
        \(svg)
        <div id="crosshair"></div>
        <div id="tooltip"></div>
        <script>
        const columns = \(tooltipData);
        const plotLeft = \(plotLeft);
        const plotRight = \(plotRight);
        const plotTop = \(plotTop);
        const plotBottom = \(plotBottom);
        
        const svgEl = document.querySelector('svg');
        const crosshair = document.getElementById('crosshair');
        const tooltip = document.getElementById('tooltip');
        
        function formatNum(n) {
            if (n >= 1000000) return (n/1000000).toFixed(1) + 'M';
            if (n >= 1000) return (n/1000).toFixed(1) + 'K';
            return n.toString();
        }
        
        svgEl.addEventListener('mousemove', function(e) {
            const rect = svgEl.getBoundingClientRect();
            const scaleX = \(config.width) / rect.width;
            const scaleY = \(config.height) / rect.height;
            const svgX = (e.clientX - rect.left) * scaleX;
            const svgY = (e.clientY - rect.top) * scaleY;
            
            if (svgX < plotLeft || svgX > plotRight || svgY < plotTop || svgY > plotBottom) {
                crosshair.style.display = 'none';
                tooltip.style.display = 'none';
                svgEl.style.cursor = 'default';
                return;
            }
            
            svgEl.style.cursor = 'crosshair';
            
            // Find nearest data column
            let closest = 0;
            let minDist = Infinity;
            for (let i = 0; i < columns.length; i++) {
                const colX = plotLeft + columns[i].x * (plotRight - plotLeft);
                const dist = Math.abs(svgX - colX);
                if (dist < minDist) { minDist = dist; closest = i; }
            }
            
            const col = columns[closest];
            const colScreenX = rect.left + (plotLeft + col.x * (plotRight - plotLeft)) / scaleX;
            
            // Crosshair
            crosshair.style.display = 'block';
            crosshair.style.left = colScreenX + 'px';
            crosshair.style.top = (rect.top + plotTop / scaleY) + 'px';
            crosshair.style.height = ((plotBottom - plotTop) / scaleY) + 'px';
            
            // Tooltip content
            let html = '<div class="tt-date">' + col.date + '</div>';
            html += '<div class="tt-total">Total: ' + formatNum(col.total) + ' lines</div>';
            for (let i = col.periods.length - 1; i >= 0; i--) {
                const p = col.periods[i];
                if (p.count === 0) continue;
                html += '<div class="tt-row">';
                html += '<div class="tt-swatch" style="background:' + p.color + '"></div>';
                html += '<div class="tt-period">' + p.period + '</div>';
                html += '<div class="tt-count">' + formatNum(p.count) + '</div>';
                html += '</div>';
            }
            tooltip.innerHTML = html;
            tooltip.style.display = 'block';
            
            // Position tooltip
            const ttW = tooltip.offsetWidth;
            let ttX = colScreenX + 16;
            if (ttX + ttW > window.innerWidth - 20) ttX = colScreenX - ttW - 16;
            tooltip.style.left = ttX + 'px';
            tooltip.style.top = (e.clientY - 30) + 'px';
        });
        
        svgEl.addEventListener('mouseleave', function() {
            crosshair.style.display = 'none';
            tooltip.style.display = 'none';
            svgEl.style.cursor = 'default';
        });
        </script>
        </body>
        </html>
        """
    }
    
    // MARK: - SVG Components
    
    private func svgHeader() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(config.width) \(config.height)" width="\(config.width)" height="\(config.height)">
        <style>
          text { font-family: \(config.fontFamily); }
        </style>
        
        """
    }
    
    private func background() -> String {
        "<rect width=\"\(config.width)\" height=\"\(config.height)\" fill=\"\(config.backgroundColor)\" rx=\"8\"/>\n"
    }
    
    private func emptySVG() -> String {
        var svg = svgHeader()
        svg += background()
        svg += "<text x=\"\(config.width / 2)\" y=\"\(config.height / 2)\" "
        svg += "text-anchor=\"middle\" fill=\"\(config.textColor)\" font-size=\"18\">"
        svg += "No data to display</text>\n"
        svg += "</svg>\n"
        return svg
    }
    
    private func renderArea(
        _ series: ChartData.Series,
        plotWidth: Double,
        plotHeight: Double,
        maxY: Double
    ) -> String {
        guard !series.points.isEmpty, maxY > 0 else { return "" }
        
        // Build SVG path: top edge left-to-right, then bottom edge right-to-left
        var pathParts: [String] = []
        
        // Top edge (left to right)
        for (i, point) in series.points.enumerated() {
            let x = fmt(point.x * plotWidth)
            let y = fmt(plotHeight - (point.yTop / maxY) * plotHeight)
            if i == 0 {
                pathParts.append("M \(x) \(y)")
            } else {
                pathParts.append("L \(x) \(y)")
            }
        }
        
        // Bottom edge (right to left)
        for point in series.points.reversed() {
            let x = fmt(point.x * plotWidth)
            let y = fmt(plotHeight - (point.yBottom / maxY) * plotHeight)
            pathParts.append("L \(x) \(y)")
        }
        
        pathParts.append("Z")
        
        return "<path d=\"\(pathParts.joined(separator: " "))\" fill=\"\(series.color)\" opacity=\"0.9\"/>\n"
    }
    
    private func renderXAxis(dates: [Date], plotWidth: Double, plotHeight: Double) -> String {
        guard !dates.isEmpty else { return "" }
        
        var svg = ""
        
        // Axis line
        svg += "<line x1=\"0\" y1=\"\(fmt(plotHeight))\" x2=\"\(fmt(plotWidth))\" y2=\"\(fmt(plotHeight))\" "
        svg += "stroke=\"\(config.axisColor)\" stroke-width=\"1\"/>\n"
        
        // Date labels (show ~8 evenly spaced)
        let labelCount = min(8, dates.count)
        let step = max(1, dates.count / labelCount)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM yyyy"
        
        for i in stride(from: 0, to: dates.count, by: step) {
            let x = dates.count > 1
                ? Double(i) / Double(dates.count - 1) * plotWidth
                : plotWidth / 2
            let label = dateFormatter.string(from: dates[i])
            
            // Tick line
            svg += "<line x1=\"\(fmt(x))\" y1=\"\(fmt(plotHeight))\" "
            svg += "x2=\"\(fmt(x))\" y2=\"\(fmt(plotHeight + 6))\" "
            svg += "stroke=\"\(config.axisColor)\" stroke-width=\"1\"/>\n"
            
            // Label
            svg += "<text x=\"\(fmt(x))\" y=\"\(fmt(plotHeight + 22))\" "
            svg += "text-anchor=\"middle\" fill=\"\(config.textColor)\" font-size=\"11\" "
            svg += "transform=\"rotate(-30, \(fmt(x)), \(fmt(plotHeight + 22)))\">"
            svg += "\(escapeXML(label))</text>\n"
        }
        
        // X axis label
        svg += "<text x=\"\(fmt(plotWidth / 2))\" y=\"\(fmt(plotHeight + 60))\" "
        svg += "text-anchor=\"middle\" fill=\"\(config.textColor)\" font-size=\"13\" font-weight=\"600\">"
        svg += "Date</text>\n"
        
        return svg
    }
    
    private func renderYAxis(maxY: Double, plotWidth: Double, plotHeight: Double) -> String {
        var svg = ""
        
        // Axis line
        svg += "<line x1=\"0\" y1=\"0\" x2=\"0\" y2=\"\(fmt(plotHeight))\" "
        svg += "stroke=\"\(config.axisColor)\" stroke-width=\"1\"/>\n"
        
        // Y labels (~5 ticks)
        let tickCount = 5
        let niceMax = niceNumber(maxY)
        let tickStep = niceMax / Double(tickCount)
        
        for i in 0...tickCount {
            let value = Double(i) * tickStep
            let y = plotHeight - (value / maxY) * plotHeight
            
            // Grid line
            svg += "<line x1=\"0\" y1=\"\(fmt(y))\" x2=\"\(fmt(plotWidth))\" y2=\"\(fmt(y))\" "
            svg += "stroke=\"\(config.axisColor)\" stroke-width=\"0.5\" stroke-dasharray=\"4,4\" opacity=\"0.4\"/>\n"
            
            // Label
            let label = formatNumber(value)
            svg += "<text x=\"-10\" y=\"\(fmt(y + 4))\" "
            svg += "text-anchor=\"end\" fill=\"\(config.textColor)\" font-size=\"11\">"
            svg += "\(label)</text>\n"
        }
        
        // Y axis label
        svg += "<text x=\"-55\" y=\"\(fmt(plotHeight / 2))\" "
        svg += "text-anchor=\"middle\" fill=\"\(config.textColor)\" font-size=\"13\" font-weight=\"600\" "
        svg += "transform=\"rotate(-90, -55, \(fmt(plotHeight / 2)))\">"
        svg += "Lines of Code</text>\n"
        
        return svg
    }
    
    private func renderTitle() -> String {
        "<text x=\"\(fmt(config.width / 2))\" y=\"35\" text-anchor=\"middle\" "
        + "fill=\"\(config.textColor)\" font-size=\"18\" font-weight=\"700\">"
        + "\(escapeXML(config.title))</text>\n"
    }
    
    private func renderLegend(data: ChartData) -> String {
        let legendX = config.width - config.margins.right + 20
        let legendY = config.margins.top + 10
        let itemHeight: Double = 22
        
        var svg = ""
        svg += "<text x=\"\(fmt(legendX))\" y=\"\(fmt(legendY - 5))\" "
        svg += "fill=\"\(config.textColor)\" font-size=\"12\" font-weight=\"600\">"
        svg += "\(escapeXML(data.legendTitle))</text>\n"
        
        // For chronological periods, show newest first (reversed).
        // For authors, series is already sorted by contribution (most first) — show as-is.
        let isAuthorMode = data.legendTitle == "Author"
        let maxLegendItems = min(data.allPeriods.count, 20)
        let legendSeries = isAuthorMode
            ? Array(data.series.prefix(maxLegendItems))
            : Array(data.series.reversed().prefix(maxLegendItems))
        
        for (i, series) in legendSeries.enumerated() {
            let y = legendY + Double(i) * itemHeight + 15
            
            // Color swatch
            svg += "<rect x=\"\(fmt(legendX))\" y=\"\(fmt(y - 10))\" "
            svg += "width=\"14\" height=\"14\" rx=\"2\" fill=\"\(series.color)\"/>\n"
            
            // Label
            svg += "<text x=\"\(fmt(legendX + 20))\" y=\"\(fmt(y + 1))\" "
            svg += "fill=\"\(config.textColor)\" font-size=\"11\">"
            svg += "\(escapeXML(series.period))</text>\n"
        }
        
        if data.allPeriods.count > maxLegendItems {
            let y = legendY + Double(maxLegendItems) * itemHeight + 15
            svg += "<text x=\"\(fmt(legendX))\" y=\"\(fmt(y + 1))\" "
            svg += "fill=\"\(config.textColor)\" font-size=\"10\" opacity=\"0.7\">"
            svg += "… and \(data.allPeriods.count - maxLegendItems) more</text>\n"
        }
        
        return svg
    }
    
    // MARK: - Helpers
    
    private func fmt(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
    
    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
    
    private func niceNumber(_ value: Double) -> Double {
        let exponent = floor(log10(value))
        let fraction = value / pow(10, exponent)
        let niceFraction: Double
        if fraction <= 1.5 { niceFraction = 1 }
        else if fraction <= 3.5 { niceFraction = 2 }
        else if fraction <= 7.5 { niceFraction = 5 }
        else { niceFraction = 10 }
        return niceFraction * pow(10, exponent)
    }
    
    private func formatNumber(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        } else {
            return String(format: "%.0f", value)
        }
    }
    
    /// Builds JSON array of column data for the interactive tooltip.
    private func buildTooltipJSON(_ data: ChartData) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d MMM yyyy"
        
        var columns: [String] = []
        
        for (dateIndex, date) in data.commitDates.enumerated() {
            let x = data.commitDates.count > 1
                ? Double(dateIndex) / Double(data.commitDates.count - 1)
                : 0.5
            let dateStr = dateFormatter.string(from: date)
            
            // Get per-period breakdown at this date index
            var periodEntries: [String] = []
            var total = 0
            for series in data.series {
                guard dateIndex < series.points.count else { continue }
                let pt = series.points[dateIndex]
                let count = Int(pt.yTop - pt.yBottom)
                total += count
                let escapedPeriod = series.period
                    .replacingOccurrences(of: "\"", with: "\\\"")
                periodEntries.append(
                    "{\"period\":\"\(escapedPeriod)\",\"color\":\"\(series.color)\",\"count\":\(count)}"
                )
            }
            
            columns.append(
                "{\"x\":\(String(format: "%.4f", x)),\"date\":\"\(dateStr)\",\"total\":\(total),\"periods\":[\(periodEntries.joined(separator: ","))]}"
            )
        }
        
        return "[\(columns.joined(separator: ","))]"
    }
}
