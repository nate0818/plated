import SwiftUI
import SwiftData

/// Turn the phone sideways and the plan widens into a month — which nights
/// are plated, who's cooking, what the calendar already claims. Read-only
/// on purpose: landscape is for seeing the shape of the month, not editing.
struct MonthPlannerView: View {
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    @State private var monthAnchor: Date = Calendar.current.startOfDay(for: .now)
    @State private var planDay: Date?
    @State private var events = DayEventsProvider.shared
    @State private var forecast = ForecastProvider.shared

    private var calendar: Calendar { Calendar.current }

    var body: some View {
        VStack(spacing: 10) {
            header
            weekdayHeader
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                    ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 64) }
                    ForEach(monthDays, id: \.self) { date in
                        dayCell(date)
                    }
                }
                .padding(.bottom, 90)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .onAppear {
            if showCalendarEvents { events.refresh() }
        }
        .sheet(item: $planDay) { date in
            PlanNightSheet(date: date)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(monthTitle)
                    .font(.gabarito(25, .bold))
                    .tracking(-0.3)
                    .foregroundStyle(Color.ink)
                // Legend rides the header — visible before you scroll an inch.
                legend
            }
            Spacer()
            monthArrow("chevron.left") { shiftMonth(-1) }
            monthArrow("chevron.right") { shiftMonth(1) }
        }
    }

    private func monthArrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 6) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.jakarta(10, .extraBold))
                    .tracking(0.5)
                    .foregroundStyle(Color.inkFaint)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Cells

    private func dayCell(_ date: Date) -> some View {
        let today = calendar.isDateInToday(date)
        let meal = dinner(on: date)
        let past = date < calendar.startOfDay(for: .now) && !today
        return Button {
            guard !past else { return }
            Haptic.tap()
            planDay = date
        } label: {
            dayCellContent(date, today: today, meal: meal, past: past)
        }
        .buttonStyle(.plain)
        .disabled(past)
    }

    private func dayCellContent(_ date: Date, today: Bool, meal: PlannedMeal?, past: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(date.formattedDayNumber())
                    .font(.gabarito(13, .extraBold))
                    .foregroundStyle(today ? Color.tomato : (past ? Color.inkFaint : Color.ink))
                if let day = forecast.forecast(for: date) {
                    Image(systemName: day.symbolName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                }
                Spacer(minLength: 0)
                if showCalendarEvents && events.hasEvent(on: date) {
                    Circle().fill(Color.grape).frame(width: 5, height: 5)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                if let meal {
                    dishDot(meal)
                    if let cook = meal.cook {
                        AvatarCircle(initials: cook.firstInitial, tone: cook.tone, size: 16)
                    }
                } else if !past {
                    Circle()
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .frame(width: 16, height: 16)
                }
                Spacer(minLength: 0)
                if meal?.gathering != nil {
                    Image(systemName: "party.popper.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.mango)
                }
            }
        }
        .padding(6)
        .frame(height: 64)
        .background(today ? Color.todayTint : Color.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(today ? Color.tomato : Color.hairline, lineWidth: today ? 1.5 : 1)
        }
        .opacity(past ? 0.55 : 1)
    }

    private func dishDot(_ meal: PlannedMeal) -> some View {
        Group {
            if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 18, height: 18)
                    .clipShape(Circle())
            } else {
                Circle().fill(Color.basil).frame(width: 8, height: 8)
                    .frame(width: 18, height: 18)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Plated") { Circle().fill(Color.basil).frame(width: 8, height: 8) }
            legendItem("Who cooks") { AvatarCircle(initials: "S", tone: .basilPair, size: 14) }
            if showCalendarEvents {
                legendItem("Calendar event") { Circle().fill(Color.grape).frame(width: 6, height: 6) }
            }
            legendItem("Gathering") {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.mango)
            }
            Spacer()
        }
    }

    private func legendItem(_ label: String, @ViewBuilder marker: () -> some View) -> some View {
        HStack(spacing: 5) {
            marker()
            Text(label)
                .font(.jakarta(11, .semibold))
                .foregroundStyle(Color.inkSecondary)
                .fixedSize()
        }
    }

    // MARK: Data

    private var monthDays: [Date] {
        guard let interval = calendar.dateInterval(of: .month, for: monthAnchor) else { return [] }
        var days: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    private var leadingBlanks: Int {
        guard let first = monthDays.first else { return 0 }
        let weekday = calendar.component(.weekday, from: first)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: monthAnchor)
    }

    private func dinner(on date: Date) -> PlannedMeal? {
        meals.first { calendar.isSameDay($0.date, date) && $0.slotValue == .dinner }
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = shifted
        }
    }
}

#Preview(traits: .landscapeLeft) {
    MonthPlannerView().modelContainer(SampleData.previewContainer)
}
