import Foundation

/// Retained tabs can stay mounted while hidden. Only rows actually visible
/// during an active visit count as viewed; opening the inbox alone reads nothing.
struct ActivityReadSession<ID: Hashable> {
    private(set) var visible: Set<ID> = []
    private(set) var viewed: Set<ID> = []
    var active = false

    mutating func visibility(_ id: ID, isVisible: Bool) {
        if isVisible { visible.insert(id) } else { visible.remove(id) }
        if isVisible && active { viewed.insert(id) }
    }

    mutating func enter() {
        active = true
        viewed.formUnion(visible)
    }

    mutating func leave() -> Set<ID> {
        active = false
        let result = viewed
        viewed.removeAll()
        return result
    }
}
