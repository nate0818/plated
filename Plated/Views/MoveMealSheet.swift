import SwiftUI
import SwiftData

/// Moving keeps the meal's shopping identity and swaps occupied slots, so
/// changing nights can never silently replace another planned dinner.
///
/// **This phone's own nights only, and a household night is plainly not
/// offered one.** A move is a swap: the meal takes a date and whatever was
/// already there takes its old one. On a household night the swap partner is
/// very often a local `PlannedMeal`, so one gesture would be two writes in
/// two authorities, the zone and the store, with nothing to roll either back
/// if the other refused. `PlanNightSheet` changes a household night in
/// place, `RemotePlanRow` carries no drag lift and no Move, and this sheet
/// takes a `PlannedMeal` because that is the only thing it can honour
/// (docs/plan-share.md, "Changing a household night").
struct MoveMealSheet: View {
    let meal: PlannedMeal
    var didMove: (Date) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @State private var target: Date
    @State private var failure: String?

    init(meal: PlannedMeal, didMove: @escaping (Date) -> Void = { _ in }) {
        self.meal = meal
        self.didMove = didMove
        _target = State(initialValue: max(meal.date, Date.now.startOfDay))
    }
    private var occupant: PlannedMeal? {
        meals.first { $0.persistentModelID != meal.persistentModelID && $0.slot == meal.slot && Calendar.current.isDate($0.date, inSameDayAs: target) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Move \(meal.slotValue.title.lowercased())").plType(.title)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").plTapTarget() }
                    .accessibilityLabel("Cancel move")
            }
            Text(meal.title).plType(.body, .semibold)
            DatePicker("New date", selection: $target, in: Date.now.startOfDay..., displayedComponents: .date)
                .datePickerStyle(.graphical).tint(Color.ink).plChrome()
            if let occupant {
                Text(occupant.isCooked
                     ? "This meal has already been cooked. Choose another date."
                     : "\(occupant.title) is already planned here. The two meals will swap dates.")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
            }
            if let failure { Text(failure).plType(.footnote).foregroundStyle(Color.ink) }
            InkPillButton(title: occupant == nil ? "Move meal" : "Swap meals") { move() }
                .disabled(Calendar.current.isDate(target, inSameDayAs: meal.date) || occupant?.isCooked == true)
        }
        .foregroundStyle(Color.ink)
        .padding(24).plFitsOrScrolls()
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()
    }
    private func move() {
        guard meals.contains(where: { $0.persistentModelID == meal.persistentModelID }), !meal.isCooked else {
            failure = "This meal has changed. Close this sheet and check the plan."
            return
        }
        guard target.startOfDay >= Date.now.startOfDay, occupant?.isCooked != true else { return }
        let other = occupant, oldDate = meal.date, otherDate = occupant?.date
        meal.date = target.startOfDay
        other?.date = oldDate
        do {
            try context.save()
            Haptic.plate()
            didMove(meal.date)
            dismiss()
        } catch {
            meal.date = oldDate
            if let otherDate { other?.date = otherDate }
            failure = "Couldn't save the new date. Try again."
        }
    }
}
