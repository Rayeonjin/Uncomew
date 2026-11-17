import Foundation
import CoreGraphics

@main struct SpaceMapTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        for weights in [[1.0], [8, 1, 1], Array(repeating: 1.0, count: 42),
                        [1_000_000, 1, 0, -1, .nan, .infinity, 2]] {
            for size in [CGSize(width: 800, height: 400), CGSize(width: 300, height: 700)] {
                let bounds = CGRect(origin: CGPoint(x: 10, y: 20), size: size)
                let tiles = SpaceMapLayout.tiles(weights: weights, in: bounds)
                let valid = weights.indices.filter { weights[$0].isFinite && weights[$0] > 0 }
                check(Set(tiles.map(\.id)) == Set(valid), "Every positive finite weight represented exactly")
                check(tiles.count == valid.count, "No duplicate tile")
                let total = valid.reduce(0) { $0 + weights[$1] }
                for tile in tiles {
                    let area = tile.rect.width * tile.rect.height
                    check(abs(area / (size.width * size.height) - weights[tile.id] / total) < 0.000001,
                          "Area faithfully represents relative size")
                    check(tile.rect.minX >= bounds.minX - 0.000001 &&
                          tile.rect.minY >= bounds.minY - 0.000001 &&
                          tile.rect.maxX <= bounds.maxX + 0.000001 &&
                          tile.rect.maxY <= bounds.maxY + 0.000001, "Tile stays in bounds")
                }
                for i in tiles.indices {
                    for j in tiles.indices where j > i {
                        let overlap = tiles[i].rect.intersection(tiles[j].rect)
                        check(overlap.isNull || overlap.width * overlap.height < 0.000001, "Tiles do not overlap")
                    }
                }
            }
        }
        check(SpaceMapLayout.tiles(weights: [], in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty, "Empty data")
        check(SpaceMapLayout.tiles(weights: [1], in: .zero).isEmpty, "Zero geometry")
        print("Passed \(checks) space map geometry checks.")
    }
}
