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
    var homeTab: AppTab = .week
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.activeAppTab) private var activeAppTab
    @Query(sort: \PlatedNotification.createdAt, order: .reverse)
    private var notifications: [PlatedNotification]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var comments: [TableComment]
    @State private var contentSafety = ContentSafety.shared

    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedNote: PersistentIdentifier?
    @State private var clearAllAsked = false
    @State private var readSession = ActivityReadSession<PersistentIdentifier>()
    /// The dish photographs, by post record, loaded once per visit rather
    /// than fetched on every body pass.
    @State private var thumbnails: [String: Data] = [:]
    @State private var phoneAlertsNeedSetup = false
    @State private var showingAlertSettings = false

    private var visibleNotifications: [PlatedNotification] {
        notifications.filter { !contentSafety.hidesTableActivity($0) }
    }

    private var unreadCount: Int { visibleNotifications.lazy.filter { !$0.isRead }.count }

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
        let unread = visibleNotifications.filter { !$0.isRead }
        let read = visibleNotifications.filter(\.isRead)
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
                    Text("Activity")
                        .plType(.pageTitle)
                        .foregroundStyle(Color.ink)
                }
                Spacer()
                if !visibleNotifications.isEmpty {
                    Menu {
                        Button("Mark all read", systemImage: "checkmark") { markAllRead() }
                            .disabled(unreadCount == 0)
                        Button("Clear all activity", systemImage: "trash", role: .destructive) { clearAllAsked = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Color.ink)
                            .plTapTarget()
                    }
                    .accessibilityLabel("Activity options")
                }
            }
            .padding(.horizontal, Spacing.page)
            .padding(.top, 6)
            .padding(.bottom, 12)
            HStack {
                Text(unreadCount == 0 ? "You’re up to date" : "\(unreadCount) unread")
                    .plType(.caption).foregroundStyle(Color.inkSecondary)
                Spacer()
                if unreadCount > 0 {
                    Button("Mark all read", action: markAllRead)
                        .plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                        .frame(minHeight: 44).buttonStyle(.pressable)
                        .accessibilityIdentifier("activity-mark-all-read")
                }
            }.padding(.horizontal, Spacing.page)
            Divider().overlay(Color.hairlineSoft)

            if phoneAlertsNeedSetup {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Get Table notifications")
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.ink)
                        Text("Replies and invitation updates, even when Plated is closed.")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Button("Settings") { showingAlertSettings = true }
                        .plType(.footnote, .bold)
                        .foregroundStyle(Color.accentText)
                        .frame(minHeight: 44)
                }
                .padding(14)
                .background(Color.fill, in: Radius.shape(Radius.card))
                .padding(.horizontal, Spacing.page)
                .padding(.vertical, 12)
            }

            if visibleNotifications.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "bell")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                    Text("All quiet at the Table")
                        .plType(.body, .bold)
                        .foregroundStyle(Color.ink)
                    Text("New likes, replies, votes, and cook reminders will collect here.")
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
                            if group.title != "New" {
                                MicroLabel(group.title).padding(.horizontal, Spacing.page)
                                    .padding(.top, 18).padding(.bottom, 6).accessibilityAddTraits(.isHeader)
                            }
                            ForEach(group.rows, id: \.persistentModelID) { note in
                                row(note)
                                    .onScrollVisibilityChange(threshold: 0.5) { visible in
                                        readSession.visibility(note.persistentModelID, isVisible: visible)
                                    }
                                Divider().overlay(Color.hairlineSoft)
                            }
                        }
                    }
                    .padding(.bottom, Layout.focusedPageBottom)
                }
            }
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .plSwipeBack()
        .hidesFloatingChrome()
        .sheet(isPresented: $showingAlertSettings) { SettingsSheet() }
        .task { await refreshPhoneAlertStatus() }
        .onChange(of: showingAlertSettings) { _, showing in
            if !showing { Task { await refreshPhoneAlertStatus() } }
        }
        .confirmationDialog(
            "Clear all activity?", isPresented: $clearAllAsked, titleVisibility: .visible
        ) {
            Button("Clear all", role: .destructive) { clearAll() }
            Button("Keep activity", role: .cancel) {}
        } message: {
            Text("The list empties. Nothing at the Table changes.")
        }
        .onAppear {
            // Two devices, one event: keep one row. See TableNews.
            TableNews.dedupeRows(context)
            // Every row a banner would repeat is already on this screen.
            Presence.shared.activityVisible = activeAppTab == homeTab
            if activeAppTab == homeTab { readSession.enter() }
            loadThumbnails()
        }
        .onChange(of: activeAppTab) { _, tab in
            if tab == homeTab {
                Presence.shared.activityVisible = true
                readSession.enter()
            } else {
                finishReading()
            }
        }
        .onChange(of: notifications.count) { _, _ in loadThumbnails() }
        .onDisappear { finishReading() }
    }

    private func refreshPhoneAlertStatus() async {
        let permission = await NotificationScheduler.authorizationState()
        phoneAlertsNeedSetup = permission == .allowed && NewsPreferences.tableOn
            && !SocialPush.hasConfirmedInstallation
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
        Persist.save(context, "activity item cleared")
        AppBadge.sync(context)
        Task { await TableNews.reconcileDelivered(context: context) }
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
                    markRead(note)
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
        case .post: return "Opens the post"
        case .home: return "Opens the household"
        case .plan, .grocery: return "Opens the plan"
        case .cookbook: return "Opens the cookbook"
        case .cook: return "Resumes cooking"
        default: return "Opens the Table"
        }
    }

    private func markAllRead() {
        for note in visibleNotifications where !note.isRead { note.isRead = true }
        Persist.save(context, "all activity read")
        AppBadge.sync(context)
        Task { await TableNews.reconcileDelivered(context: context) }
    }

    private func markRead(_ note: PlatedNotification) {
        guard !note.isRead else { return }
        note.isRead = true
        Persist.save(context, "activity item read")
        AppBadge.sync(context)
        Task { await TableNews.reconcileDelivered(context: context) }
    }

    /// MainShell retains inactive tabs at zero opacity, so selecting another
    /// tray item does not guarantee `onDisappear`. Treat that tab transition
    /// as leaving the inbox too; the operation is idempotent for a later pop.
    private func finishReading() {
        Presence.shared.activityVisible = false
        let viewedIDs = readSession.leave()
        let viewed = visibleNotifications.filter { !$0.isRead && viewedIDs.contains($0.persistentModelID) }
        guard !viewed.isEmpty else { return }
        for note in viewed { note.isRead = true }
        Persist.save(context, "viewed activity read")
        AppBadge.sync(context)
        // Read here is read on the lock screen too.
        Task { await TableNews.reconcileDelivered(context: context) }
    }

    /// A row about a person shows the person. The icon is for rows about
    /// things: a reminder, the grocery list, the cookbook.
    @ViewBuilder
    private func face(for note: PlatedNotification) -> some View {
        if !note.actorName.isEmpty, note.kindValue.isAboutSomebody {
            if let member = member(for: note) {
                AvatarCircle(member: member, size: 36)
            } else {
                // A guest at a table this household joined has no seat row
                // here, so no colour has been earned: the neutral pair.
                AvatarCircle(initials: initials(of: note.actorName), tone: .neutralPair, size: 36)
            }
        } else {
            ZStack {
                Circle()
                    .fill(Color.fill)
                    .frame(width: 36, height: 36)
                Image(systemName: note.kindValue.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(note.isRead ? Color.inkSecondary : Color.ink)
            }
        }
    }

    /// Identity first (`userRecordName` or `participantID`), then the
    /// stored name. Same rule as `PlatedNotification.line`. Matching only
    /// on participant left join notices wearing the host's face: the
    /// joiner's id lives on `userRecordName` until the share corroborates.
    private func member(for note: PlatedNotification) -> HouseholdMember? {
        members.actor(id: note.actorID, name: note.actorName)
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
        for note in visibleNotifications {
            guard let url = note.linkURL, let record = DeepLink.postID(in: url),
                  found[record] == nil else { continue }
            if let photo = thumbnails[record] ?? TableNews.find(record, in: context)?.photoData {
                found[record] = photo
            }
        }
        thumbnails = found
    }

    private func excerpt(for note: PlatedNotification) -> String? {
        guard note.kindValue == .commentAdded || note.kindValue == .commentReaction else { return nil }
        let id = note.linkURL.flatMap(DeepLink.commentID(in:))
            ?? (note.eventKey.hasPrefix("note:") ? String(note.eventKey.dropFirst(5)) : nil)
        guard let id, let comment = comments.first(where: { $0.shareRecordName == id }),
              comment.deletedAt == nil,
              !contentSafety.isBlocked(authorID: comment.authorID, authorName: comment.authorName) else { return nil }
        if !comment.text.isEmpty { return String(comment.text.prefix(160)) }
        if comment.photoData != nil { return "Sent a photo" }
        return nil
    }

    private func noteLine(_ note: PlatedNotification) -> some View {
        HStack(alignment: .center, spacing: 10) {
            face(for: note)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                activityLine(note)
                    .plType(.footnote)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let excerpt = excerpt(for: note) {
                    Text(excerpt).plType(.footnote).foregroundStyle(Color.inkSecondary).lineLimit(2)
                }
                Text([note.objectTitle, when(note.createdAt)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .plType(.detail)
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer(minLength: 8)
            if let photo = thumbnail(for: note) {
                RecipeArtwork(data: photo, title: note.objectTitle, ratio: 1, radius: Radius.small)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 17)
        .overlay(alignment: .leading) {
            if !note.isRead {
                Circle().fill(Color.olive).frame(width: 5, height: 5)
                    .offset(x: -12).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, Spacing.page)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        // The dot is paint; the state has to be audible too.
        .accessibilityValue(note.isRead ? "" : "Unread")
    }

    /// Emphasize the actor, rather than making the entire event a bold sentence.
    private func activityLine(_ note: PlatedNotification) -> Text {
        let line = note.line(members: members)
        let actor = member(for: note)?.firstName ?? note.actorName.split(separator: " ").first.map(String.init) ?? ""
        guard !actor.isEmpty, line.hasPrefix(actor) else { return Text(line) }
        return Text(actor).fontWeight(.semibold) + Text(String(line.dropFirst(actor.count)))
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
