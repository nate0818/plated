import SwiftUI
import SwiftData

/// Grocery is *of* the week, not a destination — the basket in the week
/// header opens it. Everything uncooked on the plan, rolled up by aisle,
/// one tap from Reminders.
struct GrocerySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \GroceryItem.name) private var items: [GroceryItem]
    /// Only to tell the two empty lists apart: a week with nights on it and
    /// nothing left to buy is a different sentence from a week with no plan.
    @Query private var meals: [PlannedMeal]

    /// Three states, never one. DESIGN.md: "Nothing here" is a claim, and it
    /// is only true when the app actually asked and got an answer. The list
    /// is built on appear, so before that finishes there is nothing to say,
    /// and if the build throws there is something quite different to say.
    /// Same shape as TableFeedView.Reach.
    private enum Build { case building, built, failed }
    @State private var build: Build = .building
    @State private var exportResult: String?
    @State private var exporting = false
    @State private var newItemName = ""
    @FocusState private var addFieldFocused: Bool
    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedItem: PersistentIdentifier?

    private var currentItems: [GroceryItem] {
        let windowStart = Calendar.current.startOfDay(for: .now)
        // Manual lines keep the window key of the day they were typed; give
        // them a week of life so they don't vanish as the window rolls.
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: windowStart) ?? windowStart
        return items.filter {
            guard !$0.isDismissed else { return false }
            return $0.isManual
                ? $0.weekStart >= manualHorizon
                : Calendar.current.isSameDay($0.weekStart, windowStart)
        }
    }

    private var unchecked: [GroceryItem] {
        currentItems.filter { !$0.isChecked }
    }

    private var grouped: [(GroceryAisle, [GroceryItem])] {
        Dictionary(grouping: currentItems, by: \.aisleValue)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("This week")
                Text("Groceries")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)

            if currentItems.isEmpty {
                Spacer()
                switch build {
                case .building:
                    // Still asking. A spinner, no words: a sentence here
                    // would be a claim the app cannot make yet.
                    ProgressView().tint(Color.inkSecondary)
                case .failed:
                    VStack(spacing: 8) {
                        Image(systemName: "basket")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                        Text("Couldn't build the list")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text("The week is still there. This is just the list.")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                        Button("Try again") { rebuild() }
                            .plType(.footnote, .bold)
                            .foregroundStyle(Color.tomato)
                            .plTapTarget()
                            .padding(.top, 2)
                    }
                case .built:
                    VStack(spacing: 8) {
                        Image(systemName: "basket")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                        Text(hasPlannedNights ? "Nothing left to buy" : "Nothing to shop for yet")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text(hasPlannedNights
                             ? "This week's dishes need nothing you don't have."
                             : "Plan a few nights and the list builds itself.")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(grouped, id: \.0) { aisle, aisleItems in
                            VStack(alignment: .leading, spacing: 4) {
                                MicroLabel(aisle.rawValue)
                                ForEach(aisleItems, id: \.persistentModelID) { item in
                                    itemRow(item)
                                }
                            }
                        }
                        addRow
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 8) {
                    // "Send 0 items" is not an offer. When the list is fully
                    // shopped the committing action retires and says so.
                    if unchecked.isEmpty {
                        Text("All shopped. Nothing left to send.")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    } else {
                    TomatoPillButton(
                        title: "Send \(unchecked.count) item\(unchecked.count == 1 ? "" : "s") to Reminders",
                        systemImage: "checklist",
                        busy: exporting
                    ) {
                        exportToReminders()
                    }
                    Button {
                        orderWithInstacart()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cart")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Copy list and open Instacart")
                                .plType(.body, .bold)
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
                    }
                    if let exportResult {
                        Text(exportResult)
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .task { rebuild() }
        // A receipt must not outlive its truth: "12 items sent to Reminders"
        // stayed on screen while the list underneath it changed.
        .onChange(of: currentItems.count) { exportResult = nil }
    }

    /// "We're out of olive oil" — the single most obvious grocery job, and
    /// until now the only door to a hand-typed line was a checkbox buried in
    /// the recipe editor. The manual horizon and remove() already knew how
    /// to keep and clear these; the list just never offered a pen.
    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.inkFaint)
            TextField("Add an item", text: $newItemName)
                .plType(.body)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit(addManualItem)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
        }
        .contentShape(Rectangle())
        .onTapGesture { addFieldFocused = true }
        .padding(.top, 4)
    }

    private func addManualItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        // A line arriving on the list is something landing. This fired the
        // chrome tap while remove() fired the landing buzz, which is the
        // vocabulary exactly backwards.
        Haptic.plate()
        withAnimation(.plSnap) {
            context.insert(GroceryItem(
                name: name,
                aisle: RecipeImporter.aisle(for: name),
                weekStart: .now,
                isManual: true
            ))
            newItemName = ""
        }
        // Keep the keyboard: out of one thing usually means out of three.
    }

    private func itemRow(_ item: GroceryItem) -> some View {
        SwipeRow(isOpen: swipeBinding(item), actions: [.remove { remove(item) }]) {
            checkRow(item)
        }
    }

    private func swipeBinding(_ item: GroceryItem) -> Binding<Bool> {
        Binding(
            get: { swipedItem == item.persistentModelID },
            set: { open in
                swipedItem = open
                    ? item.persistentModelID
                    : (swipedItem == item.persistentModelID ? nil : swipedItem)
            }
        )
    }

    /// A struck line has to stay struck. Auto lines are regenerated from the
    /// plan on every open, so they carry a flag; a hand-typed line has nothing
    /// behind it and can simply go.
    private func remove(_ item: GroceryItem) {
        Haptic.tap()
        withAnimation(.plSnap) {
            swipedItem = nil
            if item.isManual {
                context.delete(item)
            } else {
                item.isDismissed = true
            }
        }
    }

    private func checkRow(_ item: GroceryItem) -> some View {
        Button {
            // A tick is a toggle, and DESIGN.md gives toggles `select`.
            Haptic.select()
            withAnimation(.plSnap) { item.isChecked.toggle() }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(item.isChecked ? Color.basil : Color.hairline, lineWidth: 2)
                        .background(Circle().fill(item.isChecked ? Color.basil : Color.clear))
                        .frame(width: 24, height: 24)
                    if item.isChecked {
                        // The check lands like a pen stroke, not a repaint —
                        // but a stroke, not a pop. 0.4 was a fly-in.
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.canvas)
                            .transition(.plArrive)
                    }
                }
                Text(item.name)
                    .plType(.body)
                    .foregroundStyle(item.isChecked ? Color.inkSecondary : Color.ink)
                    .strikethrough(item.isChecked, color: .inkSecondary)
                Spacer()
                Text(quantityText(item))
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
            .plTapTarget()
        }
        .buttonStyle(.pressable)
    }

    private func quantityText(_ item: GroceryItem) -> String {
        var parts: [String] = []
        if item.quantity > 0 { parts.append(Ingredient.format(item.quantity)) }
        let unit = Ingredient.unitText(item.unit, for: item.quantity)
        if !unit.isEmpty { parts.append(unit) }
        return parts.joined(separator: " ")
    }

    /// No public cart API exists, so this is the honest version: the list
    /// rides the clipboard and Instacart opens (the app when installed, the
    /// site otherwise) ready for a paste-and-search run.
    private func orderWithInstacart() {
        Haptic.plate()
        let unchecked = currentItems.filter { !$0.isChecked }
        let list = unchecked.map(\.displayText).joined(separator: "\n")
        UIPasteboard.general.string = list
        exportResult = "List copied. Paste it into your Instacart cart."
        Notifier.post(
            .groceriesOrdered, actor: "",
            body: "Grocery list copied for Instacart.",
            into: context
        )
        if let url = URL(string: "https://www.instacart.com/store") {
            openURL(url)
        }
    }

    private func rebuild() {
        do {
            try GroceryListBuilder(context: context).rebuild(weekOf: .now)
            build = .built
        } catch {
            // assertionFailure here was a crash under `make phone` and total
            // silence in TestFlight: the two worst answers, one per build
            // configuration.
            print("PLATED GROCERY: rebuild failed — \(error)")
            build = .failed
        }
    }

    private var hasPlannedNights: Bool {
        let start = Calendar.current.startOfDay(for: .now)
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return false }
        return meals.contains { $0.date >= start && $0.date < end }
    }

    private func exportToReminders() {
        // The pill stays tappable while it works, and Reminders has no
        // deduplication: two taps was two copies of the shopping list.
        guard !exporting else { return }
        exporting = true
        Task {
            do {
                let unchecked = currentItems.filter { !$0.isChecked }
                let count = try await RemindersExporter.shared.export(unchecked)
                withAnimation(.plSnap) { exportResult = "\(count) \(count == 1 ? "item" : "items") sent to Reminders" }
                Haptic.kiss()
            } catch {
                // The typed reason, not one guess covering both:
                // `noWritableList` has nothing to do with access, and telling
                // somebody to open Settings for it sends them nowhere.
                withAnimation(.plSnap) {
                    exportResult = (error as? LocalizedError)?.errorDescription
                        ?? "Couldn't add to Reminders."
                }
                Haptic.warn()
            }
            exporting = false
        }
    }
}
