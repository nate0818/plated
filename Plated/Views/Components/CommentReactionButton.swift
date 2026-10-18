import SwiftUI
import SwiftData

/// A comment has its own reaction target, even when it is a nested reply.
struct CommentReactionButton: View {
    let comment: TableComment
    @Environment(\.modelContext) private var context
    @AppStorage("userFirstName") private var authorName = ""

    private var pending: Bool {
        TableOutbox.shared.pending.contains { $0.id == "plate:\(comment.shareRecordName)" }
    }

    var body: some View {
        Button {
            Haptic.select()
            withAnimation(.plSnap) {
                TableReactions.toggleLike(comment, context: context, authorName: authorName)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: comment.likedByMeNow ? "heart.fill" : "heart")
                if comment.totalLikes > 0 {
                    Text(comment.totalLikes.formatted())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                if pending {
                    Image(systemName: "clock")
                }
            }
            .plType(.footnote, .medium)
            .foregroundStyle(comment.likedByMeNow ? Color.accentText : Color.inkSecondary)
            .plTapTarget()
        }
        .buttonStyle(.pressable)
        .disabled(comment.deletedAt != nil)
        .accessibilityLabel(comment.likedByMeNow
                            ? "Unlike \(comment.authorName)'s comment"
                            : "Like \(comment.authorName)'s comment")
        .accessibilityValue(comment.totalLikes.things("like") + (pending ? ", waiting to sync" : ""))
        .accessibilityHint(comment.text.isEmpty ? "" : String(comment.text.prefix(160)))
        .accessibilityAddTraits(comment.likedByMeNow ? .isSelected : [])
        .accessibilityIdentifier("comment-like-\(comment.shareRecordName)")
    }
}
