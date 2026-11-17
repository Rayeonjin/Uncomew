import Foundation
import CoreGraphics

// Pure geometry: sibling weights only, never add ancestors and descendants.
enum SpaceMapLayout {
    struct Tile: Identifiable {
        let id: Int
        let rect: CGRect
    }
    static func tiles(weights: [Double], in rect: CGRect) -> [Tile] {
        let entries = weights.enumerated().filter { $0.element.isFinite && $0.element > 0 }
        guard rect.width > 0, rect.height > 0 else { return [] }
        func divide(_ items: [(offset: Int, element: Double)], _ box: CGRect) -> [Tile] {
            guard !items.isEmpty else { return [] }
            if items.count == 1 { return [Tile(id: items[0].offset, rect: box)] }
            let sum = items.reduce(0) { $0 + $1.element }
            var prefix = 0.0
            var split = 1
            var best = Double.infinity
            for index in 1..<items.count {
                prefix += items[index - 1].element
                if abs(sum / 2 - prefix) < best {
                    best = abs(sum / 2 - prefix); split = index
                }
            }
            let fraction = items.prefix(split).reduce(0) { $0 + $1.element } / sum
            let horizontal = box.width >= box.height
            let length = (horizontal ? box.width : box.height) * fraction
            let first = CGRect(x: box.minX, y: box.minY,
                               width: horizontal ? length : box.width,
                               height: horizontal ? box.height : length)
            let second = CGRect(x: horizontal ? box.minX + length : box.minX,
                                y: horizontal ? box.minY : box.minY + length,
                                width: horizontal ? box.width - length : box.width,
                                height: horizontal ? box.height : box.height - length)
            return divide(Array(items.prefix(split)), first) + divide(Array(items.dropFirst(split)), second)
        }
        return divide(entries, rect)
    }
}
