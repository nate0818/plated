/// Presentation state for a comment thread. Long branches start behind a
/// disclosure; an explicit choice lasts for this visit. New replies and direct
/// destinations reveal only their ancestor path, never unrelated conversations.
struct CommentReplyVisibility {
    struct Comment: Equatable {
        let id: String
        let parentID: String?
        let isDeleted: Bool

        init(id: String, parentID: String?, isDeleted: Bool = false) {
            self.id = id
            self.parentID = parentID
            self.isDeleted = isDeleted
        }
    }

    struct Row: Equatable {
        let id: String
        let depth: Int
    }

    struct Layout {
        let rows: [Row]
        let liveDescendantCounts: [String: Int]
    }

    private var expandedBranches: Set<String> = []
    private var collapsedBranches: Set<String> = []
    private var observedIDs: Set<String>?
    private var observedPendingIDs: Set<String> = []
    private var revealedComments: Set<String> = []

    func isCollapsed(_ id: String, descendantCount: Int) -> Bool {
        guard descendantCount > 0 else { return false }
        return collapsedBranches.contains(id)
            || (descendantCount > 2 && !expandedBranches.contains(id))
    }

    /// Deleted leaves do not contribute to the disclosure count or keep a
    /// branch on screen. A deleted ancestor remains only when it connects a
    /// live reply to its conversation. Orphans and cycles remain reachable.
    func layout(_ comments: [Comment]) -> Layout {
        var seen: Set<String> = []
        let ordered = comments.filter { seen.insert($0.id).inserted }
        var children: [String: [Comment]] = [:]
        for comment in ordered {
            if let parent = comment.parentID { children[parent, default: []].append(comment) }
        }
        var counts: [String: Int] = [:]
        for comment in ordered {
            var visited: Set<String> = [comment.id]
            var remaining = children[comment.id] ?? []
            var count = 0
            while let child = remaining.popLast() {
                guard visited.insert(child.id).inserted else { continue }
                if !child.isDeleted { count += 1 }
                remaining.append(contentsOf: children[child.id] ?? [])
            }
            counts[comment.id] = count
        }

        let retained = Set(ordered.filter { !$0.isDeleted || counts[$0.id, default: 0] > 0 }.map(\.id))
        var visited: Set<String> = []
        var rows: [Row] = []
        func append(_ comment: Comment, depth: Int) {
            guard retained.contains(comment.id), visited.insert(comment.id).inserted else { return }
            rows.append(.init(id: comment.id, depth: depth))
            if isCollapsed(comment.id, descendantCount: counts[comment.id, default: 0]) {
                // Hidden descendants are visited so the orphan/cycle fallback
                // cannot accidentally append them as top-level comments.
                var remaining = children[comment.id] ?? []
                while let child = remaining.popLast() {
                    guard visited.insert(child.id).inserted else { continue }
                    remaining.append(contentsOf: children[child.id] ?? [])
                }
            } else {
                for child in children[comment.id] ?? [] { append(child, depth: depth + 1) }
            }
        }
        for comment in ordered where comment.parentID == nil || !retained.contains(comment.parentID ?? "") {
            append(comment, depth: 0)
        }
        for comment in ordered where !visited.contains(comment.id) { append(comment, depth: 0) }
        return .init(rows: rows, liveDescendantCounts: counts)
    }

    mutating func observe(_ comments: [Comment], pendingIDs: Set<String> = []) {
        let ids = Set(comments.map(\.id))
        let liveIDs = Set(comments.filter { !$0.isDeleted }.map(\.id))
        var toReveal = pendingIDs.subtracting(observedPendingIDs).intersection(liveIDs)
        if let observedIDs { toReveal.formUnion(liveIDs.subtracting(observedIDs)) }
        // An empty initial query is not a loaded thread. Its first received
        // snapshot must still use the collapsed default, rather than treating
        // the entire historical conversation as newly arrived replies.
        if !ids.isEmpty || observedIDs != nil { observedIDs = ids }
        observedPendingIDs = pendingIDs
        reveal(toReveal, in: comments)
        // A child may sync before its parent. Keep the destination visible when
        // that parent arrives later and creates a newly collapsible branch.
        reveal(revealedComments, in: comments)
    }

    mutating func reveal(_ ids: Set<String>, in comments: [Comment]) {
        revealedComments.formUnion(ids)
        let parents = parentMap(comments)
        for id in ids {
            let ancestors = ancestorIDs(of: id, parents: parents)
            expandedBranches.formUnion(ancestors)
            collapsedBranches.subtract(ancestors)
        }
    }

    mutating func toggle(_ id: String, descendantCount: Int, in comments: [Comment]) {
        guard descendantCount > 0 else { return }
        if isCollapsed(id, descendantCount: descendantCount) {
            collapsedBranches.remove(id)
            expandedBranches.insert(id)
        } else {
            expandedBranches.remove(id)
            collapsedBranches.insert(id)
            let parents = parentMap(comments)
            // Respect a deliberate Hide after a notification or a new reply.
            // A later unrelated update must not undo that explicit choice.
            revealedComments = revealedComments.filter {
                !ancestorIDs(of: $0, parents: parents).contains(id)
            }
        }
    }

    private func parentMap(_ comments: [Comment]) -> [String: String] {
        var parents: [String: String] = [:]
        for comment in comments {
            if let parent = comment.parentID, !parent.isEmpty, parents[comment.id] == nil {
                parents[comment.id] = parent
            }
        }
        return parents
    }

    private func ancestorIDs(of id: String, parents: [String: String]) -> Set<String> {
        var ancestors: Set<String> = []
        var visited: Set<String> = [id]
        var current = id
        while let parent = parents[current], visited.insert(parent).inserted {
            ancestors.insert(parent)
            current = parent
        }
        return ancestors
    }
}
