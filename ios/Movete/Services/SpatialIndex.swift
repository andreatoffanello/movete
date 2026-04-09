import Foundation
import CoreLocation

/// Grid-based spatial index for fast viewport queries on thousands of stops.
/// Divides the coordinate space into cells; queries only check cells that overlap the viewport.
/// O(1) cell lookup, no tree rebalancing, perfect for static data.
final class SpatialIndex<T>: @unchecked Sendable {
    struct Item {
        let value: T
        let lat: Double
        let lng: Double
    }

    private var grid: [Int: [Item]] = [:]
    private let cellSize: Double  // degrees per cell
    private let lngCells: Int

    /// cellSize ~0.005 degrees ≈ 500m — good for city-scale transit
    init(cellSize: Double = 0.005) {
        self.cellSize = cellSize
        self.lngCells = Int(ceil(360.0 / cellSize))
    }

    func insert(_ value: T, lat: Double, lng: Double) {
        let key = cellKey(lat: lat, lng: lng)
        grid[key, default: []].append(Item(value: value, lat: lat, lng: lng))
    }

    func buildFromItems(_ items: [(T, Double, Double)]) {
        grid.removeAll(keepingCapacity: true)
        grid.reserveCapacity(items.count / 4)
        for (value, lat, lng) in items {
            let key = cellKey(lat: lat, lng: lng)
            grid[key, default: []].append(Item(value: value, lat: lat, lng: lng))
        }
    }

    /// Query all items within a lat/lng bounding box
    func query(minLat: Double, maxLat: Double, minLng: Double, maxLng: Double) -> [T] {
        let minRow = Int(floor((minLat + 90) / cellSize))
        let maxRow = Int(floor((maxLat + 90) / cellSize))
        let minCol = Int(floor((minLng + 180) / cellSize))
        let maxCol = Int(floor((maxLng + 180) / cellSize))

        var result: [T] = []
        for row in minRow...maxRow {
            for col in minCol...maxCol {
                let key = row * lngCells + col
                guard let cell = grid[key] else { continue }
                for item in cell {
                    if item.lat >= minLat && item.lat <= maxLat &&
                       item.lng >= minLng && item.lng <= maxLng {
                        result.append(item.value)
                    }
                }
            }
        }
        return result
    }

    /// Query with a limit (returns first N found, good for nearby)
    func nearest(to lat: Double, lng: Double, radiusDeg: Double, limit: Int) -> [(T, Double)] {
        let results = query(
            minLat: lat - radiusDeg, maxLat: lat + radiusDeg,
            minLng: lng - radiusDeg, maxLng: lng + radiusDeg
        )
        // This is a rough filter; for exact distance, caller should use CLLocation
        return results.prefix(limit * 3).map { ($0, 0) } // distance computed by caller
    }

    private func cellKey(lat: Double, lng: Double) -> Int {
        let row = Int(floor((lat + 90) / cellSize))
        let col = Int(floor((lng + 180) / cellSize))
        return row * lngCells + col
    }
}
