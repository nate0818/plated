import SwiftUI
import SwiftData

/// The activity feed — who plated, who commented, whose turn it is. Opened
/// from the bell on the plan; entries mark themselves read on the way out.
struct NotificationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlatedNotification.createdAt, order: .reverse)
    private var notifications: [PlatedNotification]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedNote: PersistentIdentifier?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconDiscButton(systemName: "chevron.left", label: "Back") {
                    dismiss()
                }
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("Recent")
                    Text("Activity")
                        .plType(.display)
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
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                    Text("Nothing yet")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text("What people plate, say and vote on lands here, and your cook reminders.")
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
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
        .onAppear {
            // Two devices, one event: keep one row. See TableNews.
            TableNews.dedupeRows(context)
        }
        .onDisappear {
            // Leaving the feed reads it — same contract as every inbox.
            for note in notifications where !note.isRead {
                note.isRead = true
            }
            Persist.save(context, "activity read")
            AppBadge.sync(context)
            // Read here is read on the lock screen too.
            Task { await TableNews.reconcileDelivered(context: context) }
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

    /// A row that knows where it came from opens it; a row that does not
    /// stays a line of text rather than pretending to be a button.
    @ViewBuilder
    private func noteRow(_ note: PlatedNotification) -> some View {
        if let url = note.linkURL {
            Button {
                Haptic.tap()
                note.isRead = true
                LinkRelay.open(url)
            } label: {
                noteLine(note)
            }
            .buttonStyle(.pressable)
            .accessibilityHint(hint(for: url))
        } else {
            noteLine(note)
        }
    }

    /// Where the row goes, in words, because "Opens it" names nothing.
    private func hint(for url: URL) -> String {
        switch DeepLink.destination(for: url) {
        case .post: return "Opens the dish"
        case .home: return "Opens Home"
        case .plan, .grocery: return "Opens the plan"
        default: return "Opens the Table"
        }
    }

    /// A row about a person shows the person. The icon is for rows about
    /// things: a reminder, the grocery list, the cookbook.
    @ViewBuilder
    private func face(for note: PlatedNotification) -> some View {
        if !note.actorName.isEmpty, note.kindValue.isAboutSomebody {
            if let member = members.first(where: { $0.name == note.actorName }) {
                AvatarCircle(member: member, size: 40)
            } else {
                AvatarCircle(
                    initials: initials(of: note.actorName),
                    tone: PersonTone.from(hex: "7F7364"),  // design-ok(literal-colour): the neutral tone of a person this household has no seat for
                    size: 40
                )
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.fill)
                    .frame(width: 40, height: 40)
                Image(systemName: note.kindValue.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(note.isRead ? Color.inkSecondary : Color.ink)
            }
        }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2)
        let joined = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    private func noteLine(_ note: PlatedNotification) -> some View {
        HStack(alignment: .top, spacing: 12) {
            face(for: note)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.body)
                    .plType(.body, note.isRead ? TypeWeight.medium : .semibold)
                    .foregroundStyle(Color.ink)
                Text(when(note.createdAt))
                    .plType(.micro, .medium)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            // Quiet unread: weight and an ink dot — the tomato budget is
            // spent on the bell badge.
            if !note.isRead {
                Circle().fill(Color.ink).frame(width: 6, height: 6)
                    .padding(.top, 7)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // The dot is paint; the state has to be audible too.
        .accessibilityValue(note.isRead ? "" : "Unread")
    }

    /// The Table's ladder, so "Thursday" here means what it means there.
    /// Within the day it keeps the hour, because the bell is read in the
    /// evening about the afternoon.
    private func when(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            let minutes = Int(Date.now.timeIntervalSince(date) / 60)
            if minutes < 1 { return "Just now" }
            if minutes < 60 { return "\(minutes) min ago" }
            return date.formatted(date: .omitted, time: .shortened)
        }
        return Stamp.day(date)
    }
}
