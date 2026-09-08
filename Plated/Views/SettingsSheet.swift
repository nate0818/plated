import SwiftUI
import SwiftData

/// The personal control center for Plated. Controls are grouped by the job
/// they affect and always show their real state; permission failures lead to
/// the place that can resolve them instead of leaving a disabled switch.
struct SettingsSheet: View {
    var focusHouseholdName = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @AppStorage("householdName") private var householdName = ""
    @AppStorage("didSignIn") private var didSignIn = false
    @AppStorage("remindersOn") private var remindersOn = true
    /// What the Table may say when somebody else plates, writes, plans a
    /// night or takes a seat. `TableNews.tableOnKey` reads the same key.
    @AppStorage("tableNewsOn") private var tableNewsOn = true
    /// The finer switches, one per category, read from NewsPreferences on
    /// first draw.
    @State private var categoryStates: [NewsPreferences.Category: Bool] = [:]
    /// Which table this phone's week is shared with, in the three states
    /// `PlanShare` can answer. Re-read with the rest of the status.
    @State private var planHousehold: PlanShare.Household = .unknown

    @State private var notificationState: NotificationScheduler.AuthorizationState = .notDetermined
    @State private var calendarRefused = false
    @State private var signOutAsked = false
    @State private var tourShown = false
    @State private var editProfileShown = false
    @State private var sync = SyncStatus.shared
    @FocusState private var namingHousehold: Bool
    /// Where this phone stands in the household (docs/household.md §8,
    /// §10). The app-group cache is not observed and Settings is a sheet,
    /// so it is read when the sheet opens and again after Leave.
    @State private var membership = HouseholdShare.membership
    @State private var leaveAsked = false
    @State private var leaving = false
    /// "Couldn't leave." Said under the Leave row, the same way Home says a
    /// refused Remove.
    @State private var leaveProblem: String?

    /// The person holding the phone, not the head of table: on a member's
    /// phone the two are different people and Settings is about you.
    private var me: HouseholdMember? { members.me }
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }
    private var displayName: String {
        guard let name = me?.name, !HouseholdIdentity.isPlaceholder(name) else {
            return "Complete your profile"
        }
        return name
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 7) {
                    MicroLabel("Personalize Plated")
                    Text("Make Plated yours.")
                        .plType(.title, .semibold)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Control how Plated looks, plans, reminds and syncs.")
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                }
                .padding(.top, 10)

                identityCard

                SettingsSection(title: "Appearance", caption: "Choose how your kitchen looks.") {
                    appearanceChooser
                }

                SettingsSection(title: "Planning", caption: "Bring the week together without extra noise.") {
                    SettingsGroup {
                        planningReminderRow
                        SettingsDivider()
                        calendarRow
                    }
                }

                SettingsSection(title: "The Table", caption: "What other people do that reaches you.") {
                    SettingsGroup {
                        tableActivityRow
                        // The finer switches only while the coarse one is
                        // on and iOS would deliver: a row of switches under
                        // a refusal is furniture.
                        if notificationState == .allowed, tableNewsOn {
                            ForEach(NewsPreferences.Category.allCases, id: \.self) { category in
                                SettingsDivider()
                                categoryRow(category)
                            }
                        }
                    }
                }

                SettingsSection(title: "Household", caption: "The name everyone sees at home, and where your week goes.") {
                    // The host names the household; a member reads the name
                    // the host set and keeps the way out.
                    switch membership {
                    case .solo, .hosting: householdNameCard
                    case .member: memberHouseholdCard
                    }
                    SettingsGroup {
                        planShareRow
                    }
                }

                SettingsSection(title: "iCloud & privacy", caption: "Know where your information lives.") {
                    SettingsGroup {
                        syncRow
                        SettingsDivider()
                        Button {
                            Haptic.tap()
                            openSystemSettings()
                        } label: {
                            SettingsValueRow(
                                symbol: "hand.raised.fill",
                                title: "iOS permissions",
                                detail: "Calendar, contacts, photos and notifications",
                                tint: .grapeTint,
                                tone: .grape,
                                value: "Manage"
                            )
                        }
                        .buttonStyle(.pressable)
                        .accessibilityHint("Opens the Plated page in iOS Settings.")
                    }

                    privacyNote
                        .padding(.top, 10)
                }

                SettingsSection(title: "Help & account", caption: "Learn the app or manage your sign-in.") {
                    SettingsGroup {
                        Button {
                            Haptic.tap()
                            tourShown = true
                        } label: {
                            SettingsValueRow(
                                symbol: "sparkles",
                                title: "Show me around",
                                detail: "A one-minute tour of the four main spaces",
                                tint: .mangoTint,
                                tone: .amber,
                                value: "Begin"
                            )
                        }
                        .buttonStyle(.pressable)

                        SettingsDivider()

                        Button {
                            Haptic.tap()
                            signOutAsked = true
                        } label: {
                            SettingsValueRow(
                                symbol: "rectangle.portrait.and.arrow.right",
                                title: "Sign out",
                                detail: "Your recipes, plan and household stay saved",
                                tint: .tomatoTint,
                                tone: .tomato,
                                value: nil,
                                titleColor: .tomato
                            )
                        }
                        .buttonStyle(.pressable)
                    }
                }

                Text(Self.versionLine)
                    .plType(.micro, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 34)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .preferredColorScheme(appearance.scheme)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .task { await refreshStatus() }
        .onAppear {
            membership = HouseholdShare.membership
            if focusHouseholdName { namingHousehold = true }
        }
        // The name goes to the household on commit only: Done, or the field
        // losing focus, which includes the sheet closing over it.
        .onChange(of: namingHousehold) { _, focused in
            if !focused { commitHouseholdName() }
        }
        .onDisappear { commitHouseholdName() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refreshStatus() }
        }
        .fullScreenCover(isPresented: $tourShown) {
            TourView { tourShown = false }
        }
        .sheet(isPresented: $editProfileShown) {
            EditProfileSheet()
        }
        .confirmationDialog(
            "Sign out of Plated?",
            isPresented: $signOutAsked,
            titleVisibility: .visible
        ) {
            Button("Sign out", role: .destructive) { signOut() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("Nothing is deleted. Your recipes, your week and your household stay where they are.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Text("Settings")
                .plType(.heading, .semibold)
                .foregroundStyle(Color.ink)
            Spacer()
            Button("Done") { dismiss() }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.hairline))
                .contentShape(Capsule())
                .buttonStyle(.pressable)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
    }

    private var identityCard: some View {
        Button {
            Haptic.select()
            editProfileShown = true
        } label: {
            HStack(spacing: 14) {
                AvatarCircle(
                    initials: me?.initials ?? "Me",
                    tone: .neutralPair,
                    size: 54,
                    photo: me?.photoData
                )
                .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
                .shadow(color: Color.shadowInk.opacity(0.10), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName)
                        .plName()
                        .plType(.heading, .semibold)
                        .foregroundStyle(Color.ink)
                    Text("Photo, name and personal details")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
                Spacer(minLength: 8)
                Text("Edit")
                    .plType(.footnote, .bold)
                    .plActionLabel()
                    .foregroundStyle(Color.accentText)
                    .padding(.horizontal, 13)
                    .frame(minHeight: 34)
                    .background(Color.tomato.opacity(0.10), in: Capsule())
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.tomatoTint, Color.raisedFill],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Radius.shape(Radius.card)
            )
            .overlay(Radius.shape(Radius.card).strokeBorder(Color.tomato.opacity(0.12)))
            .contentShape(Radius.shape(Radius.card))
        }
        .buttonStyle(.pressable)
        .accessibilityIdentifier("settings-edit-profile")
    }

    private var appearanceChooser: some View {
        Group {
            if typeSize >= .accessibility1 {
                VStack(spacing: 10) {
                    ForEach(Appearance.allCases) { option in
                        appearanceOption(option, horizontal: true)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(Appearance.allCases) { option in
                        appearanceOption(option, horizontal: false)
                    }
                }
            }
        }
    }

    private func appearanceOption(_ option: Appearance, horizontal: Bool) -> some View {
        Button {
            Haptic.select()
            withAnimation(.plSnap) { appearanceRaw = option.rawValue }
        } label: {
            Group {
                if horizontal {
                    HStack(spacing: 13) {
                        appearancePreview(option)
                        Text(option.label)
                            .plType(.body, .semibold)
                            .plActionLabel()
                        Spacer()
                        selectionMark(option)
                    }
                } else {
                    VStack(spacing: 9) {
                        appearancePreview(option)
                        HStack(spacing: 5) {
                            Text(option.label)
                                .plType(.footnote, .semibold)
                                .plActionLabel()
                            selectionMark(option)
                        }
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .padding(horizontal ? 13 : 11)
            .frame(maxWidth: .infinity, minHeight: horizontal ? 70 : 108)
            .background(
                appearance == option ? Color.tomatoTint : Color.raisedFill,
                in: Radius.shape(Radius.row)
            )
            .overlay {
                Radius.shape(Radius.row)
                    .strokeBorder(
                        appearance == option ? Color.tomato : Color.hairline,
                        lineWidth: appearance == option ? 1.5 : 1
                    )
            }
            .contentShape(Radius.shape(Radius.row))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("\(option.label) appearance")
        .accessibilityValue(appearance == option ? "Selected" : "Not selected")
        .accessibilityAddTraits(appearance == option ? .isSelected : [])
    }

    private func appearancePreview(_ option: Appearance) -> some View {
        ZStack {
            let dark = option == .dark
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dark ? Color(rgb: 0x211A14) : Color(rgb: 0xFFFDFC))
            VStack(spacing: 4) {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color.tomato)
                        .frame(width: 6, height: 6)
                    Capsule()
                        .fill(dark ? Color(rgb: 0xF4EDE3) : Color(rgb: 0x221B14))
                        .frame(width: 20, height: 4)
                }
                Capsule()
                    .fill(dark ? Color(rgb: 0x362E24) : Color(rgb: 0xEFE9E2))
                    .frame(width: 35, height: 11)
            }
            if option == .system {
                Rectangle()
                    .fill(Color(rgb: 0x211A14))
                    .frame(width: 24)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .mask(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .opacity(0.92)
            }
        }
        .frame(width: 48, height: 42)
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.hairline))
        .plChrome()
        .accessibilityHidden(true)
    }

    private func selectionMark(_ option: Appearance) -> some View {
        Image(systemName: appearance == option ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(appearance == option ? Color.tomato : Color.inkFaint)
            .plChrome()
    }

    @ViewBuilder
    private var planningReminderRow: some View {
        switch notificationState {
        case .allowed:
            SettingsControlRow(
                symbol: remindersOn ? "bell.badge.fill" : "bell",
                title: "Cook reminders",
                detail: remindersOn
                    ? "Your cook nights and an unfinished week"
                    : "Off. Plated will stay quiet.",
                tint: .tomatoTint,
                tone: .tomato
            ) {
                Toggle("Cook reminders", isOn: $remindersOn)
                    .labelsHidden()
                    .tint(Color.tomato)
                    .sensoryFeedback(.selection, trigger: remindersOn)
                    .onChange(of: remindersOn) { _, on in
                        if !on {
                            Task { await NotificationScheduler.cancelAll() }
                        }
                    }
            }
        case .notDetermined:
            SettingsControlRow(
                symbol: "bell.badge",
                title: "Cook reminders",
                detail: "Helpful nudges tied to real plans",
                tint: .tomatoTint,
                tone: .tomato
            ) {
                Button("Turn on") {
                    Haptic.tap()
                    Task {
                        _ = await NotificationScheduler.requestFromSettings()
                        await refreshStatus()
                    }
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.onTomato)
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background(Color.tomato, in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.pressable)
            }
        case .denied:
            SettingsControlRow(
                symbol: "bell.slash",
                title: "Cook reminders",
                detail: "Notifications are off in iOS Settings",
                tint: .fill,
                tone: .inkSecondary
            ) {
                Button("Open") {
                    Haptic.tap()
                    openSystemSettings()
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.pressable)
                .accessibilityLabel("Open notification settings")
            }
        }
    }

    /// The second switch, same three states as the first: never asked (the
    /// button asks), refused (only iOS Settings can change it), allowed.
    @ViewBuilder
    private var tableActivityRow: some View {
        switch notificationState {
        case .allowed:
            SettingsControlRow(
                symbol: tableNewsOn ? "fork.knife.circle.fill" : "fork.knife.circle",
                title: "Household and Table activity",
                detail: tableNewsOn
                    ? "Dishes, replies, plates, new seats and changes to the plan"
                    : "Off. The bell still keeps the list.",
                tint: .tomatoTint,
                tone: .tomato
            ) {
                Toggle("Household and Table activity", isOn: $tableNewsOn)
                    .labelsHidden()
                    .tint(Color.tomato)
                    .sensoryFeedback(.selection, trigger: tableNewsOn)
                    // The icon counts only while the Table may speak.
                    .onChange(of: tableNewsOn) { _, _ in AppBadge.sync(context) }
            }
        case .notDetermined:
            SettingsControlRow(
                symbol: "fork.knife.circle",
                title: "Household and Table activity",
                detail: "When someone plates, replies, takes a seat or changes the plan",
                tint: .tomatoTint,
                tone: .tomato
            ) {
                Button("Turn on") {
                    Haptic.tap()
                    Task {
                        _ = await NotificationScheduler.requestFromSettings()
                        await refreshStatus()
                    }
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.onTomato)
                .padding(.horizontal, 13)
                .frame(minHeight: 40)
                .background(Color.tomato, in: Capsule())
                .contentShape(Capsule())
                .buttonStyle(.pressable)
            }
        case .denied:
            SettingsControlRow(
                symbol: "fork.knife.circle",
                title: "Household and Table activity",
                detail: "Notifications are off in iOS Settings",
                tint: .fill,
                tone: .inkSecondary
            ) {
                Button("Open") {
                    Haptic.tap()
                    openSystemSettings()
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.pressable)
                .accessibilityLabel("Open notification settings")
            }
        }
    }

    /// One category of Table news. Off keeps the row in the bell and takes
    /// it off the screen and the icon; the caption says which.
    private func categoryRow(_ category: NewsPreferences.Category) -> some View {
        let binding = Binding(
            get: { categoryStates[category] ?? NewsPreferences.isOn(category) },
            set: { on in
                categoryStates[category] = on
                NewsPreferences.set(category, on: on)
                AppBadge.sync(context)
            }
        )
        return SettingsControlRow(
            symbol: category.symbol,
            title: category.title,
            detail: binding.wrappedValue ? category.detail : "Off. Still in the bell, never on the screen.",
            tint: .chipFill,
            tone: .ink
        ) {
            Toggle(category.title, isOn: binding)
                .labelsHidden()
                .tint(Color.tomato)
                .sensoryFeedback(.selection, trigger: binding.wrappedValue)
        }
    }

    private var calendarRow: some View {
        SettingsControlRow(
            symbol: calendarRefused ? "calendar.badge.exclamationmark" : "calendar",
            title: "Calendar on the plan",
            detail: calendarRefused
                ? "Calendar access is off in iOS Settings"
                : showCalendarEvents
                    ? "Events appear beside each night"
                    : "See busy nights before choosing dinner",
            tint: .basilTint,
            tone: .completion
        ) {
            if calendarRefused {
                Button("Open") {
                    Haptic.tap()
                    openSystemSettings()
                }
                .plType(.footnote, .bold)
                .foregroundStyle(Color.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .buttonStyle(.pressable)
                .accessibilityLabel("Open calendar settings")
            } else {
                Toggle("Calendar on the plan", isOn: $showCalendarEvents)
                    .labelsHidden()
                    .tint(Color.tomato)
                    .sensoryFeedback(.selection, trigger: showCalendarEvents)
                    .onChange(of: showCalendarEvents) { _, on in
                        guard on else { return }
                        Task {
                            let granted = await DayEventsProvider.shared.requestAccess()
                            if !granted {
                                withAnimation(.plSnap) {
                                    showCalendarEvents = false
                                    calendarRefused = true
                                }
                                Haptic.warn()
                            }
                        }
                    }
            }
        }
    }

    private var householdNameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 13) {
                SettingsIcon(symbol: "house.fill", tint: .basilTint, tone: .completion)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Household name")
                        .plType(.body, .semibold)
                        .foregroundStyle(Color.ink)
                    Text("Shown at the top of Home")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            TextField("Name your household", text: $householdName)
                .plType(.body, .semibold)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.fill, in: Radius.shape(Radius.chip))
                .overlay(Radius.shape(Radius.chip).strokeBorder(namingHousehold ? Color.tomato : Color.hairline))
                .focused($namingHousehold)
                .plTapToFocus { namingHousehold = true }
                .submitLabel(.done)
                .onSubmit { namingHousehold = false }

            Text(hostCaption)
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.raisedFill, in: Radius.shape(Radius.card))
        .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
    }

    // MARK: The household, from a member's phone (docs/household.md §8, §10)

    /// The name read-only with who can change it, whose household it is and
    /// when this phone joined, and the way out. The host's phone keeps the
    /// field above; here the name is the host's to set.
    private var memberHouseholdCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 13) {
                SettingsIcon(symbol: "house.fill", tint: .basilTint, tone: .completion)
                VStack(alignment: .leading, spacing: 2) {
                    Text(memberHouseholdName)
                        .plName()
                        .plType(.body, .semibold)
                        .foregroundStyle(Color.ink)
                    Text("\(hostFirstName) can rename it.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Text(memberLine)
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            leaveButton

            if let leaveProblem {
                ProblemRow(leaveProblem)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(Color.raisedFill, in: Radius.shape(Radius.card))
        .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
        .animation(.plSnap, value: leaveProblem)
        // On the card, not the sheet root: the root already carries the
        // sign-out dialog, and two presentation modifiers on one view is
        // the undefined behaviour CLAUDE.md warns about.
        .confirmationDialog(
            "Leave \(hostFirstName)'s household?",
            isPresented: $leaveAsked,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) { leave() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(leaveMessage)
        }
    }

    /// The tomato outline pill: the same shape the seats sheet gave "Leave
    /// this table", quiet until pressed, never the filled tomato of a
    /// committing action. Busy is a state of the label, not a fade of the
    /// control (DESIGN.md: a disabled control changes colour, it does not
    /// fade), so the tap is guarded rather than `.disabled`.
    private var leaveButton: some View {
        Button {
            guard !leaving else { return }
            Haptic.tap()
            leaveAsked = true
        } label: {
            HStack(spacing: 8) {
                if leaving {
                    ProgressView().tint(Color.tomato)
                }
                Text(leaving ? "Leaving" : "Leave household")
                    .plType(.body, .bold)
                    .plActionLabel()
            }
            .foregroundStyle(Color.tomato)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(leaving ? "Leaving the household" : "Leave household")
        .accessibilityHint("Asks before you leave.")
    }

    /// The host's first name, from the app-group value the join recorded.
    /// "The host" when it never arrived, rather than an empty possessive.
    private var hostFirstName: String {
        let host = HouseholdShare.cachedOwnerName.trimmingCharacters(in: .whitespaces)
        let first = host.split(separator: " ").first.map(String.init) ?? host
        return first.isEmpty ? "The host" : first
    }

    /// On a member's phone the name is the root's alone (§3.6): the typed
    /// value the merge wrote, else the cached root name, else the host's.
    private var memberHouseholdName: String {
        let typed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        let cached = HouseholdShare.cachedName.trimmingCharacters(in: .whitespacesAndNewlines)
        return cached.isEmpty ? "\(hostFirstName)'s household" : cached
    }

    /// "Nate's household. You joined Tuesday." The date is the seat's own
    /// `joinedAt`; without one the sentence stops at whose household it is
    /// rather than inventing a day.
    private var memberLine: String {
        var line = "\(hostFirstName)'s household."
        if let joined = me?.joinedAt {
            line += " You joined \(HouseholdMember.when(joined))."
        }
        return line
    }

    /// Every other seat, joined and by-name alike: a place laid for
    /// somebody is a place at this household whether or not they hold a
    /// phone. An invited seat is not, and neither is one that left, so the
    /// list is `hostedNames` rather than "everybody but me" (§10).
    private var hostCaption: String {
        let names = members.hostedNames
        guard !names.isEmpty else { return "Add someone from Home to plan together." }
        return "You host this household with \(HouseholdIdentity.seatedLine(names: names))."
    }

    /// Section 8, verbatim, plus the by-name seats this phone laid: they
    /// were mine before the household and come back out with me.
    private var leaveMessage: String {
        var text = "You'll leave the Table too. Your recipes and awards stay with you, and the household keeps its copy of your recipes. The plan and the grocery list stay with the household."
        let brought = members
            .filter { $0.seat == .notOnPlated && $0.authorID == TableIdentity.cached }
            .map(\.name)
        if !brought.isEmpty {
            text += " \(JoinHouseholdSheet.list(brought)) \(brought.count == 1 ? "comes" : "come") with you."
        }
        return text
    }

    /// The root goes out on commit only, and only when the trimmed name
    /// differs from the one last exchanged (§3.6): a push per keystroke
    /// would put every half-typed name in front of the household, and a
    /// push of an unchanged name is a write that says nothing.
    private func commitHouseholdName() {
        guard membership == .hosting else { return }
        let typed = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        let synced = HouseholdShare.groupDefaults.string(forKey: HouseholdShare.Keys.lastSyncedName) ?? ""
        guard typed != synced else { return }
        HouseholdOutbox.shared.enqueueRoot()
        print("PLATED HOUSEHOLD: household name changed, root queued")
    }

    private func leave() {
        guard !leaving else { return }
        withAnimation(.plSnap) {
            leaving = true
            leaveProblem = nil
        }
        Task {
            let left = await HouseholdSync.leave(context: context)
            withAnimation(.plSnap) { leaving = false }
            if left {
                Haptic.plate()
                membership = HouseholdShare.membership
                dismiss()
            } else {
                Haptic.warn()
                withAnimation(.plSnap) {
                    leaveProblem = "Couldn't leave. Check your connection and try again."
                }
            }
        }
    }

    /// Which table the nights planned on this phone go to. Three honest
    /// states (docs/plan-share.md, "Which zone is the household's"): one
    /// table, named; several with no choice written down, a picker; none,
    /// and the caption says what would change that. And a fourth for when
    /// iCloud could not be asked, which is not "nobody": a member with a
    /// seat at Riley's table, offline, must not be told to go find one.
    /// A zone never counts because it merely exists, so this row can
    /// never guess.
    @ViewBuilder
    private var planShareRow: some View {
        switch planHousehold {
        case .unknown:
            SettingsControlRow(
                symbol: "calendar.badge.exclamationmark",
                title: "Plan shared with",
                detail: "Could not check iCloud.",
                tint: .mangoTint,
                tone: .amber
            ) {
                Button("Try again") {
                    Haptic.tap()
                    Task { await refreshPlanHousehold() }
                }
                .plType(.footnote, .bold)
                .plActionLabel()
                .foregroundStyle(Color.accentText)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.pressable)
                .accessibilityLabel("Check again which table your plan is shared with")
            }
        case .none:
            SettingsValueRow(
                symbol: "calendar",
                title: "Plan shared with",
                detail: "Nobody yet. Invite somebody or take a seat at a table.",
                tint: .fill,
                tone: .inkSecondary,
                value: nil
            )
        case .resolved(let table):
            // The caption names the field this row reflects, the target,
            // and not a delivery: whether every night has reached the
            // zone is the publisher's business, reported in the console.
            SettingsValueRow(
                symbol: "calendar",
                title: "Plan shared with",
                detail: "Where the nights you plan go",
                tint: .basilTint,
                tone: .completion,
                value: Self.label(for: table)
            )
        case .unresolved(let tables):
            SettingsControlRow(
                symbol: "calendar.badge.exclamationmark",
                title: "Plan shared with",
                detail: "You sit at more than one table. Choose which one sees your week.",
                tint: .mangoTint,
                tone: .amber
            ) {
                Menu {
                    ForEach(tables) { table in
                        Button(Self.label(for: table)) { choosePlanTable(table) }
                    }
                } label: {
                    Text("Choose")
                        .plType(.footnote, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Choose the table your plan is shared with")
            }
        }
    }

    /// The root record's title is the host's name. A table with no title
    /// yet is still named for what it is rather than left blank.
    private static func label(for table: PlanShare.Table) -> String {
        if !table.title.isEmpty { return table.title }
        return table.isOwn ? "Your table" : "A table you joined"
    }

    private func choosePlanTable(_ table: PlanShare.Table) {
        Haptic.select()
        Task {
            await PlanShare.choose(owner: table.owner)
            withAnimation(.plSnap) { planHousehold = PlanShare.household }
        }
    }

    private var syncRow: some View {
        SettingsValueRow(
            symbol: sync.account.isSyncing ? "icloud.fill" : "icloud",
            title: syncTitle,
            detail: syncDetail,
            tint: sync.account.line == nil ? .basilTint : .mangoTint,
            tone: sync.account.line == nil ? .completion : .amber,
            value: sync.account.line == nil ? syncValue : "Review"
        )
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.completion)
                .frame(width: 34, height: 34)
                .background(Color.basilTint, in: Circle())
                .plChrome()
            Text("Your plan and cookbook are shared with your household and nobody else. Only posts you choose to share appear at the Table.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 5)
    }

    private var syncTitle: String {
        switch sync.account {
        case .available: return "iCloud sync"
        case .notArmed: return "Saved on this iPhone"
        case .noAccount, .restricted, .temporarilyUnavailable: return "iCloud needs attention"
        }
    }

    private var syncDetail: String {
        if let line = sync.account.line { return line }
        switch sync.account {
        case .available:
            return "Your plan and cookbook follow you across devices"
        case .notArmed:
            return "Your data stays safely on this device"
        case .noAccount, .restricted, .temporarilyUnavailable:
            return ""
        }
    }

    private var syncValue: String {
        switch sync.account {
        case .available: return "Up to date"
        case .notArmed: return "Local"
        case .noAccount, .restricted, .temporarilyUnavailable: return "Review"
        }
    }

    private func refreshStatus() async {
        await sync.refresh()
        notificationState = await NotificationScheduler.authorizationState()
        if DayEventsProvider.shared.isAuthorized {
            calendarRefused = false
        }
        await refreshPlanHousehold()
    }

    private func refreshPlanHousehold() async {
        // The last answer first, so the row is never blank while the
        // shares are asked again.
        planHousehold = PlanShare.household
        let answer = await PlanShare.resolveHousehold()
        withAnimation(.plSnap) { planHousehold = answer }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private func signOut() {
        AppleIdentity.clear()
        Haptic.plate()
        dismiss()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            didSignIn = false
        }
    }

    private static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Plated \(short) (\(build))"
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel(title)
                Text(caption)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
            }
            content
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(Color.raisedFill, in: Radius.shape(Radius.card))
        .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .overlay(Color.hairlineSoft)
            .padding(.leading, 66)
    }
}

private struct SettingsIcon: View {
    let symbol: String
    let tint: Color
    let tone: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tone)
            .frame(width: 38, height: 38)
            .background(tint, in: Circle())
            .plChrome()
    }
}

private struct SettingsValueRow: View {
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let tone: Color
    var value: String?
    var titleColor: Color = .ink

    var body: some View {
        HStack(spacing: 13) {
            SettingsIcon(symbol: symbol, tint: tint, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .plType(.body, .semibold)
                    .foregroundStyle(titleColor)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let value {
                Text(value)
                    .plType(.footnote, .semibold)
                    .plActionLabel(0.72)
                    .foregroundStyle(tone)
                    .multilineTextAlignment(.trailing)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 30)
                    .background(tint, in: Capsule())
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct SettingsControlRow<Trailing: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let symbol: String
    let title: String
    let detail: String
    let tint: Color
    let tone: Color
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Group {
            if typeSize >= .accessibility1 {
                VStack(alignment: .leading, spacing: 12) {
                    words
                    trailing
                        .padding(.leading, 51)
                }
            } else {
                HStack(spacing: 13) {
                    words
                    Spacer(minLength: 8)
                    trailing
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
    }

    private var words: some View {
        HStack(spacing: 13) {
            SettingsIcon(symbol: symbol, tint: tint, tone: tone)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .plType(.body, .semibold)
                    .foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
