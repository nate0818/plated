import SwiftUI

/// The launch opener — a native port of the handoff in
/// `design_handoff_plated_launch_animation` (plated-launch.jsx is the
/// authoritative scene math). A complete place setting lands at screen
/// center, folds into the wordmark's period, "plated" resolves out of the
/// blur, and everything lifts away into the first screen. All geometry
/// derives from FS = 0.11·min(w,h).
struct LaunchOpenerView: View {
    /// Flips when the app has finished waking. Ready before the wordmark
    /// settles → the lift-away plays straight after it; still loading →
    /// the opener holds in the two-pulse simmer loop and exits at a seam.
    let ready: Bool
    /// Every launch after the first. The full opener is a 4.3 second piece
    /// of theatre, which is right exactly once: the first time someone opens
    /// the app. On the two hundredth launch it is a door that sticks. Brief
    /// keeps the persimmon ground and the settled wordmark for two thirds of
    /// a second so the static launch plate still has somewhere to go, and
    /// gets out of the way.
    var brief = false
    let onFinished: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var start = Date.now
    @State private var readyAt: Double?
    @State private var seatFrame = CGRect.zero
    @State private var finished = false
    @State private var plateLanded = false
    /// The other two beats of the opener's haptic line. Each fires once.
    @State private var settingLocked = false
    @State private var liftedAway = false
    /// Pre-warm each physical beat close to its visible event. Preparing
    /// only on appearance is too early: the Taptic Engine can idle again
    /// before the plate reaches the table.
    @State private var settingPrepared = false
    @State private var landingPrepared = false
    @State private var liftPrepared = false

    // Brief outranks Reduce Motion: someone who has asked for less motion
    // is not asking for a longer opener.
    private var cue: OpenerCue { brief ? .brief : (reduceMotion ? .reduced : .full) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let fs = 0.11 * min(w, h)                        // FS — everything scales from this
            let k = fs / 118                                 // 1 reference px (authored at FS=118)
            let th: OpenerTheme = colorScheme == .dark ? .dark : .light

            TimelineView(.animation) { ctx in
                let t = ctx.date.timeIntervalSince(start)
                let (T, _) = cue.authoredTime(t, readyAt: readyAt)
                let f = OpenerFrame(T: T, cue: cue, darkRoom: colorScheme == .dark)
                let dotD = 32 * k
                let waitOut = readyAt.map { glide(1, 0, $0, $0 + 0.24, t) } ?? 1
                let waitO = cue.flat ? 0 : glide(0, 1, 4.6, 5.0, t) * waitOut

                ZStack {
                    // Ground — one flat persimmon, no gradient or vignette:
                    // the field stays a solid color edge to edge. The static
                    // launch plate is always persimmon (it can't know about
                    // After Dark), so the dark room's espresso ground is
                    // arrived at here, on camera, before the mark appears.
                    OpenerTheme.light.ground
                    if colorScheme == .dark {
                        // Reduced motion fades the lockup in over the same
                        // window the espresso used to occupy — the ground
                        // must land first or the peach mark spends half a
                        // second nearly invisible on persimmon.
                        th.ground.opacity(
                            cue.flat
                                ? glide(0, 1, 0, cue.fade * 0.64, T)
                                : glide(0, 1, 0.15, 0.75, T)
                        )
                    }

                    // Ground ripple from the set-down, at true screen center
                    if !cue.flat, f.rippleP > 0.001, f.rippleP < 0.999 {
                        RadialGradient(stops: [.init(color: .clear, location: 0.52),
                                               .init(color: th.rippleTone, location: 0.68),
                                               .init(color: .clear, location: 0.84)],
                                       center: .center, startRadius: 0, endRadius: 320 * k)
                            .frame(width: 640 * k, height: 640 * k)
                            .scaleEffect(0.14 + 1.75 * f.rippleP)
                            .opacity(0.55 * (1 - f.rippleP))
                    }

                    // The hero object is not a logo badge dropped onto the
                    // field. It is the product's noun, plated: a porcelain
                    // place setting that lands, clears, and contracts into
                    // the punctuation already waiting underneath it.
                    if !cue.flat, f.tableO > 0.001 {
                        OpenerPlaceSetting(frame: f, theme: th, k: k)
                    }

                    // Hidden twin at final tracking — stable measurement
                    // target for the period's travel to its seat.
                    lockup(fs: fs, k: k, th: th, e: 0,
                           letters: OpenerFrame.settledLetters, breathe: 1) {
                        Color.clear.onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .named("opener"))
                        } action: { seatFrame = $0 }
                    }
                    .opacity(0)
                    .accessibilityHidden(true)

                    lockup(fs: fs, k: k, th: th, e: f.trackingExtra,
                           letters: f.letters, breathe: f.breatheScale) {
                        dot(f: f, th: th, dotD: dotD, k: k, fs: fs,
                            off: CGSize(width: w / 2 - seatFrame.midX,
                                        height: h / 2 - seatFrame.midY))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Plated")

                    if !cue.flat {
                        Text("PULL UP A CHAIR")
                            .font(.jakarta(max(10.5, 24 * k), .bold))
                            .tracking(max(1.6, 4.2 * k))
                            .foregroundStyle(th.ink.opacity(0.72))
                            .offset(y: 0.92 * fs)
                            .opacity(f.promiseO)
                            .accessibilityHidden(true)
                    }

                    // Ordinary launches never get here. If real wake-up
                    // work lasts long enough to feel like a wait, explain
                    // the state instead of leaving a breathing logo to pose
                    // as progress. No percentage is invented.
                    if waitO > 0.001 {
                        OpenerWaitStatus(time: t, theme: th, k: k)
                            .padding(.bottom, max(36, geo.safeAreaInsets.bottom + 18))
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .opacity(waitO)
                    }
                }
                .frame(width: w, height: h)
            }
        }
        .coordinateSpace(name: "opener")
        .ignoresSafeArea()
        .onAppear {
            start = .now
            if ready { readyAt = 0 }
        }
        .onChange(of: ready) { _, isReady in
            if isReady, readyAt == nil {
                readyAt = Date.now.timeIntervalSince(start)
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                let t = Date.now.timeIntervalSince(start)
                // Authored time, not wall time — the hurried clock must not
                // drift the haptic away from the visible touch-down.
                let T = cue.authoredTime(t, readyAt: readyAt).T
                // Three beats, matched to what the eye already sees: the
                // setting locks, the plate lands, the table lifts away.
                // Light either side of the one medium, so the landing stays
                // the loudest thing that happens — a run of equal taps reads
                // as a stutter, not as choreography.
                //
                // The flat cues silence all three rather than re-timing
                // them: the cue they annotate is the motion itself, and a
                // haptic marking a beat the user cannot see is just a buzz.
                // That covers Reduce Motion and the brief opener both, and
                // it keeps every launch after the first from buzzing.
                if !cue.flat, !settingPrepared, T >= 0.78 {
                    settingPrepared = true
                    Haptic.prepare()
                }
                if !cue.flat, !settingLocked, T >= 1.02 {
                    // The cutlery and dinner marks click into their places.
                    // Selection is the quiet positional tick, not an impact.
                    settingLocked = true
                    Haptic.select()
                }
                if !cue.flat, !landingPrepared, T >= 1.08 {
                    landingPrepared = true
                    Haptic.prepare()
                }
                if !cue.flat, !plateLanded, T >= 1.28 {
                    // Porcelain touches the table. This is the one medium
                    // impact and therefore the center of the haptic line.
                    plateLanded = true
                    Haptic.plate()
                }
                if !cue.flat, !liftPrepared, let readyAt,
                   (readyAt < cue.simmer && T >= cue.simmer - 0.2 || T >= cue.out - 0.2) {
                    liftPrepared = true
                    Haptic.prepare()
                }
                if !cue.flat, !liftedAway, T >= cue.out {
                    // Everything lifts into the first screen — the handoff.
                    liftedAway = true
                    Haptic.tap()
                }
                if T >= cue.total {
                    if !finished { finished = true; onFinished() }
                    break
                }
            }
        }
    }

    /// Word + gap + period seat, centered. The seat drop is real layout
    /// (top padding under center alignment, the CSS margin-top twin) so the
    /// hidden twin's measurement is transform-free. Tracking contraction is
    /// painted as per-letter offsets so layout never moves.
    private func lockup(fs: Double, k: Double, th: OpenerTheme, e: Double,
                        letters: [OpenerFrame.Letter], breathe: Double,
                        @ViewBuilder seat: () -> some View) -> some View {
        HStack(spacing: 12 * k) {
            HStack(spacing: 0) {
                ForEach(Array("plated".enumerated()), id: \.offset) { i, ch in
                    let l = letters[i]
                    Text(String(ch))
                        // Spec §3: the launch wordmark is one of the three
                        // places ExtraBold survives — the handoff's medium
                        // belonged to its Helvetica, not to the register.
                        .font(.gabarito(fs, .extraBold))
                        .tracking(-0.022 * fs)
                        .foregroundStyle(th.ink)
                        .shadow(color: th.typeShadow, radius: 6 * k, y: 4 * k)
                        .opacity(l.o)
                        .blur(radius: l.b > 0.02 ? l.b * k : 0)
                        .offset(x: (Double(i) - 3) * e * fs, y: l.y * k)
                }
            }
            seat()
                .frame(width: 32 * k, height: 32 * k)
                .padding(.top, 40 * k)
                .offset(x: 3 * e * fs)
        }
        .scaleEffect(breathe)
    }

    /// The period and its halo: contact shadow, simmer glow, hairline ring,
    /// then the plate itself. `off` carries it from its seat to screen center.
    private func dot(f: OpenerFrame, th: OpenerTheme, dotD: Double, k: Double,
                     fs: Double, off: CGSize) -> some View {
        ZStack {
            Ellipse()
                .fill(th.contact)
                .frame(width: 1.3 * dotD, height: 0.26 * dotD)
                .scaleEffect(x: f.contactSpread, y: 1)
                .blur(radius: 5 * k)
                .offset(y: 0.59 * dotD)
                .opacity(0.32 * f.dotO * f.contactIn)

            RadialGradient(stops: [.init(color: th.glowCore, location: 0),
                                   .init(color: .clear, location: 0.7)],
                           center: .center, startRadius: 0, endRadius: 1.6 * dotD)
                .frame(width: 3.2 * dotD, height: 3.2 * dotD)
                .scaleEffect(1 + 0.3 * f.glow)
                .opacity(0.6 * f.glow)

            if f.ringP > 0.001, f.ringP < 0.999 {
                Circle()
                    .strokeBorder(th.ink, lineWidth: max(1, 2 * k))
                    .frame(width: dotD, height: dotD)
                    .scaleEffect(1 + 1.3 * f.ringP)
                    .opacity(0.32 * (1 - f.ringP))
            }

            Circle()
                .fill(th.ink)
                .frame(width: dotD, height: dotD)
                .scaleEffect(x: max(f.sx, 0), y: max(f.sy, 0))
                .shadow(color: th.typeShadow, radius: 6 * k, y: 4 * k)
                .opacity(f.dotO)
        }
        .offset(x: (off.width - 3 * f.trackingExtra * fs) * f.toCenter,
                y: off.height * f.toCenter)
    }

}

// MARK: - The hero place setting

/// A deliberately tiny, monochrome still life. The center fill borrows the
/// ground so it reads as dinner on porcelain without adding a second brand
/// palette to the opener. At the end of the beat the plate is exactly the
/// diameter of the wordmark period, which makes the handoff one continuous
/// object rather than a dissolve between two unrelated marks.
private struct OpenerPlaceSetting: View {
    let frame: OpenerFrame
    let theme: OpenerTheme
    let k: Double

    private var plateD: Double { 128 * k }

    var body: some View {
        ZStack {
            Ellipse()
                .fill(theme.contact)
                .frame(width: 152 * k, height: 26 * k)
                .blur(radius: 8 * k)
                .offset(y: 72 * k)
                .opacity(0.42)

            cutlery
                .opacity(frame.tableDetailO * 0.82)

            Circle()
                .fill(theme.ink)
                .frame(width: plateD, height: plateD)
                .overlay {
                    Circle()
                        .strokeBorder(theme.ground.opacity(0.18), lineWidth: max(1, 3 * k))
                        .padding(10 * k)
                }
                .overlay { dinner }
                .shadow(color: theme.typeShadow.opacity(0.9), radius: 11 * k, y: 8 * k)
        }
        .frame(width: 250 * k, height: 190 * k)
        .scaleEffect(frame.tableScale)
        .rotationEffect(.degrees(frame.tableTurn))
        .offset(y: frame.tableY * k)
        .opacity(frame.tableO)
        .accessibilityHidden(true)
    }

    private var dinner: some View {
        ZStack {
            Circle()
                .fill(theme.ground.opacity(0.94))
                .frame(width: 76 * k, height: 76 * k)

            Circle()
                .trim(from: 0.08, to: 0.72)
                .stroke(theme.ink.opacity(0.78),
                        style: StrokeStyle(lineWidth: max(1.5, 8 * k), lineCap: .round))
                .frame(width: 45 * k, height: 45 * k)
                .rotationEffect(.degrees(-24 + frame.tableTurn * 1.8))

            Capsule()
                .fill(theme.ink.opacity(0.92))
                .frame(width: 13 * k, height: 31 * k)
                .rotationEffect(.degrees(46))
                .offset(x: -13 * k, y: -11 * k)

            Capsule()
                .fill(theme.ink.opacity(0.78))
                .frame(width: 10 * k, height: 25 * k)
                .rotationEffect(.degrees(-52))
                .offset(x: 14 * k, y: 11 * k)

            Circle()
                .fill(theme.ink)
                .frame(width: 10 * k, height: 10 * k)
                .offset(x: 18 * k, y: -14 * k)
        }
        .opacity(frame.tableDetailO)
        .scaleEffect(0.86 + 0.14 * frame.tableDetailO)
    }

    private var cutlery: some View {
        ZStack {
            // Fork: one handle, one shoulder, three tines. Keeping the
            // drawing geometric lets it stay crisp at every phone and iPad
            // size without another launch asset to decode.
            ZStack(alignment: .top) {
                Capsule()
                    .frame(width: max(2, 5 * k), height: 91 * k)
                    .padding(.top, 13 * k)
                HStack(spacing: max(1.5, 3 * k)) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().frame(width: max(1.2, 3 * k), height: 28 * k)
                    }
                }
            }
            .foregroundStyle(theme.ink)
            .offset(x: -91 * k - frame.cutlerySlide * 25 * k)

            // Knife: a softer blade and a narrow handle keep the two sides
            // optically balanced instead of mirroring the fork's silhouette.
            VStack(spacing: -2 * k) {
                UnevenRoundedRectangle(topLeadingRadius: 9 * k,
                                       bottomLeadingRadius: 2 * k,
                                       bottomTrailingRadius: 3 * k,
                                       topTrailingRadius: 2 * k)
                    .frame(width: max(3, 10 * k), height: 53 * k)
                Capsule()
                    .frame(width: max(2.2, 6 * k), height: 50 * k)
            }
            .foregroundStyle(theme.ink)
            .offset(x: 91 * k + frame.cutlerySlide * 25 * k)
        }
    }
}

/// A long-wait affordance, intentionally lower in the hierarchy than the
/// wordmark. The dots show that the process is alive; their stagger is
/// time-based, so no independent animation or timer survives the opener.
private struct OpenerWaitStatus: View {
    let time: Double
    let theme: OpenerTheme
    let k: Double

    var body: some View {
        HStack(spacing: max(8, 12 * k)) {
            Text("SETTING THE TABLE")
                .font(.jakarta(max(10.5, 22 * k), .bold))
                .tracking(max(1.4, 3.6 * k))

            HStack(spacing: max(3, 5 * k)) {
                ForEach(0..<3, id: \.self) { index in
                    let wave = 0.35 + 0.65 * (0.5 + 0.5 * sin(time * 4.2 - Double(index) * 1.15))
                    Circle()
                        .frame(width: max(3, 6 * k), height: max(3, 6 * k))
                        .opacity(wave)
                }
            }
        }
        .foregroundStyle(theme.ink.opacity(0.72))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Setting the table")
    }
}

// MARK: - Timeline

/// Scene cues. The Out cue always sits one simmer cycle after the simmer
/// cue, so skipped and looped simmers share one mapping.
private struct OpenerCue {
    let simmer: Double
    let outDur: Double
    /// Clock multiplier once the app is awake before the simmer — nothing
    /// is left to cover, so the remaining choreography plays faster with
    /// the same eased shapes. A slow wake still simmers at 1:1.
    let hurry: Double
    /// Full mode rounds the simmer to whole cycles so a pulse never cuts
    /// mid-breath; the flat modes have no pulse and exit the moment they can.
    let quantizesSimmer: Bool
    /// No choreography at all: the finished lockup arrives, holds, lifts.
    /// The set-down, the travel to centre and the per-letter resolve are the
    /// parts worth watching once, and the parts that cost the seconds.
    let flat: Bool
    /// One simmer breath, and so how far Out sits behind the simmer cue.
    let cycle: Double
    /// Flat modes only: how long the lockup takes to arrive. Every other
    /// window in the flat path is derived from this and `outDur`, so a
    /// timing is changed in one place rather than four.
    let fade: Double

    var out: Double { simmer + cycle }
    var total: Double { out + outDur }

    /// Field 0.8 · Mark 1.1 · Word 1.5 · Simmer 2.2 · Out 0.9
    static let full = OpenerCue(simmer: 3.4, outDur: 0.9, hurry: 1.5,
                                quantizesSimmer: true, flat: false, cycle: 2.2, fade: 0.55)
    /// Reduce Motion: fade the finished lockup in, no pulse, leave early.
    static let reduced = OpenerCue(simmer: 1.2, outDur: 0.7, hurry: 1,
                                   quantizesSimmer: false, flat: true, cycle: 2.2, fade: 0.55)
    /// Second launch onward: 0.65s door. Long enough that the persimmon
    /// launch plate resolves into the wordmark instead of cutting to white,
    /// short enough that nobody ever waits through it.
    static let brief = OpenerCue(simmer: 0.05, outDur: 0.30, hurry: 1,
                                 quantizesSimmer: false, flat: true, cycle: 0.30, fade: 0.22)

    /// Wall clock → authored time. Before the simmer they agree (hurried
    /// once the app is ready); then the simmer repeats whole cycles until
    /// the wake-up seam that follows `readyAt`, after which Out plays.
    func authoredTime(_ t: Double, readyAt: Double?) -> (T: Double, simmerEnd: Double) {
        var t = t
        if let readyAt, readyAt < simmer, t > readyAt {
            t = readyAt + (t - readyAt) * hurry
        }
        if t < simmer { return (t, simmerEndWall(readyAt: readyAt)) }
        let end = simmerEndWall(readyAt: readyAt)
        if t < end {
            return (simmer + (t - simmer).truncatingRemainder(dividingBy: cycle), end)
        }
        return (out + (t - end), end)
    }

    private func simmerEndWall(readyAt: Double?) -> Double {
        guard let readyAt else { return .infinity }
        guard quantizesSimmer else { return max(simmer, readyAt) }
        let cycles = max(0, ((readyAt - simmer) / cycle).rounded(.up))
        return simmer + cycles * cycle
    }
}

/// One frame of choreography — a direct port of the JSX scene math.
/// Distances are in reference px (authored at FS=118); callers multiply by k.
private struct OpenerFrame {
    struct Letter { var o, b, y: Double }

    var letters: [Letter]
    var trackingExtra: Double   // current letterspacing minus final, in em
    var breatheScale: Double
    var toCenter: Double
    var dotO, sx, sy: Double
    var glow, ringP, rippleP: Double
    var contactSpread, contactIn: Double
    var tableO, tableScale, tableY, tableTurn, tableDetailO, cutlerySlide: Double
    var promiseO: Double

    static let settledLetters = [Letter](repeating: Letter(o: 1, b: 0, y: 0), count: 6)

    init(T: Double, cue: OpenerCue, darkRoom: Bool = false) {
        let S = cue.simmer, O = cue.out

        if cue.flat {
            // Every animated channel stays flat — the glow pulse included,
            // which is doubly right now that the reduced path can exit
            // mid-cycle the moment the app is ready.
            glow = 0
            // In the dark room the mark waits for the espresso to fully
            // arrive (0.35) so it fades in on its final ground; light has
            // no crossfade to wait for and starts straight away.
            let lockIn: Double = cue.fade * (darkRoom ? 0.64 : 0.27)
            let lockO = glide(0, 1, lockIn, lockIn + cue.fade, T)
                * glide(1, 0, O + cue.outDur * 0.15, O + cue.outDur * 0.9, T)
            letters = (0..<6).map { _ in Letter(o: lockO, b: 0, y: 0) }
            trackingExtra = 0
            breatheScale = 1
            toCenter = 0
            dotO = lockO
            sx = 1; sy = 1
            ringP = 0; rippleP = 0
            contactSpread = 1; contactIn = 1
            tableO = 0; tableScale = 1; tableY = 0; tableTurn = 0
            tableDetailO = 0; cutlerySlide = 0; promiseO = 0
            return
        }

        let b1 = bump(T, S + 0.25, 0.85), b2 = bump(T, S + 1.25, 0.85)
        glow = b1 + b2

        let M = 0.8, W = 1.9

        toCenter = min(max(glide(1, 0, W + 0.05, W + 0.85, T)
                           + glide(0, 1, O + 0.1, O + 0.65, T), 0), 1)
        let setDown = glide(1.55, 1, M + 0.08, M + 0.6, T)
        dotO = glide(0, 1, M + 0.08, M + 0.32, T) * glide(1, 0, O + 0.55, O + 0.85, T)
        let bLand = bump(T, M + 0.5, 0.35), bArrive = bump(T, W + 0.82, 0.4)
        let dotS = setDown * glide(1, 0.4, O + 0.5, O + 0.88, T)
            * (1 + 0.10 * (b1 + b2) + 0.05 * bArrive)
        sx = dotS * (1 + 0.10 * bLand)
        sy = dotS * (1 - 0.08 * bLand)
        ringP = glide(0, 1, S + 0.35, S + 1.35, T)
        rippleP = glide(0, 1, M + 0.52, M + 1.45, T)
        contactSpread = glide(1.6, 1, M + 0.08, M + 0.6, T)
        contactIn = glide(0, 1, M + 0.3, M + 0.6, T)

        // A 128px plate contracts to 25% at the handoff: 32px, exactly
        // `dotD`. Detail and cutlery clear first; then the porcelain itself
        // becomes punctuation while the underlying dot takes over.
        tableO = glide(0, 1, 0.48, 0.76, T) * glide(1, 0, 1.92, 2.12, T)
        tableScale = glide(0.72, 1, 0.48, 1.28, T) * glide(1, 0.25, 1.46, 2.08, T)
        tableY = glide(-70, 0, 0.48, 1.28, T)
        tableTurn = glide(-7, 0, 0.48, 1.22, T) + glide(0, 9, 1.48, 2.08, T)
        tableDetailO = glide(0, 1, 0.66, 1.02, T) * glide(1, 0, 1.42, 1.78, T)
        cutlerySlide = glide(1, 0, 0.58, 1.16, T) + glide(0, 1, 1.38, 1.82, T)
        promiseO = glide(0, 1, 2.42, 2.92, T) * glide(1, 0, O, O + 0.32, T)

        let ls = glide(0.085, -0.022, W + 0.05, W + 0.85, T)
        trackingExtra = ls + 0.022
        letters = (0..<6).map { i in
            let s0 = W + 0.12 + Double(i) * 0.055
            let s1 = O + 0.04 + Double(5 - i) * 0.045
            return Letter(
                o: glide(0, 1, s0, s0 + 0.35, T) * glide(1, 0, s1, s1 + 0.34, T),
                b: glide(9, 0, s0, s0 + 0.5, T) + glide(0, 8, s1, s1 + 0.36, T),
                y: glide(14, 0, s0, s0 + 0.5, T) + glide(0, -12, s1, s1 + 0.36, T)
            )
        }
        breatheScale = 1 + 0.012 * glow
    }
}

// MARK: - Easing (the handoff's whole vocabulary)

private func glide(_ from: Double, _ to: Double, _ s: Double, _ e: Double, _ t: Double) -> Double {
    let x = min(max((t - s) / (e - s), 0), 1)
    let eased = x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    return from + (to - from) * eased
}

private func breathe(_ from: Double, _ to: Double, _ s: Double, _ e: Double, _ t: Double) -> Double {
    let x = min(max((t - s) / (e - s), 0), 1)
    return from + (to - from) * (-(cos(.pi * x) - 1) / 2)
}

private func bump(_ t: Double, _ s: Double, _ d: Double) -> Double {
    breathe(0, 1, s, s + d / 2, t) * breathe(1, 0, s + d / 2, s + d, t)
}

// MARK: - Theme
// The opener's persimmon ground is the one place the app leads with color —
// it is the icon continued, not part of the in-app register.

private struct OpenerTheme {
    let ground, ink, contact, glowCore, rippleTone, typeShadow: Color

    static let light = OpenerTheme(
        ground: Color(rgb: 0xE4593B),
        ink: .white,
        contact: Color(rgb: 0x3C0A00).opacity(0.38),
        glowCore: .white.opacity(0.55),
        rippleTone: .white.opacity(0.28),
        typeShadow: Color(rgb: 0x581606).opacity(0.22)
    )

    static let dark = OpenerTheme(
        ground: Color(rgb: 0x584439),
        ink: Color(rgb: 0xF5824F),
        contact: .black.opacity(0.55),
        glowCore: Color(rgb: 0xF5824F).opacity(0.5),
        rippleTone: Color(rgb: 0xF5824F).opacity(0.22),
        typeShadow: .clear
    )
}

#Preview("Opener") {
    LaunchOpenerView(ready: false) {}
}
