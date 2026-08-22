import SwiftUI
import SwiftData

/// Prongsby — the house fork. Drawn by hand so he's ours: three tines of
/// hair, a long friendly face on the handle, permanently pleased to talk
/// about dinner.
struct ProngsbyGlyph: View {
    var size: CGFloat = 28
    var tone: Color = .ink

    var body: some View {
        let s = size / 28
        VStack(spacing: 0) {
            // The tines — his hair.
            HStack(spacing: 3 * s) {
                ForEach(0..<3, id: \.self) { _ in
                    Capsule()
                        .fill(tone)
                        .frame(width: 2.6 * s, height: 8 * s)
                }
            }
            // The head — the wide of the fork, with the face.
            RoundedRectangle(cornerRadius: 6 * s)
                .fill(tone)
                .frame(width: 14 * s, height: 12 * s)
                .overlay {
                    VStack(spacing: 1.6 * s) {
                        HStack(spacing: 3.4 * s) {
                            Circle().fill(Color.canvas).frame(width: 2.2 * s, height: 2.2 * s)
                            Circle().fill(Color.canvas).frame(width: 2.2 * s, height: 2.2 * s)
                        }
                        SmileShape()
                            .stroke(Color.canvas, style: StrokeStyle(lineWidth: 1.4 * s, lineCap: .round))
                            .frame(width: 5.5 * s, height: 2.6 * s)
                    }
                }
            // The handle.
            Capsule()
                .fill(tone)
                .frame(width: 3.4 * s, height: 8 * s)
        }
        .frame(width: size, height: size)
    }
}

/// The living version — a slow contented bob with a little lean, like a
/// fork listening to a good story.
struct ProngsbyIdleGlyph: View {
    var size: CGFloat = 56
    var tone: Color = .ink

    var body: some View {
        ProngsbyGlyph(size: size, tone: tone)
            .phaseAnimator([0, 1, 2]) { view, phase in
                view
                    .offset(y: phase == 1 ? -4 : 1)
                    .rotationEffect(.degrees(phase == 0 ? -3 : (phase == 2 ? 3 : 0)))
            } animation: { _ in
                .easeInOut(duration: 1.4)
            }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY)
        )
        return path
    }
}

/// What the fork is holding right now — the draft in the composer and the
/// in-flight reply. Owned by the shell so switching tabs (which tears the
/// chat view down) never eats a half-typed question or drops the thinking
/// indicator while a reply is cooking.
@Observable
final class ProngsbySession {
    var draft = ""
    var thinking = false
    var thinkingLine = ProngsbyBrain.thinkingLines[0]
}

/// The chat. Grounded in this household's cookbook, plan, and people via
/// ProngsbyBrain — on-device rules today, the doorway for the real model
/// later. The thread persists like any DM, so the history is always there.
/// Lives in the tab bar now — a seat at the table, not a page behind one.
struct ProngsbyView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]
    @Query(
        filter: #Predicate<DirectMessage> { $0.peerName == "Prongsby" },
        sort: \DirectMessage.createdAt
    ) private var messages: [DirectMessage]

    /// Draft, thinking state, and the rotating status line live above the
    /// view — the tab switch tears ProngsbyView down, and a half-typed
    /// question must survive a peek at another tab.
    @Bindable var session: ProngsbySession
    @State private var activityShown = false
    @State private var clearConfirmShown = false
    @FocusState private var composerFocused: Bool

    private let starters = [
        "What should we make tonight?",
        "Make Pizza Night vegetarian",
        "Scale BBQ Skewers for 10",
        "Who's cooking Sunday?",
        "Plan a gathering for 8",
        "Substitute for buttermilk?"
    ]

    var body: some View {
        NavigationStack {
            chat
                .navigationDestination(isPresented: $activityShown) {
                    NotificationsView()
                }
        }
    }

    private var chat: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.hairlineSoft)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if messages.isEmpty {
                        welcome
                    }
                    ForEach(messages, id: \.persistentModelID) { message in
                        bubble(message)
                    }
                    if session.thinking {
                        thinkingBubble
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 12)
            }
            // Chat stays pinned to the newest line; ScrollViewReader inside a
            // pushed destination spins the update cycle, so the anchor does
            // the job instead.
            .defaultScrollAnchor(messages.isEmpty ? .top : .bottom)

            if messages.isEmpty || messages.count < 4 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(starters, id: \.self) { starter in
                            Button {
                                send(starter)
                            } label: {
                                Text(starter)
                                    .font(.jakarta(12, .bold))
                                    .fixedSize()
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 13)
                                    .frame(height: 36)
                                    .overlay(Capsule().strokeBorder(Color.hairline))
                                    .frame(minHeight: 44)
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(session.thinking)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                TextField("Ask Prongsby…", text: $session.draft, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    // The padding is part of the pill but not of the text
                    // field — without this, taps on it go nowhere and the
                    // keyboard never shows.
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
                    .onTapGesture { composerFocused = true }
                Button {
                    send(session.draft)
                } label: {
                    Circle()
                        .fill(session.draft.isEmpty ? Color.fill : Color.tomato)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(session.draft.isEmpty ? Color.inkFaint : Color.canvas)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(session.draft.isEmpty || session.thinking)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            // The floating tab bar rides over pushed pages — the composer
            // clears it.
            .padding(.bottom, 92)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Clear your chat with Prongsby?",
            isPresented: $clearConfirmShown,
            titleVisibility: .visible
        ) {
            Button("Clear it all", role: .destructive) {
                withAnimation(.plSnap) {
                    for message in messages { context.delete(message) }
                }
            }
            Button("Keep the history", role: .cancel) {}
        }
        .onAppear {
            #if DEBUG
            // UI-test hook: fires a starter question so the thinking state
            // and reply flow can be exercised headlessly.
            if LaunchFlags.consume("-plated-prongsby-demo") {
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(600))
                    send("What should we make tonight?")
                }
            }
            #endif
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProngsbyGlyph(size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text("Prongsby")
                    .font(.gabarito(20, .extraBold))
                    .foregroundStyle(Color.ink)
                Text("Your AI cooking companion")
                    .font(.jakarta(11, .bold))
                    .foregroundStyle(Color.inkSecondary)
                // A new joke every day. Quality not guaranteed; frequency is.
                Text(ProngsbyBrain.taglineOfTheDay)
                    .font(.jakarta(10, .medium))
                    .foregroundStyle(Color.inkFaint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            Spacer()
            ActivityBellButton {
                activityShown = true
            }
            if !messages.isEmpty {
                Menu {
                    Button("Clear chat history", role: .destructive) {
                        clearConfirmShown = true
                    }
                } label: {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Color.ink)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            ProngsbyIdleGlyph(size: 56)
                .padding(.top, 24)
            Text("Well hello. I'm Prongsby.")
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
            Text("Your sous chef and planning department. I know your \(recipes.count) recipes, the week's plan, and who's cooking when — ask me to resize a dish, make it vegetarian, swap a protein, or plan the whole party.")
                .font(.jakarta(13, .medium))
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
    }

    /// The fork at work — wiggling glyph, rotating kitchen-status puns.
    private var thinkingBubble: some View {
        HStack {
            HStack(spacing: 8) {
                ProngsbyIdleGlyph(size: 20, tone: .inkSecondary)
                Text(session.thinkingLine)
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .contentTransition(.opacity)
                    .id(session.thinkingLine)
                    .transition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Color.fill, in: RoundedRectangle(cornerRadius: Radius.chip))
            Spacer(minLength: 60)
        }
        .task {
            // Rotate the status line while the fork thinks. The cancellation
            // check matters: `try?` swallows the CancellationError a torn-down
            // view's sleep throws, and without the guard this loop degenerates
            // into a zero-delay spin against the shared session.
            while session.thinking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(900))
                guard session.thinking, !Task.isCancelled else { break }
                withAnimation(.plSnap) {
                    session.thinkingLine = ProngsbyBrain.thinkingLines.filter { $0 != session.thinkingLine }.randomElement()
                        ?? ProngsbyBrain.thinkingLines[0]
                }
            }
        }
    }

    private func bubble(_ message: DirectMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isMine {
                Spacer(minLength: 60)
            } else {
                ProngsbyGlyph(size: 18, tone: .inkSecondary)
                    .padding(.bottom, 4)
            }
            Text(message.text)
                .font(.jakarta(14, .medium))
                .foregroundStyle(message.isMine ? Color.canvas : Color.ink)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    message.isMine ? Color.ink : Color.fill,
                    in: RoundedRectangle(cornerRadius: Radius.chip)
                )
            if !message.isMine { Spacer(minLength: 40) }
        }
    }

    private func send(_ text: String) {
        // One question at a time — parallel sends would interleave replies.
        guard !session.thinking else { return }
        let question = text.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        Haptic.tap()
        context.insert(DirectMessage(peerName: "Prongsby", text: question, isMine: true))
        session.draft = ""
        session.thinkingLine = ProngsbyBrain.thinkingLines.randomElement() ?? ProngsbyBrain.thinkingLines[0]
        withAnimation(.plSnap) { session.thinking = true }
        let brain = ProngsbyBrain(recipes: recipes, members: members, meals: meals)
        Task {
            // A beat of "cooking" so the reply feels made, not vended.
            try? await Task.sleep(for: .milliseconds(Int.random(in: 900...1600)))
            let answer = brain.reply(to: question)
            withAnimation(.plSnap) {
                context.insert(DirectMessage(peerName: "Prongsby", text: answer, isMine: false))
                session.thinking = false
            }
            Haptic.plate()
        }
    }
}
