import Foundation

// Keep only the visible leading rows while scanning a large result dictionary.
// Sorting every discovered file on each SwiftUI update is unnecessarily expensive.
enum StorageRanking {
    static func tree(nodes: [String: StorageNode], roots: [String], expanded: Set<String>,
                     selected: String?, limit: Int, byName: Bool, includePackages: Bool) -> [(node: StorageNode, depth: Int)] {
        guard limit > 0 else { return [] }
        var required = Set<String>()
        var path = selected
        while let current = path, let node = nodes[current], required.insert(current).inserted {
            if roots.contains(current) { break }
            guard let parent = node.parent, expanded.contains(parent),
                  nodes[parent]?.type != .package || includePackages else { required.removeAll(); break }
            path = node.parent
        }
        var rows: [(node: StorageNode, depth: Int)] = []
        var seen = Set<String>()
        func append(_ paths: [String], depth: Int) {
            let siblings = paths.compactMap { nodes[$0] }.sorted {
                if byName {
                    let order = $0.name.localizedStandardCompare($1.name)
                    if order != .orderedSame { return order == .orderedAscending }
                } else if $0.allocatedBytes != $1.allocatedBytes {
                    return ($0.allocatedBytes ?? -1) > ($1.allocatedBytes ?? -1)
                }
                return $0.path < $1.path
            }
            for node in siblings {
                guard rows.count < limit else { return }
                // Reserve space for a jump target and its ancestors instead of rendering the entire disk.
                if !required.contains(node.path), rows.count >= limit - required.count { continue }
                guard seen.insert(node.path).inserted else { continue }
                rows.append((node, depth)); required.remove(node.path)
                if expanded.contains(node.path), node.type != .package || includePackages {
                    append(node.children, depth: depth + 1)
                }
            }
        }
        append(roots, depth: 0)
        return rows
    }

    static func top<S: Sequence>(_ nodes: S, limit: Int, byName: Bool = false,
                                 including: (StorageNode) -> Bool) -> [StorageNode] where S.Element == StorageNode {
        guard limit > 0 else { return [] }
        func before(_ lhs: StorageNode, _ rhs: StorageNode) -> Bool {
            if byName {
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.path < rhs.path : order == .orderedAscending
            }
            if lhs.allocatedBytes != rhs.allocatedBytes {
                return (lhs.allocatedBytes ?? -1) > (rhs.allocatedBytes ?? -1)
            }
            return lhs.path < rhs.path
        }
        func worse(_ lhs: StorageNode, _ rhs: StorageNode) -> Bool { before(rhs, lhs) }
        var heap: [StorageNode] = []
        heap.reserveCapacity(min(limit, 1_000))
        for node in nodes where including(node) {
            if heap.count < limit {
                heap.append(node)
                var child = heap.count - 1
                while child > 0 {
                    let parent = (child - 1) / 2
                    if !worse(heap[child], heap[parent]) { break }
                    heap.swapAt(child, parent)
                    child = parent
                }
            } else if before(node, heap[0]) {
                heap[0] = node
                var parent = 0
                while true {
                    let left = parent * 2 + 1
                    if left >= heap.count { break }
                    let right = left + 1
                    let child = right < heap.count && worse(heap[right], heap[left]) ? right : left
                    if !worse(heap[child], heap[parent]) { break }
                    heap.swapAt(child, parent)
                    parent = child
                }
            }
        }
        return heap.sorted(by: before)
    }
}
