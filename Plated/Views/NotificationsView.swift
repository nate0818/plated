import SwiftUI
import SwiftData

/// The activity feed — who plated, who commented, whose turn it is. Opened
/// from the bell on the plan; entries mark themselves read on the way out.
struct NotificationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlatedNotification.createdAt, order: .reverse)
    private var notifications: [PlatedNotification]

    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedNote: PersistentIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    dismiss()
                } label: {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "chevron.left")
                                .accessibilityLabel("Back")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("What happened")
                    Text("Activity")
                        .font(.gabarito(25, .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
                if notifications.contains(where: { !$0.isRead }) == false && !notifications.isEmpty {
                    EmptyView()
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .padding(.bottom, 12)
            Divider().overlay(Color.hairlineSoft)

            if notifications.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bell")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                    Text("All quiet at the table")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Plates, comments, saves, and turn reminders land here.")
                        .font(.jakarta(13, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(notifications, id: \.persistentModelID) { note in
                            row(note)
                            Divider().overlay(Color.hairlineSoft)
                        }
                    }
                    .padding(.bottom, Layout.floatingChromeInset)
                }
            }
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .onDisappear {
            // Leaving the feed reads it — same contract as every inbox.
            for note in notifications where !note.isRead {
                note.isRead = true
            }
        }
    }

    private func row(_ note: PlatedNotification) -> some View {
        // Clearing an inbox entry is not deleting the thing it describes —
        // the plate, the comment, the save all still happened — so it wears
        // an xmark rather than the trash SwipeAction.remove hands out.
        SwipeRow(isOpen: swipeBinding(note), actions: [.clear { clear(note) }]) {
            noteRow(note)
        }
    }

    private func swipeBinding(_ note: PlatedNotification) -> Binding<Bool> {
        Binding(
            get: { swipedNote == note.persistentModelID },
            set: { open in
                swipedNote = open
                    ? note.persistentModelID
                    : (swipedNote == note.persistentModelID ? nil : swipedNote)
            }
        )
    }

    private func clear(_ note: PlatedNotification) {
        withAnimation(.plSnap) {
            swipedNote = nil
            context.delete(note)
        }
    }

    private func noteRow(_ note: PlatedNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.fill)
                    .frame(width: 40, height: 40)
                Image(systemName: note.kindValue.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(note.isRead ? Color.inkSecondary : Color.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(note.body)
                    .font(.jakarta(14, note.isRead ? .medium : .semibold))
                    .foregroundStyle(Color.ink)
                    .lineSpacing(2)
                Text(relativeWhen(note.createdAt))
                    .font(.jakarta(11, .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            // Quiet unread: weight and an ink dot — the tomato budget is
            // spent on the bell badge.
            if !note.isRead {
                Circle().fill(Color.ink).frame(width: 6, height: 6)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
    }

    private func relativeWhen(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }
}
