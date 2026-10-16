import SwiftUI

/// A day picker, not a disguised pair of week buttons. The old strip stayed
/// perfectly still under the finger and replaced all seven dates only after a
/// swipe ended. That made a direct manipulation feel like clicking a carousel.
///
/// This strip uses the system scroll physics, keeps the selected day centered,
/// and previews the date crossing that center line while the finger is moving.
/// The dinner plan commits once the wheel settles.
/// Each crossed day gets the quiet selection tick used by native pickers.
struct PlanDateStrip: View {
    @Binding var selection: Date
    @Binding var dropHoverDay: Date?

    let hasDinner: (Date) -> Bool
    let canAcceptDrop: (Date) -> Bool
    let moveMeal: (String?, Date) -> Bool
    let selectionChanged: () -> Void
    var navigationRevision: Int = 0
    /// The seven-day jump the header arrows used to make. WeekView owns it
    /// so the strip never grows a second copy of the week arithmetic.
    let shiftWeek: (Int) -> Void

    @State private var dates: [Date]
    @State private var scrollPosition: Date?
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var centeredIndex: Int?
    @State private var interaction = DateWheelInteraction()
    /// Set by a week action and consumed by the scroll that follows it, so
    /// VoiceOver's focus lands on the new day rather than staying on a cell
    /// that just scrolled off the screen.
    @State private var focusFollowsSelection = false
    @AccessibilityFocusState private var focusedDay: Date?
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private let cellWidth: CGFloat = 46
    private let cellSpacing: CGFloat = 2

    /// The sheet grabber turned on its side and stood at each end of the
    /// strip. iOS has taught everyone that a short grey capsule means "this
    /// surface moves in the direction I am thin"; on a sheet that is down,
    /// here it is sideways. It is a stroke, not a glyph, so inkFaint is the
    /// paint DESIGN.md allows it. It never moves: a grabber does not animate
    /// on a sheet either, and the claim it makes, that there is more strip
    /// in that direction, is kept true by the runway rebuild below, so there
    /// is no state for it to perform.
    private static let edgeMarkSize = CGSize(width: 3, height: 20)
    private static let edgeMarkInset: CGFloat = 3

    /// The scroll content dissolves under each mark rather than being cut
    /// off beside it. A grabber sits on the sheet, not on the sheet's words;
    /// on a 430pt phone the strip's hard edge otherwise lands on half a "Su".
    private static let edgeFade: CGFloat = 12

    /// Rebuild the runway before a thumb can reach its end. A year each way
    /// is generous, but the marks promise more strip in both directions and
    /// a hard stop under one of them would make that a lie.
    private static let runwayMargin = 7

    init(
        selection: Binding<Date>,
        dropHoverDay: Binding<Date?>,
        hasDinner: @escaping (Date) -> Bool,
        canAcceptDrop: @escaping (Date) -> Bool,
        moveMeal: @escaping (String?, Date) -> Bool,
        selectionChanged: @escaping () -> Void,
        navigationRevision: Int = 0,
        shiftWeek: @escaping (Int) -> Void
    ) {
        self._selection = selection
        self._dropHoverDay = dropHoverDay
        self.hasDinner = hasDinner
        self.canAcceptDrop = canAcceptDrop
        self.moveMeal = moveMeal
        self.selectionChanged = selectionChanged
        self.navigationRevision = navigationRevision
        self.shiftWeek = shiftWeek

        let day = Calendar.current.startOfDay(for: selection.wrappedValue)
        let initialDates = Self.makeDates(around: day)
        self._dates = State(initialValue: initialDates)
        // Start nil and assign after the scroll view exists. Supplying an ID
        // before the lazy stack's first layout leaves that ID as the first
        // materialized cell, with an empty half-strip to its left.
        self._scrollPosition = State(initialValue: nil)
        self._centeredIndex = State(initialValue: initialDates.firstIndex(of: day))
    }

    var body: some View {
        GeometryReader { proxy in
            let centerInset = max(0, (proxy.size.width - cellWidth) / 2)
            // Increase Contrast softens nothing a person reads: the marks
            // stay, the dissolve goes.
            let fadeWidth = contrast == .increased ? 0 : Self.edgeFade

            ScrollViewReader { reader in
            ScrollView(.horizontal) {
                // Materialize only the visible runway. Building 731 buttons
                // eagerly bloats the accessibility tree and can exhaust a
                // phone during a drag. The scroll position starts nil and is
                // assigned after layout, avoiding the old half-empty initial
                // frame while retaining native continuous physics.
                LazyHStack(spacing: cellSpacing) {
                    ForEach(dates, id: \.self) { date in
                        dayButton(date)
                            .frame(width: cellWidth)
                            .id(date)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, centerInset, for: .scrollContent)
            .scrollPosition(id: $scrollPosition, anchor: .center)
            .defaultScrollAnchor(.center, for: .initialOffset)
            .scrollTargetBehavior(snapBehavior)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.containerSize.width
            } action: { _, width in
                guard width > 0 else { return }
                // Resolve the initial lazy layout and window resizes from the
                // actual viewport, rather than racing its estimated content.
                reader.scrollTo(selection, anchor: .center)
            }
            .accessibilityIdentifier("plan-date-wheel")
            .onScrollPhaseChange { _, phase, context in
                scrollPhase = phase
                let finalIndex = DateWheelInteraction.centeredIndex(
                    offset: context.geometry.contentOffset.x,
                    leadingInset: context.geometry.contentInsets.leading,
                    stride: cellWidth + cellSpacing, count: dates.count
                )
                if phase == .tracking || (phase == .interacting && interaction.activity != .scrubbing) {
                    interaction.begin(at: finalIndex.map { dates[$0] } ?? selection)
                }

                // A very short drag can move through the final threshold as
                // the view snaps. Commit the resting date even when there was
                // no deceleration callback between the two geometry samples.
                if phase == .idle,
                   let finalIndex,
                   let settled = interaction.settle(on: dates[finalIndex], at: ProcessInfo.processInfo.systemUptime) {
                    centeredIndex = finalIndex
                    commit(settled)
                    // Native deceleration can stop a few points off a detent.
                    // Use the same viewport alignment as the initial layout
                    // so the committed day rests exactly in the center.
                    reader.scrollTo(settled, anchor: .center)

                    // Keep the edge marks honest: a thumb nearing either end
                    // of the runway gets a fresh year on both sides of where
                    // it stopped. Only after a real scrub: the first idle
                    // callback arrives while the geometry still reads index
                    // zero, and rebuilding there put the selected day at the
                    // far end of a runway that began a year earlier.
                    if let centeredIndex,
                       centeredIndex < Self.runwayMargin || centeredIndex > dates.count - 1 - Self.runwayMargin {
                        let day = settled
                        dates = Self.makeDates(around: day)
                        self.centeredIndex = dates.firstIndex(of: day)
                        scrollPosition = day
                    }
                } else if phase == .idle {
                    interaction.cancel()
                    if focusFollowsSelection {
                        focusedDay = selection
                        focusFollowsSelection = false
                    }
                }
            }
            .onScrollGeometryChange(for: Int?.self) { geometry in
                DateWheelInteraction.centeredIndex(
                    offset: geometry.contentOffset.x,
                    leadingInset: geometry.contentInsets.leading,
                    stride: cellWidth + cellSpacing,
                    count: dates.count
                )
            } action: { oldIndex, newIndex in
                centeredIndex = newIndex
                guard newIndex != oldIndex,
                      scrollPhase == .interacting || scrollPhase == .decelerating,
                      let newIndex,
                      dates.indices.contains(newIndex)
                else { return }
                interaction.cross(to: dates[newIndex], at: ProcessInfo.processInfo.systemUptime)
            }
            .onChange(of: selection) { _, value in
                navigate(to: value, feedback: false)
            }
            .onChange(of: navigationRevision) { navigate(to: selection, feedback: false) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    interaction.cancel()
                    scrollPosition = Calendar.current.startOfDay(for: selection)
                }
            }
            .onDisappear { interaction.cancel() }
            .sensoryFeedback(.selection, trigger: interaction.feedbackRevision)
            // Painted over the strip rather than masked into it: a mask on
            // the ScrollView left the lazy stack's first layout half empty,
            // every cell right of the selected day missing until a scroll.
            // The strip stands on canvas, so a canvas gradient at each edge
            // is the same dissolve without touching the scroll view at all.
            .overlay(alignment: .leading) { edgeFade(fadeWidth) }
            .overlay(alignment: .trailing) { edgeFade(fadeWidth).scaleEffect(x: -1) }
            .overlay(alignment: .leading) { edgeMark }
            .overlay(alignment: .trailing) { edgeMark }
            }
        }
        .frame(height: 76)
        .plChrome()
        .accessibilityHint("Swipe left or right to choose a date")
        .onKeyPress(.leftArrow) { adjustDay(-1); return .handled }
        .onKeyPress(.rightArrow) { adjustDay(1); return .handled }
    }

    private var centeredDate: Date? {
        guard let centeredIndex, dates.indices.contains(centeredIndex) else { return nil }
        return dates[centeredIndex]
    }

    private var snapBehavior: ViewAlignedScrollTargetBehavior {
        if #available(iOS 26.0, *) {
            ViewAlignedScrollTargetBehavior(limitBehavior: .never, anchor: .center)
        } else {
            ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByFew)
        }
    }

    /// The dissolve under each mark. Drawn for the leading edge and
    /// mirrored for the trailing one, so the two can never drift apart.
    private func edgeFade(_ width: CGFloat) -> some View {
        LinearGradient(colors: [Color.canvas, Color.canvas.opacity(0)], startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// One view drawn twice here, and a third time on the month grid, so it
    /// lives in Theme.swift rather than in either screen.
    private var edgeMark: some View {
        PlanEdgeMark().padding(.horizontal, Self.edgeMarkInset)
    }

    /// The jump the header arrows used to make, for readers who cannot
    /// swipe the strip: VoiceOver's actions rotor, Voice Control's "Show
    /// actions for Monday, September 7", Switch Control's actions menu.
    /// The marks are silent and "Monday, September 14" alone does not tell
    /// a listener that a week moved, so the week is spoken as well.
    private func weekAction(_ delta: Int) {
        let calendar = Calendar.current
        let target = calendar.date(byAdding: .day, value: delta * 7, to: selection) ?? selection
        focusFollowsSelection = true
        shiftWeek(delta)

        let spoken: String
        if calendar.isDate(target, equalTo: .now, toGranularity: .weekOfYear) {
            spoken = "This week"
        } else {
            let start = calendar.startOfWeek(for: target)
            let sameYear = calendar.isDate(start, equalTo: .now, toGranularity: .year)
            spoken = "Week of " + start.formatted(sameYear ? .dateTime.month(.wide).day() : .dateTime.month(.wide).day().year())
        }
        AccessibilityNotification.Announcement(spoken).post()
    }

    private func dayButton(_ date: Date) -> some View {
        let selected = Calendar.current.isDate(date, inSameDayAs: interaction.previewDate ?? selection)
        let hovering = dropHoverDay.map { Calendar.current.isDate($0, inSameDayAs: date) } == true

        return Button {
            choose(date)
        } label: {
            DateWheelDayLabel(date: date, selected: selected,
                              dinnerPlanned: hasDinner(date), hovering: hovering)
        }
        .buttonStyle(.pressable)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(date.formatted(.dateTime.weekday(.wide).month().day()))
        .accessibilityValue(hasDinner(date) ? "Dinner planned" : "No dinner planned")
        .modifier(DateWheelAdjustment(selected: selected) { adjustDay($0) })
        // The strip spans two years. A day-of-month identifier produced up
        // to 24 indistinguishable controls for Voice Control and UI tests.
        // Keep the spoken label human and make the programmatic identity a
        // complete calendar date.
        .accessibilityIdentifier(Self.accessibilityIdentifier(for: date))
        .accessibilityFocused($focusedDay, equals: date)
        // On the button itself, not the container: a ScrollView is not an
        // element VoiceOver lands on, so actions hung there may never be
        // offered, and this pair has to be certain.
        .accessibilityAction(named: "Previous week") { weekAction(-1) }
        .accessibilityAction(named: "Next week") { weekAction(1) }
        .accessibilityAction(named: "Today") { choose(.now.startOfDay) }
        .dropDestination(for: String.self) { tokens, _ in
            moveMeal(tokens.first, date)
        } isTargeted: { over in
            if over, canAcceptDrop(date) {
                dropHoverDay = date
            } else if dropHoverDay.map({ Calendar.current.isDate($0, inSameDayAs: date) }) == true {
                dropHoverDay = nil
            }
        }
    }

    private func commit(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        guard !Calendar.current.isDate(day, inSameDayAs: selection) else { return }
        selectionChanged()

        // The wheel previews locally while moving. Update dinner once at rest
        // without stacking content animations behind the native scroll.
        var transaction = Transaction()
        transaction.animation = nil
        withTransaction(transaction) { selection = day }
    }

    private func choose(_ date: Date) {
        let day = Calendar.current.startOfDay(for: date)
        let changed = !Calendar.current.isDate(day, inSameDayAs: interaction.previewDate ?? selection)
        navigate(to: day, feedback: changed)
        commit(day)
    }

    private func navigate(to date: Date, feedback: Bool) {
        let day = Calendar.current.startOfDay(for: date)
        if !dates.contains(day) { dates = Self.makeDates(around: day) }
        interaction.navigate(to: day, feedback: feedback)
        guard scrollPosition != day else {
            interaction.cancel()
            if focusFollowsSelection { focusedDay = day; focusFollowsSelection = false }
            return
        }
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.26)) {
            scrollPosition = day
        }
    }

    private func adjustDay(_ delta: Int) {
        let target = Calendar.current.date(byAdding: .day, value: delta, to: selection) ?? selection
        focusFollowsSelection = true
        choose(target)
    }

    private static func makeDates(around center: Date) -> [Date] {
        let calendar = Calendar.current
        let center = calendar.startOfDay(for: center)
        // A full year in either direction is a generous continuous runway;
        // the date picker, a week action and a thumb nearing either end all
        // rebuild it around wherever they land.
        return (-365...365).compactMap {
            calendar.date(byAdding: .day, value: $0, to: center)
        }
    }

    private static func accessibilityIdentifier(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "week-date-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct DateWheelAdjustment: ViewModifier {
    let selected: Bool
    let adjust: (Int) -> Void

    @ViewBuilder func body(content: Content) -> some View {
        if selected {
            content.accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: adjust(1)
                case .decrement: adjust(-1)
                @unknown default: break
                }
            }
        } else { content }
    }
}


private struct DateWheelDayLabel: View {
    let date: Date
    let selected: Bool
    let dinnerPlanned: Bool
    let hovering: Bool

    private var textColor: Color { selected ? .onSelection : .inkSecondary }
    private var background: Color { selected ? .selectionFill : hovering ? .oliveTint : .clear }

    var body: some View {
        VStack(spacing: 5) {
            Text(date.formattedWeekday()) // design-ok(action-wrap): weekday and date intentionally stack
                .plType(.caption, .medium)
            Text(date.formattedDayNumber())
                .plType(.heading, .semibold)
                .monospacedDigit()
            Circle().fill(dinnerPlanned ? textColor : .clear).frame(width: 4, height: 4)
        }
        .foregroundStyle(textColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(background, in: Radius.shape(Radius.chip))
        .contentShape(Rectangle())
    }
}
