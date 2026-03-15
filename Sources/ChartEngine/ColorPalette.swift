import Foundation

/// A viridis-inspired color palette for chart rendering.
public struct ColorPalette {
    
    /// Viridis color stops (subset of the matplotlib viridis colormap).
    /// Each entry is (r, g, b) in 0–255 range.
    private static let viridis: [(r: Int, g: Int, b: Int)] = [
        (68, 1, 84),
        (72, 24, 106),
        (68, 57, 131),
        (56, 88, 140),
        (44, 113, 142),
        (33, 133, 141),
        (32, 155, 130),
        (56, 176, 113),
        (94, 194, 87),
        (143, 210, 56),
        (196, 222, 27),
        (253, 231, 37),
    ]
    
    /// Returns a hex color string for the given index out of totalCount items.
    /// Interpolates across the viridis palette.
    public static func color(at index: Int, of totalCount: Int) -> String {
        guard totalCount > 1 else {
            let c = viridis[viridis.count / 2]
            return hexString(r: c.r, g: c.g, b: c.b)
        }
        
        let t = Double(index) / Double(totalCount - 1)
        let scaledIndex = t * Double(viridis.count - 1)
        let lower = Int(scaledIndex)
        let upper = min(lower + 1, viridis.count - 1)
        let frac = scaledIndex - Double(lower)
        
        let r = Int(Double(viridis[lower].r) * (1 - frac) + Double(viridis[upper].r) * frac)
        let g = Int(Double(viridis[lower].g) * (1 - frac) + Double(viridis[upper].g) * frac)
        let b = Int(Double(viridis[lower].b) * (1 - frac) + Double(viridis[upper].b) * frac)
        
        return hexString(r: r, g: g, b: b)
    }
    
    private static func hexString(r: Int, g: Int, b: Int) -> String {
        String(format: "#%02x%02x%02x", r, g, b)
    }
}
