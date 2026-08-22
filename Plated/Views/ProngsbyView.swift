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

/// The chat. Grounded in this household's cookbook via ProngsbyBrain —
/// on-device rules today, the doorway for the real model later. The thread
/// persists like any DM. Lives in the tab bar now — a seat at the table,
/// not a page behind one.
struct ProngsbyView: View {
    @Environment(\.modelContext) private var context
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query(
        filter: #Predicate<DirectMessage> { $0.peerName == "Prongsby" },
        sort: \DirectMessage.createdAt
    ) private var messages: [DirectMessage]

    @State private var draft = ""
    @State private var thinking = false
    @State private var activityShown = false

    private let starters = [
        "What should we make tonight?",
        "Substitute for buttermilk?",
        "Give me a cooking tip",
        "How do I make Pizza Night?"
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
                    if thinking {
                        HStack {
                            HStack(spacing: 6) {
                                ProngsbyGlyph(size: 18, tone: .inkSecondary)
                                Text("thinking…")
                                    .font(.jakarta(12, .semibold))
                                    .foregroundStyle(Color.inkFaint)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color.fill, in: RoundedRectangle(cornerRadius: Radius.chip))
                            Spacer(minLength: 60)
                        }
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

            if messages.isEmpty {
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
                        }
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.bottom, 8)
            }

            HStack(spacing: 10) {
                TextField("Ask the fork…", text: $draft, axis: .vertical)
                    .font(.jakarta(14, .medium))
                    .lineLimit(1...4)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                Button {
                    send(draft)
                } label: {
                    Circle()
                        .fill(draft.isEmpty ? Color.fill : Color.tomato)
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(draft.isEmpty ? Color.inkFaint : .white)
                        }
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(draft.isEmpty || thinking)
            }
            .padding(.horizontal, 24)
            .padding(.top, 10)
            // The floating tab bar rides over pushed pages — the composer
            // clears it.
            .padding(.bottom, 92)
        }
        .background(Color.canvas)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ProngsbyGlyph(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Prongsby")
                    .font(.gabarito(20, .extraBold))
                    .foregroundStyle(Color.ink)
                Text("The house fork · knows your cookbook")
                    .font(.jakarta(11, .semibold))
                    .foregroundStyle(Color.inkSecondary)
            }
            Spacer()
            ActivityBellButton {
                activityShown = true
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    private var welcome: some View {
        VStack(spacing: 10) {
            ProngsbyGlyph(size: 56)
                .padding(.top, 24)
            Text("Well hello. I'm Prongsby.")
                .font(.gabarito(19, .extraBold))
                .foregroundStyle(Color.ink)
            Text("Dinner ideas from your own cookbook, ingredient swaps, kitchen tips. I'm a young fork — the bigger brain arrives with Plated's network — but I know this table.")
                .font(.jakarta(13, .medium))
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)
        }
        .padding(.bottom, 12)
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
        guard !thinking else { return }
        let question = text.trimmingCharacters(in: .whitespaces)
        guard !question.isEmpty else { return }
        Haptic.tap()
        context.insert(DirectMessage(peerName: "Prongsby", text: question, isMine: true))
        draft = ""
        thinking = true
        let brain = ProngsbyBrain(recipes: recipes, members: members)
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            let answer = brain.reply(to: question)
            context.insert(DirectMessage(peerName: "Prongsby", text: answer, isMine: false))
            thinking = false
            Haptic.plate()
        }
    }
}
