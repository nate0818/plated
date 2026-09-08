import SwiftUI
import SwiftData
import CloudKit

/// Somebody's household, before you are in it (docs/household.md §7).
///
/// Drawn from the share's owner identity first and the root record second,
/// never from the link: a link can say anything. The sheet says what
/// joining does to what is already on this phone, in the person's own
/// numbers, and refuses in plain words where joining is not possible.
///
/// Three states, never one. Still asking: the monogram, a spinner, no
/// words. Asked: the host and the facts. Could not ask: `failure` instead
/// of a metadata, the sentence in the problem row and a way out. That
/// third one used to be a four-second toast, which is no way to carry an
/// instruction somebody has to leave the app to act on.
///
/// The shell presents this as a sheet; onboarding shows it as a step, full
/// screen, for a person who installed from the link (`embedded`).
struct JoinHouseholdSheet: View {
    /// Posted after `.joined`, so the shell can select the Plan tab.
    static let didJoin = Notification.Name("plated.household.didJoin")
    /// A sentence for the shell to show once the sheet is gone, under
    /// `userInfo["text"]`: the one state that closes with a toast.
    static let notice = Notification.Name("plated.household.joinNotice")

    let metadata: CKShare.Metadata?
    let root: HouseholdShare.RemoteRoot?
    let seat: String?
    let linkHost: String
    /// Set instead of a metadata when the share could not be read at all:
    /// no iCloud account, restricted, a dead link, an unreachable network.
    var failure: String? = nil
    /// True when this is an onboarding step rather than a sheet: no detent,
    /// the buttons pinned, and `onDone` instead of `dismiss`.
    var embedded = false
    var onDone: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var preview: HouseholdSync.JoinPreview?
    @State private var joining = false
    /// Set by `.needsSeat`: the roster's open seats to pick from.
    @State private var candidates: [HouseholdSync.SeatCandidate]?
    @State private var problem: String?
    /// The sheet's height, measured from the scroll content rather than
    /// typed (DESIGN.md: a detent is a measurement, not a guess).
    @State private var measured: CGFloat = 420

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        content.padding(.top, 60)
                    }
                    buttons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                }
                .background(Color.canvas.ignoresSafeArea())
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 22) {
                        content
                        buttons
                    }
                    .padding(.bottom, 30)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured = $0 }
                }
                .presentationDetents([.height(measured), .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.canvas)
                // The seat question is asked AFTER the share has been
                // accepted, the previous household left and the plan
                // cleared, so there is no longer anything to decline: a
                // swipe here would leave a member of this household with no
                // seat, no way back in (the link answers "already here")
                // and their own plan gone. "None of these" is the way out.
                .interactiveDismissDisabled(candidates != nil)
                .presentationCornerRadius(Radius.sheet)
            }
        }
        .task { await load() }
    }

    // MARK: What is on it

    private var host: String {
        let name = preview?.hostName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Someone" : name
    }

    private var content: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                AvatarCircle(
                    initials: preview.map { String($0.hostName.prefix(1)).uppercased() }.flatMap { $0.isEmpty ? nil : $0 } ?? "?",
                    tone: .neutralPair, size: 72, photo: preview?.hostPhoto
                )
                .padding(.top, 22)
                if failure != nil {
                    // Could not ask. No name, no household, no claim about
                    // whose invitation this was: the phone never read it.
                    EmptyView()
                } else if let preview {
                    VStack(spacing: 4) {
                        Text("\(host) invited you to their household")
                            .plType(.title)
                            .foregroundStyle(Color.ink)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        if !preview.householdName.isEmpty {
                            Text(preview.householdName)
                                .plType(.body, .medium)
                                .foregroundStyle(Color.inkSecondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                } else {
                    // Still asking: no words. A sentence here would be a
                    // claim about a household the phone has not read yet.
                    ProgressView()
                        .frame(minHeight: 44)
                        .accessibilityLabel("Reading the invitation")
                }
            }
            .padding(.horizontal, 24)

            if let preview {
                stateBody(preview)
                    .transition(.plUnfold)
            }

            if let text = failure ?? problem {
                ProblemRow(text)
                    .padding(.horizontal, 24)
                    .transition(.opacity)
            }
        }
        .animation(.plSnap, value: preview)
        .animation(.plSnap, value: candidates)
    }

    @ViewBuilder
    private func stateBody(_ preview: HouseholdSync.JoinPreview) -> some View {
        if let candidates {
            seatPicker(candidates)
        } else {
            switch preview.state {
            case .ready, .willLeave:
                factsList(facts(for: preview))
            case .ownShare:
                sentence("This is your own household's link. Send it to someone else from Home.")
            case .hostingWithJoined(let names):
                sentence("You host a household with \(Self.list(names)). Remove them first, or ask \(host) to join yours.")
            case .removed:
                sentence("\(host) removed you from this household. Ask them for a new invitation.")
            case .alreadyHere, .needsSeat:
                // `.alreadyHere` closes on load with a toast, and
                // `.needsSeat` sets `candidates` there, so the picker above
                // is what draws. Neither is ever reached here.
                EmptyView()
            }
        }
    }

    private func sentence(_ text: String) -> some View {
        Text(text)
            .plType(.body, .medium)
            .foregroundStyle(Color.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 24)
    }

    /// The facts, in §7's order. Every line is a sentence VoiceOver can
    /// read on its own, so the row combines the mark and the words.
    private func facts(for preview: HouseholdSync.JoinPreview) -> [String] {
        var lines: [String] = []
        if case .willLeave(let current) = preview.state {
            let name = current.trimmingCharacters(in: .whitespaces)
            lines.append(name.isEmpty ? "You'll leave your household first." : "You'll leave the \(name) household first.")
        }
        lines.append("You'll see the plan, the grocery list and the cookbook, and you can change them.")
        lines.append("Your recipes come with you.")
        let meals = preview.mealsFromToday
        if meals == 1 {
            lines.append("Your 1 planned meal from today on is replaced by \(host)'s plan.")
        } else if meals > 1 {
            lines.append("Your \(meals) planned meals from today on are replaced by \(host)'s plan.")
        }
        if preview.hasGroceryState {
            lines.append("Your grocery list is replaced by the household's.")
        }
        if !preview.broughtSeats.isEmpty {
            let names = Self.list(preview.broughtSeats)
            lines.append(preview.broughtSeats.count == 1 ? "\(names) comes with you." : "\(names) come with you.")
        }
        if preview.publishedAt == nil {
            lines.append("\(host)'s cookbook and plan arrive as their phone uploads them.")
        }
        lines.append("Leave any time from Settings.")
        return lines
    }

    private func factsList(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle()
                        .fill(Color.inkFaint)
                        .frame(width: 6, height: 6)
                        .offset(y: -3)
                    Text(line)
                        .plType(.body, .medium)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
    }

    /// A seatless link: the roster's open seats, and a way to say none of
    /// them is you. Chosen by record name, so two seats called Sam are two
    /// seats.
    private func seatPicker(_ candidates: [HouseholdSync.SeatCandidate]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Which seat is yours?")
                .plType(.body, .bold)
                .foregroundStyle(Color.ink)
            VStack(spacing: 0) {
                ForEach(candidates) { candidate in
                    seatRow(title: candidate.name, detail: candidate.role.capitalized) {
                        claim(candidate.id)
                    }
                    Divider().overlay(Color.hairlineSoft)
                }
                seatRow(title: "None of these", detail: "A new seat, as yourself") {
                    claim(nil)
                }
            }
            .padding(.horizontal, 14)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
        }
        .padding(.horizontal, 24)
    }

    private func seatRow(title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .plName()
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Text(detail)
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .disabled(joining)
        .accessibilityElement(children: .combine)
    }

    // MARK: The verbs

    @ViewBuilder
    private var buttons: some View {
        VStack(spacing: 12) {
            if let preview, candidates == nil {
                switch preview.state {
                case .ready:
                    TomatoPillButton(title: joining ? "Joining" : "Join", busy: joining) { join() }
                        .disabled(joining)
                case .willLeave:
                    TomatoPillButton(title: joining ? "Joining" : "Leave and join", busy: joining) { join() }
                        .disabled(joining)
                case .ownShare, .hostingWithJoined, .removed, .alreadyHere, .needsSeat:
                    EmptyView()
                }
            }
            // Not while the seat question is up. By then the share has been
            // accepted, the previous household left, the plan and the
            // grocery list cleared and the roster merged, so "Not now" is a
            // choice that no longer exists: it dismissed with membership
            // `.member`, no seat claimed, every "me" surface empty and the
            // link refused on the way back in. The picker's own "None of
            // these" is the way out (DESIGN.md, Honesty).
            if !joining, candidates == nil {
                Button {
                    Haptic.tap()
                    finish()
                } label: {
                    Text(quietVerb)
                        .plType(.body)
                        .plActionLabel()
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, embedded ? 0 : 24)
    }

    /// "Not now" while there is a Join to decline; otherwise the sheet has
    /// nothing to offer and the verb is the way out.
    private var quietVerb: String {
        if failure != nil { return embedded ? "Continue" : "Close" }
        switch preview?.state {
        case .ready, .willLeave, nil: return "Not now"
        default: return embedded ? "Continue" : "Close"
        }
    }

    /// "Sam", "Sam and Jo", "Sam, Jo and Max": first names, every one of
    /// them, because a sentence about who is being left behind may not
    /// round anybody off.
    static func list(_ names: [String]) -> String {
        let firsts = names.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
        switch firsts.count {
        case 0: return ""
        case 1: return firsts[0]
        default: return firsts.dropLast().joined(separator: ", ") + " and " + firsts[firsts.count - 1]
        }
    }

    // MARK: Doing it

    private func load() async {
        guard preview == nil, failure == nil, let metadata else { return }
        // The shell hands the metadata in, so there is nothing left to ask.
        // Without a root the state is shown for a beat rather than never,
        // so the sheet opens the same way on every road.
        if root == nil { try? await Task.sleep(for: .milliseconds(350)) }
        let read = HouseholdSync.preview(for: metadata, root: root, linkHost: linkHost, context: context)
        print("PLATED HOUSEHOLD: join sheet for \(read.hostName.isEmpty ? "an unnamed host" : read.hostName), state \(read.state)")
        if read.state == .alreadyHere {
            let name = read.hostName.trimmingCharacters(in: .whitespaces)
            NotificationCenter.default.post(
                name: Self.notice, object: nil,
                userInfo: ["text": "You're already in \(name.isEmpty ? "this" : "\(name)'s") household."]
            )
            finish()
            return
        }
        // The share is already accepted and the zone already merged; the
        // only thing this join never finished is the seat. Straight to the
        // picker, with no second accept and no second pull.
        if case .needsSeat(let open) = read.state {
            withAnimation(.plSnap) {
                preview = read
                candidates = open
            }
            return
        }
        withAnimation(.plSnap) { preview = read }
    }

    private func join() {
        guard !joining, let metadata else { return }
        withAnimation(.plSnap) {
            joining = true
            problem = nil
        }
        Task {
            let outcome = await HouseholdSync.join(metadata, root: root, seat: seat, context: context)
            handle(outcome)
        }
    }

    private func claim(_ seatName: String?) {
        guard !joining else { return }
        withAnimation(.plSnap) {
            joining = true
            problem = nil
        }
        Task {
            let outcome = await HouseholdSync.claimSeat(named: seatName, context: context)
            handle(outcome)
        }
    }

    private func handle(_ outcome: HouseholdSync.JoinOutcome) {
        withAnimation(.plSnap) { joining = false }
        switch outcome {
        case .joined:
            Haptic.kiss()
            NotificationCenter.default.post(name: Self.didJoin, object: nil)
            finish()
        case .needsSeat(let open):
            withAnimation(.plSnap) { candidates = open }
        case .refused(let reason), .failed(let reason):
            Haptic.warn()
            withAnimation(.plSnap) { problem = reason }
        }
    }

    private func finish() {
        if embedded { onDone?() } else { dismiss() }
    }
}

/// A person who installed from a household link (§7): SignIn, ProfileSetup,
/// then this, full screen, then the Tour. It fetches the share the link
/// names and shows what came back, so the invite-your-people screen is
/// never shown to somebody about to give their own plan up.
struct JoinFromLinkStep: View {
    let parsed: Invitation.Parsed
    let onDone: () -> Void

    @State private var received: ShareAcceptor.Received?
    @State private var tableAsked = false

    var body: some View {
        ZStack {
            Color.canvas.ignoresSafeArea()
            switch received {
            case .household(let metadata, let root, let seat, let host):
                JoinHouseholdSheet(metadata: metadata, root: root, seat: seat, linkHost: host, embedded: true, onDone: onDone)
                    .transition(.opacity)
            case .table(let metadata, let host, let invite):
                // A link that said household and resolved to a Table share
                // is a Table invitation, and it asks before it seats anybody.
                asking
                    .confirmationDialog(
                        tableTitle(host), isPresented: $tableAsked, titleVisibility: .visible
                    ) {
                        Button("Join the Table") {
                            Task {
                                // A refused accept was a warn haptic and
                                // then the Tour, with the seat not taken and
                                // nothing said. The shell's copy of this
                                // dialog says so; both roads say it now.
                                guard await ShareAcceptor.acceptTable(metadata, invite: invite) else {
                                    received = .failed(reason: "Couldn't join the Table. Check your connection and open the link again.")
                                    return
                                }
                                onDone()
                            }
                        }
                        Button("Not now", role: .cancel) { onDone() }
                    } message: {
                        Text("Their dishes and asks join your Table, and they see what you post.")
                    }
                    .onAppear { tableAsked = true }
            case .failed(let reason):
                VStack(spacing: 24) {
                    Spacer()
                    ProblemRow(reason)
                    Spacer()
                    InkPillButton(title: "Continue") { onDone() }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .transition(.opacity)
            case nil:
                asking
            }
        }
        .animation(.plSettle, value: received == nil)
        .task {
            print("PLATED HOUSEHOLD: onboarding is reading the invitation link")
            await ShareAcceptor.received(
                shareURL: parsed.share, seat: parsed.seat, invite: parsed.invite, linkHost: parsed.host
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: ShareAcceptor.invitationReceived)) { note in
            guard received == nil,
                  let answer = note.userInfo?["received"] as? ShareAcceptor.Received else { return }
            received = answer
        }
    }

    /// Still asking: the neutral monogram and a spinner, no words.
    private var asking: some View {
        VStack(spacing: 16) {
            AvatarCircle(initials: "?", tone: .neutralPair, size: 72)
            ProgressView()
                .frame(minHeight: 44)
                .accessibilityLabel("Reading the invitation")
        }
    }

    private func tableTitle(_ host: String) -> String {
        let who = host.trimmingCharacters(in: .whitespaces)
        return who.isEmpty ? "Someone kept you a seat at their table" : "\(who) kept you a seat at their table"
    }
}

/// The inline answer to "did anything happen?": loud enough to be seen,
/// short enough to be read. One component, so Add someone, the join sheet
/// and Home say a refusal the same way.
struct ProblemRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.tomato)
            Text(text)
                .plType(.footnote, .semibold)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.tomatoTint, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
