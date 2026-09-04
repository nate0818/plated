import SwiftUI
import SwiftData

/// One calendar in either orientation. The grid selects a date; the agenda
/// underneath names every meal on that date before opening or changing it.
struct MonthPlannerView: View {
    @Binding var anchor: Date
    var askTheTable: () -> Void = {}
    @Query private var meals: [PlannedMeal]
    @State private var planDay: Date?
    @State private var dayShown: Date?
    @Namespace private var zoom
    private var calendar: Calendar { .current }
    private var first: Date { calendar.dateInterval(of: .month, for: anchor)?.start ?? anchor }
    private var days: [Date] { calendar.range(of: .day, in: .month, for: anchor)?.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: first) } ?? [] }
    private var leading: Int { (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7 }
    private var selectedMeals: [PlannedMeal] { meals.filter { calendar.isDate($0.date, inSameDayAs: anchor) }.sorted { $0.slotValue.sortOrder < $1.slotValue.sortOrder } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(anchor.formatted(.dateTime.month(.wide).year()))
                        .plType(.title, .bold)
                    Spacer()
                    Button { shift(-1) } label: { Image(systemName: "chevron.left").plTapTarget() }
                        .accessibilityLabel("Previous month")
                    Button { shift(1) } label: { Image(systemName: "chevron.right").plTapTarget() }
                        .accessibilityLabel("Next month")
                }
                VStack(spacing: 4) {
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { offset in
                            Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7])
                                .plType(.caption, .bold)
                                .foregroundStyle(Color.inkSecondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                        ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 48) }
                        ForEach(days, id: \.self) { day in dayCell(day) }
                    }
                }
                .plChrome()
                Divider()
                HStack {
                    Text(calendar.isDateInToday(anchor) ? "Today" : anchor.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .plType(.body, .bold)
                    Spacer()
                    Button { planDay = anchor } label: { Label("Plan", systemImage: "plus").plTapTarget() }
                        .plType(.footnote, .bold)
                        .disabled(anchor < Date.now.startOfDay)
                }
                if selectedMeals.isEmpty {
                    Text("Nothing planned for this day.")
                        .plType(.body)
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.vertical, 12)
                } else {
                    ForEach(selectedMeals) { meal in
                        Button { dayShown = anchor } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.slotValue.rawValue.capitalized).plType(.caption, .semibold).foregroundStyle(Color.inkSecondary)
                                    Text(meal.title).plType(.body, .bold)
                                    Text("\(meal.servings) servings" + (meal.cook.map { " · \($0.isOwner ? "You cook" : $0.name + " cooks")" } ?? ""))
                                        .plType(.caption).foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote)
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .matchedTransitionSource(id: meal.persistentModelID, in: zoom)
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 24)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .sheet(item: $planDay) { PlanNightSheet(date: $0, askTheTable: askTheTable) }
        .navigationDestination(item: $dayShown) { day in DayDetailView(date: day, askTheTable: askTheTable) }
    }

    private func dayCell(_ day: Date) -> some View {
        let selected = calendar.isDate(day, inSameDayAs: anchor)
        let today = calendar.isDateInToday(day)
        let count = meals.filter { calendar.isDate($0.date, inSameDayAs: day) }.count
        return Button {
            Haptic.select()
            withAnimation(.plSnap) { anchor = day }
        } label: {
            VStack(spacing: 3) {
                Text(day, format: .dateTime.day())
                    .plType(.body, .bold)
                    .frame(width: 34, height: 34)
                    .foregroundStyle(selected ? Color.onTomato : (today ? Color.tomato : Color.ink))
                    .background(selected ? Color.tomato : Color.clear, in: Circle())
                Circle().fill(count > 0 ? Color.inkSecondary : Color.clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (today ? ", today" : "") + ", \(count) meals planned")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shift(_ amount: Int) {
        Haptic.select()
        withAnimation(.plSnap) { anchor = calendar.date(byAdding: .month, value: amount, to: first) ?? first }
    }
}
