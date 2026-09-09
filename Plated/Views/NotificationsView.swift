import SwiftUI
import SwiftData

/// The activity feed: who plated, who commented, whose turn it is. Opened
/// from the bell; entries mark themselves read on the way out.
///
/// Read top to bottom the way Instagram's tab is, and with its row anatomy
/// (the person, the sentence, the dish), minus everything that exists to
/// manage scale. What is new sits first, then what is read, by how long
/// ago. The sentence is composed when it is drawn, so a person who renames
/// themselves is called the new thing in last week's rows too.
struct NotificationsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PlatedNotification.createdAt, order: .reverse)
    private var notifications: [PlatedNotification]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedNote: PersistentIdentifier?
    @State private var clearAllAsked = false
    /// The dish photographs, by post record, loaded once per visit rather
    /// than fetched on every body pass.
    @State private var thumbnails: [String: Data] = [:]

    /// The list in the order it is read. "New" is what is unread; the rest
    /// is read, on the Table's own ladder of days.
    private struct Group: Identifiable {
        let title: String
        let rows: [PlatedNotification]
        var id: String { title }
    }

    private var groups: [Group] {
        let calendar = Calendar.current
        let weekAgo = Date.now.addingTimeInterval(-6 * 24 * 3600)
        let unread = notifications.filter { !$0.isRead }
        let read = notifications.filter(\.isRead)
        var out: [Group] = []
        if !unread.isEmpty { out.append(Group(title: "New", rows: unread)) }
        let today = read.filter { calendar.isDateInToday($0.createdAt) }
        let week = read.filter { !calendar.isDateInToday($0.createdAt) && $0.createdAt > weekAgo }
        let earlier = read.filter { $0.createdAt <= weekAgo }
        if !today.isEmpty { out.append(Group(title: "Today", rows: today)) }
        if !week.isEmpty { out.append(Group(title: "This week", rows: week)) }
        if !earlier.isEmpty { out.append(Group(title: "Earlier", rows: earlier)) }
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                IconDiscButton(systemName: "arrow.left", label: "Back") {
                    dismiss()
                }
                VStack(alignment: .leading, spacing: 2) {
                    MicroLabel("Recent")
                    Text("Activity")
                        .plType(.display)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
                // One tap empties the list; the plates and comments it
                // described still happened, so this is clearing an inbox,
                // not deleting anything. Asked once because there is no
                // way back.
                if !notifications.isEmpty {
                    Button("Clear all") {
                        Haptic.tap()
                        clearAllAsked = true
                    }
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .plTapTarget()
                    .accessibilityHint("Empties the activity list")
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
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(groups) { group in
                            MicroLabel(group.title)
                                .padding(.horizontal, 24)
                                .padding(.top, 18)
                                .padding(.bottom, 6)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.rows, id: \.persistentModelID) { note in
                                row(note)
                                Divider().overlay(Color.hairlineSoft)
                            }
                        }
                    }
                    .padding(.bottom, Layout.floatingChromeInset)
                }
            }
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .confirmationDialog(
            "Clear all activity?", isPresented: $clearAllAsked, titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { clearAll() }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("The list empties. Nothing at the Table changes.")
        }
        .onAppear {
            // Two devices, one event: keep one row. See TableNews.
            TableNews.dedupeRows(context)
            // Every row a banner would repeat is already on this screen.
            Presence.shared.activityVisible = true
            loadThumbnails()
        }
        .onChange(of: notifications.count) { _, _ in loadThumbnails() }
        .onDisappear {
            Presence.shared.activityVisible = false
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

    private func clearAll() {
        withAnimation(.plSnap) {
            swipedNote = nil
            for note in notifications { context.delete(note) }
        }
        Persist.save(context, "activity cleared")
        AppBadge.sync(context)
        Task { await TableNews.reconcileDelivered(context: context) }
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
            // A gesture, not a Button: a Button inside SwipeRow fires on
            // the swipe that was meant to reveal Clear, and the row opened
            // the dish instead. The plan's rows learned this first.
            noteLine(note)
                .onTapGesture {
                    Haptic.tap()
                    note.isRead = true
                    LinkRelay.open(url)
                }
                .accessibilityAddTraits(.isButton)
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
        case .cookbook: return "Opens the cookbook"
        default: return "Opens the Table"
        }
    }

    /// A row about a person shows the person. The icon is for rows about
    /// things: a reminder, the grocery list, the cookbook.
    @ViewBuilder
    private func face(for note: PlatedNotification) -> some View {
        if !note.actorName.isEmpty, note.kindValue.isAboutSomebody {
            if let member = member(for: note) {
                AvatarCircle(member: member, size: 40)
            } else {
                // A guest at a table this household joined has no seat row
                // here, so no colour has been earned: the neutral pair.
                AvatarCircle(initials: initials(of: note.actorName), tone: .neutralPair, size: 40)
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

    /// Identity first, the stored name only for a seat with no identity
    /// yet. Same rule as `PlatedNotification.line`.
    private func member(for note: PlatedNotification) -> HouseholdMember? {
        if !note.actorID.isEmpty, let byID = members.first(where: { $0.participantID == note.actorID }) {
            return byID
        }
        return members.first { $0.participantID == nil && $0.name == note.actorName }
    }

    private func initials(of name: String) -> String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }.prefix(2)
        let joined = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return joined.isEmpty ? "?" : joined
    }

    /// The dish on the right, when the row is about one and it has a
    /// photograph. No placeholder tile: a monogram beside a face would be
    /// two circles saying nothing.
    private func thumbnail(for note: PlatedNotification) -> Data? {
        guard let url = note.linkURL, let record = DeepLink.postID(in: url) else { return nil }
        return thumbnails[record]
    }

    private func loadThumbnails() {
        var found: [String: Data] = [:]
        for note in notifications {
            guard let url = note.linkURL, let record = DeepLink.postID(in: url),
                  found[record] == nil else { continue }
            if let photo = thumbnails[record] ?? TableNews.find(record, in: context)?.photoData {
                found[record] = photo
            }
        }
        thumbnails = found
    }

    private func noteLine(_ note: PlatedNotification) -> some View {
        HStack(alignment: .center, spacing: 12) {
            face(for: note)
            VStack(alignment: .leading, spacing: 3) {
                Text(note.line(members: members))
                    .plType(.body, note.isRead ? TypeWeight.medium : .semibold)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(when(note.createdAt))
                    .plType(.micro, .medium)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
            if let photo = thumbnail(for: note) {
                RecipeArtwork(data: photo, title: note.objectTitle, ratio: 1, radius: Radius.small)
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            // Quiet unread: weight and an ink dot — the tomato budget is
            // spent on the bell badge.
            if !note.isRead {
                Circle().fill(Color.ink).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
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
