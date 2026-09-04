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
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("appearance") private var appearanceRaw = Appearance.system.rawValue
    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @AppStorage("householdName") private var householdName = ""
    @AppStorage("didSignIn") private var didSignIn = false
    @AppStorage("remindersOn") private var remindersOn = true

    @State private var notificationState: NotificationScheduler.AuthorizationState = .notDetermined
    @State private var calendarRefused = false
    @State private var signOutAsked = false
    @State private var tourShown = false
    @State private var editProfileShown = false
    @State private var sync = SyncStatus.shared
    @FocusState private var namingHousehold: Bool

    private var owner: HouseholdMember? { members.first(where: \.isOwner) }
    private var appearance: Appearance {
        Appearance(rawValue: appearanceRaw) ?? .system
    }
    private var displayName: String {
        guard let name = owner?.name, !HouseholdIdentity.isPlaceholder(name) else {
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

                SettingsSection(title: "Household", caption: "The name everyone sees at home.") {
                    householdNameCard
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
                                value: "Manage",
                                showsChevron: true
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
                                value: nil,
                                showsChevron: true
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
                                showsChevron: false,
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
            if focusHouseholdName { namingHousehold = true }
        }
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
                    initials: owner?.initials ?? "Me",
                    tone: .neutralPair,
                    size: 54,
                    photo: owner?.photoData
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .plChrome()
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
        }
        .padding(16)
        .background(Color.raisedFill, in: Radius.shape(Radius.card))
        .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairline))
    }

    private var syncRow: some View {
        SettingsValueRow(
            symbol: sync.account.isSyncing ? "icloud.fill" : "icloud",
            title: syncTitle,
            detail: syncDetail,
            tint: sync.account.line == nil ? .basilTint : .mangoTint,
            tone: sync.account.line == nil ? .completion : .amber,
            value: sync.account.line == nil ? syncValue : "Review",
            showsChevron: false
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
            Text("Your plan and cookbook stay with your Apple account. Only posts you choose to share appear at the Table.")
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
    var showsChevron: Bool
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
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.trailing)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.inkFaint)
                    .plChrome()
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
