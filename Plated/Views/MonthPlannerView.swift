import SwiftUI
import SwiftData

/// One calendar in either orientation. The grid selects a date; the agenda
/// underneath names every meal on that date before opening or changing it.
struct MonthPlannerView: View {
    @Binding var anchor: Date
    var askTheTable: () -> Void = {}
    @Environment(\.modelContext) private var context
    @Query private var meals: [PlannedMeal]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var planDay: Date?
    @State private var dayShown: Date?
    @State private var planSlot: MealSlot = .dinner
    @State private var mealToMove: PlannedMeal?
    @State private var swipedMeal: PersistentIdentifier?
    @State private var emptyActionsOpen = false
    @State private var dropTargetDay: Date?
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
                    Button { planSlot = .dinner; planDay = anchor } label: { Label("Plan", systemImage: "plus").plTapTarget() }
                        .plType(.footnote, .bold)
                        .disabled(anchor < Date.now.startOfDay)
                }
                if selectedMeals.isEmpty {
                    if anchor >= Date.now.startOfDay {
                        SwipeRow(isOpen: $emptyActionsOpen, actions: [
                            SwipeAction(symbol: "plus", label: "Plan") { planSlot = .dinner; planDay = anchor },
                            SwipeAction(symbol: "fork.knife", label: "Eat out") { planEatingOut() }
                        ], actionLabel: "Actions for this day") {
                            Button { planSlot = .dinner; planDay = anchor } label: {
                                Label("Plan dinner", systemImage: "plus")
                                    .plType(.body).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    } else {
                        Text("Nothing planned for this day.").plType(.body).foregroundStyle(Color.inkSecondary).padding(.vertical, 12)
                    }
                } else {
                    ForEach(selectedMeals) { meal in
                        SwipeRow(isOpen: Binding(get: { swipedMeal == meal.persistentModelID }, set: { open in swipedMeal = open ? meal.persistentModelID : (swipedMeal == meal.persistentModelID ? nil : swipedMeal) }), actions: actions(for: meal), actionLabel: "Actions for \(meal.title)") {
                        Button { dayShown = anchor } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(meal.slotValue.rawValue.capitalized).plType(.caption, .semibold).foregroundStyle(Color.inkSecondary)
                                    Text(meal.title).plType(.body, .bold)
                                    Text("\(meal.servings) servings" + (meal.cook.map { " · \($0.isOwner ? "You cook" : $0.name + " cooks")" } ?? ""))
                                        .plType(.caption).foregroundStyle(Color.inkSecondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .contextMenu { mealMenu(meal) }
                        .matchedTransitionSource(id: meal.persistentModelID, in: zoom)
                        }
                        .modifier(PlannerMealDrag(meal: meal))
                    }
                }
            }
            .foregroundStyle(Color.ink)
            .padding(.horizontal, 24)
            .padding(.bottom, Layout.floatingChromeInset)
        }
        .sheet(item: sheet) { route in
            switch route {
            case .plan(let date): PlanNightSheet(date: date, slot: planSlot, askTheTable: askTheTable)
            case .move(let meal): MoveMealSheet(meal: meal) { anchor = $0 }
            }
        }
        .onChange(of: anchor) { swipedMeal = nil; emptyActionsOpen = false }
        .onAppear {
            #if DEBUG
            if LaunchFlags.consume("-plated-reveal-plan-actions") {
                swipedMeal = selectedMeals.first?.persistentModelID
            }
            #endif
        }
        .onScrollPhaseChange { _, phase in
            if phase == .interacting { swipedMeal = nil; emptyActionsOpen = false }
        }
        .navigationDestination(item: $dayShown) { day in DayDetailView(date: day, askTheTable: askTheTable) }
    }

    private enum Sheet: Identifiable {
        case plan(Date), move(PlannedMeal)
        var id: String { switch self { case .plan(let day): "plan-\(day)"; case .move(let meal): "move-\(meal.persistentModelID)" } }
    }
    private var sheet: Binding<Sheet?> {
        Binding(get: { if let mealToMove { return .move(mealToMove) }; return planDay.map { .plan($0) } },
                set: { if $0 == nil { planDay = nil; mealToMove = nil } })
    }
    private func actions(for meal: PlannedMeal) -> [SwipeAction] {
        var actions = [SwipeAction(symbol: "pencil", label: "Edit") { planSlot = meal.slotValue; planDay = meal.date }]
        if !meal.isCooked { actions.append(SwipeAction(symbol: "calendar", label: "Move") { mealToMove = meal }) }
        actions.append(.remove { context.delete(meal); Persist.save(context) })
        return actions
    }
    @ViewBuilder private func mealMenu(_ meal: PlannedMeal) -> some View {
        Button { planSlot = meal.slotValue; planDay = meal.date } label: { Label("Edit meal", systemImage: "pencil") }
        if !meal.isCooked {
            Button { mealToMove = meal } label: { Label("Move to another date", systemImage: "calendar") }
        }
        Menu {
            Button("Unassigned") { meal.cook = nil; Persist.save(context) }
            ForEach(members) { member in
                Button(member.isOwner ? "You" : member.name) { meal.cook = member; Persist.save(context) }
            }
        } label: { Label("Who's cooking", systemImage: "person.crop.circle") }
        Button(role: .destructive) { context.delete(meal); Persist.save(context) } label: { Label("Remove meal", systemImage: "trash") }
    }

    private func dropMeal(_ tokens: [String], on target: Date) -> Bool {
        guard let source = MealPlanTransfer.decode(tokens.first),
              target.startOfDay >= Date.now.startOfDay,
              !calendar.isDate(source.date, inSameDayAs: target),
              let meal = meals.first(where: { calendar.isDate($0.date, inSameDayAs: source.date) && $0.slotValue == source.slot }),
              !meal.isCooked else { return false }
        let other = meals.first { calendar.isDate($0.date, inSameDayAs: target) && $0.slotValue == source.slot }
        guard other?.isCooked != true else { return false }
        let previous = meal.date, otherDate = other?.date
        meal.date = target.startOfDay
        other?.date = previous
        do {
            try context.save()
            Haptic.plate()
            withAnimation(.plSnap) { anchor = target; dropTargetDay = nil }
            return true
        } catch {
            meal.date = previous
            if let otherDate { other?.date = otherDate }
            Haptic.warn()
            return false
        }
    }
    private func planEatingOut() {
        guard !meals.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: anchor) && $0.slotValue == .dinner }) else { return }
        context.insert(PlannedMeal(date: anchor, customTitle: "Eating out"))
        Persist.save(context)
        Haptic.plate()
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
            .background(dropTargetDay == day ? Color.fill : Color.clear, in: RoundedRectangle(cornerRadius: Radius.chip))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dropDestination(for: String.self) { tokens, _ in dropMeal(tokens, on: day) } isTargeted: { targeted in
            withAnimation(.plSnap) {
                if targeted, day >= Date.now.startOfDay { dropTargetDay = day; Haptic.select() }
                else if dropTargetDay == day { dropTargetDay = nil }
            }
        }
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()) + (today ? ", today" : "") + ", \(count) meals planned")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func shift(_ amount: Int) {
        Haptic.select()
        withAnimation(.plSnap) { anchor = calendar.date(byAdding: .month, value: amount, to: first) ?? first }
    }
}

/// Dinner keeps the Week planner's transfer format; other slots retain their
/// identity when dropped onto a day in the month calendar.
enum MealPlanTransfer {
    static func token(for meal: PlannedMeal) -> String {
        if meal.slotValue == .dinner { return DayTransfer.token(for: meal.date) }
        return "plated-meal:\(Int(meal.date.startOfDay.timeIntervalSince1970)):\(meal.slot)"
    }
    static func decode(_ token: String?) -> (date: Date, slot: MealSlot)? {
        if let date = DayTransfer.date(from: token) { return (date, .dinner) }
        guard let token else { return nil }
        let parts = token.split(separator: ":")
        guard parts.count == 3, parts[0] == "plated-meal", let seconds = TimeInterval(parts[1]), seconds.isFinite,
              let slot = MealSlot(rawValue: String(parts[2])) else { return nil }
        return (Date(timeIntervalSince1970: seconds), slot)
    }
}

private struct PlannerMealDrag: ViewModifier {
    let meal: PlannedMeal
    func body(content: Content) -> some View {
        if meal.isCooked { content }
        else {
            content.draggable(MealPlanTransfer.token(for: meal)) {
                Label(meal.title, systemImage: "fork.knife").plType(.body, .semibold)
                    .foregroundStyle(Color.ink).padding(16)
                    .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.chip))
            }
        }
    }
}
