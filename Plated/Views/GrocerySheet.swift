import SwiftUI
import SwiftData

/// Grocery is *of* the week, not a destination — the basket in the week
/// header opens it. Everything uncooked on the plan, rolled up by aisle,
/// one tap from Reminders.
struct GrocerySheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \GroceryItem.name) private var items: [GroceryItem]

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
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)

            if currentItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "basket")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                    Text("Nothing to shop for yet")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Plan a few nights and the list builds itself.")
                        .font(.jakarta(13, .medium))
                        .foregroundStyle(Color.inkFaint)
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
                            .font(.jakarta(14, .bold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    } else {
                    TomatoPillButton(
                        title: exporting ? "Sending…"
                            : "Send \(unchecked.count) item\(unchecked.count == 1 ? "" : "s") to Reminders",
                        systemImage: "checklist"
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
                                .font(.jakarta(15, .bold))
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
                            .font(.jakarta(12, .semibold))
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
        .task {
            do {
                try GroceryListBuilder(context: context).rebuild(weekOf: .now)
            } catch {
                assertionFailure("Grocery rebuild failed: \(error)")
            }
        }
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
                .font(.jakarta(14, .semibold))
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
        Haptic.tap()
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
        Haptic.plate()
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
            Haptic.tap()
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
                            .transition(.scale(scale: 0.86).combined(with: .opacity))
                    }
                }
                Text(item.name)
                    .font(.jakarta(15, .semibold))
                    .foregroundStyle(item.isChecked ? Color.inkFaint : Color.ink)
                    .strikethrough(item.isChecked, color: .inkFaint)
                Spacer()
                Text(quantityText(item))
                    .font(.jakarta(13, .medium))
                    .foregroundStyle(Color.inkSecondary)
            }
            .frame(minHeight: 44)
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

    private func exportToReminders() {
        exporting = true
        Task {
            do {
                let unchecked = currentItems.filter { !$0.isChecked }
                let count = try await RemindersExporter.shared.export(unchecked)
                withAnimation(.plSnap) { exportResult = "\(count) \(count == 1 ? "item" : "items") sent to Reminders" }
                Haptic.kiss()
            } catch {
                withAnimation(.plSnap) { exportResult = "Couldn't add to Reminders. Check access in iOS Settings." }
                Haptic.warn()
            }
            exporting = false
        }
    }
}
