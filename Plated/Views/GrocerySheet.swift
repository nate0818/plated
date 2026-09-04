import SwiftUI
import SwiftData

/// Grocery is *of* the week, not a destination — the basket in the week
/// header opens it. Everything uncooked on the plan, rolled up by aisle,
/// one tap from Reminders.
struct GrocerySheet: View {
    var embedded = false
    @State private var mealPickerShown = false
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
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
    @State private var openingInstacart = false
    @State private var sheetDetent: PresentationDetent = .large
    @State private var shoppingStart = Date.now.startOfDay
    @State private var byMeal = false
    @State private var selectedMeals: Set<String> = []
    @State private var includeExtras = false
    @State private var undoCheck: (GroceryItem, Data?, Bool)?
    @State private var sourceShown: GroceryItem?
    private var selectedIDs: Set<String>? { byMeal ? selectedMeals : nil }
    private var plannedMeals: [PlannedMeal] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: shoppingStart) ?? shoppingStart
        return meals.filter { $0.date >= shoppingStart && $0.date < end && $0.cookedAt == nil && $0.recipe != nil }.sorted { $0.date < $1.date }
    }
    /// A household edit arriving while shopping must update quantities too,
    /// even when the number of meals and ingredients stays the same.
    private var planRevision: [String] {
        plannedMeals.map { meal in
            let ingredients = meal.scaledIngredients.map {
                "\($0.ingredient.name)|\($0.quantity)|\($0.ingredient.unit)|\($0.ingredient.isPantryStaple)"
            }.joined(separator: ";")
            return "\(meal.shoppingID ?? "")|\(meal.date)|\(meal.title)|\(ingredients)"
        }
    }
    private func checked(_ item: GroceryItem) -> Bool { item.isPurchased(for: selectedIDs) }
    private func needed(_ item: GroceryItem) -> Double {
        item.sources.isEmpty ? item.quantity : item.outstanding(for: selectedIDs)
    }
    @AppStorage("grocery.manualDraft") private var newItemName = ""
    @FocusState private var addFieldFocused: Bool
    /// One row open at a time, same contract as the week's plan rows.
    @State private var swipedItem: PersistentIdentifier?

    private var currentItems: [GroceryItem] {
        let windowStart = shoppingStart
        // Manual lines keep the window key of the day they were typed; give
        // them a week of life so they don't vanish as the window rolls.
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: windowStart) ?? windowStart
        let windowEnd = Calendar.current.date(byAdding: .day, value: 7, to: windowStart) ?? windowStart
        return items.filter {
            guard !$0.isDismissed else { return false }
            if byMeal {
                if $0.isManual { guard includeExtras else { return false } }
                else { guard $0.sources.contains(where: { selectedMeals.contains($0.id) }) else { return false } }
            }
            return $0.isManual
                ? $0.weekStart >= manualHorizon && $0.weekStart < windowEnd
                : Calendar.current.isSameDay($0.weekStart, windowStart)
        }
    }

    private var unchecked: [GroceryItem] {
        currentItems.filter { !checked($0) }
    }

    private var grouped: [(GroceryAisle, [GroceryItem])] {
        Dictionary(grouping: currentItems, by: \.aisleValue)
            .sorted { $0.key.sortOrder < $1.key.sortOrder }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PlatedMasthead(title: "Groceries") {
                if embedded { AccountButton() }
                else { DesignIconButton(symbol: "xmark", label: "Close groceries") { dismiss() } }
            }.padding(.horizontal, 24)
            shoppingControls


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
                        Text(byMeal && selectedMeals.isEmpty ? "Choose meals to shop for" : hasPlannedNights ? "Nothing left to buy" : "Nothing to shop for yet")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text(byMeal && selectedMeals.isEmpty ? "Select one or more meals above to build your list." : hasPlannedNights
                             ? "This week's dishes need nothing you don't have."
                             : "Plan a few nights and the list builds itself.")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                        // "We're out of olive oil" is the most obvious job
                        // this sheet has, and it lived only in the branch
                        // that draws an existing list — so it was missing
                        // exactly when the list was empty, which is when
                        // somebody most wants to type a line into it. An
                        // empty state that knows why it is empty should
                        // still offer the thing you came to do.
                        addRow
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 40)
                            .padding(.top, 10)
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
                    if undoCheck != nil {
                        Button("Undo last check") {
                            guard let (item, data, checked) = undoCheck else { return }
                            item.purchasesData = data; item.isChecked = checked
                            undoCheck = nil; Persist.save(context)
                        }.plType(.footnote, .bold).plTapTarget()
                    }
                    // "Send 0 items" is not an offer. When the list is fully
                    // shopped the committing action retires and says so.
                    if unchecked.isEmpty {
                        Text("All shopped. Nothing left to send.")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                    } else {
                    TomatoPillButton(title: "Shop with Instacart", systemImage: "cart", busy: openingInstacart) {
                        orderWithInstacart()
                    }
                    Button(exporting ? "Sending…" : "Send to Reminders") { exportToReminders() }
                        .plType(.footnote, .bold).foregroundStyle(Color.ink).plTapTarget()
                        .disabled(exporting)
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
        .background(Color.canvas)
        .padding(.bottom, embedded ? Layout.floatingChromeInset : 0)
        .toolbar(.hidden, for: .navigationBar)
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()

        .task { rebuild() }
        .onChange(of: shoppingStart) { rebuild() }
        .onChange(of: planRevision) { rebuild() }
        .onChange(of: byMeal) { _, active in
            if active && selectedMeals.isEmpty, let id = plannedMeals.first?.shoppingID { selectedMeals.insert(id) }
        }
        .sheet(isPresented: Binding(get: { mealPickerShown || sourceShown != nil }, set: { if !$0 { mealPickerShown = false; sourceShown = nil } })) {
            if mealPickerShown { mealSelector }
            else if let item = sourceShown {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.name).plType(.title)
                ForEach(item.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title).plType(.body, .bold)
                        Text(source.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " · " + GroceryMeasure.shopping(source.quantity, item.unit).text)
                            .plType(.footnote).foregroundStyle(Color.inkSecondary)
                    }
                }
                Text("Choose a package that covers at least the amount shown. Package sizes vary by store.")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
                Button("Done") { sourceShown = nil }.foregroundStyle(Color.ink).plTapTarget()
            }.padding(24).plFitsOrScrolls().presentationDetents([.medium, .large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
            }
        }
        // A receipt must not outlive its truth: "12 items sent to Reminders"
        // stayed on screen while the list underneath it changed.
        .onChange(of: unchecked.map { "\($0.name)|\($0.unit)|\(needed($0))" }) { exportResult = nil }
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
                weekStart: shoppingStart,
                isManual: true
            ))
            newItemName = ""
            if byMeal { includeExtras = true }
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
        let isChecked = checked(item)
        return HStack(spacing: 8) {
            Button {
                Haptic.select()
                undoCheck = (item, item.purchasesData, item.isChecked)
                withAnimation(.plSnap) { item.setPurchased(!isChecked, for: selectedIDs) }
                Persist.save(context)
                exportResult = nil
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(isChecked ? Color.basil : Color.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).plType(.body, .semibold)
                            .strikethrough(isChecked).foregroundStyle(isChecked ? Color.inkSecondary : Color.ink)
                        if !item.originTitle.isEmpty {
                            Text(item.sources.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }.map {
                                $0.date.formatted(.dateTime.weekday(.abbreviated)) + " · " + $0.title
                            }.joined(separator: " · "))
                                .plType(.caption).foregroundStyle(Color.inkSecondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 6)
                    Text(GroceryMeasure.shopping(isChecked ? selectedQuantity(item) : needed(item), item.unit).text)
                        .plType(.footnote, .semibold).foregroundStyle(Color.inkSecondary)
                }.frame(minHeight: 56).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name + ", " + GroceryMeasure.shopping(selectedQuantity(item), item.unit).text)
            .accessibilityValue(isChecked ? "Purchased" : "To buy")
            if !item.sources.isEmpty {
                Button { sourceShown = item } label: { Image(systemName: "info.circle").plTapTarget() }
                    .foregroundStyle(Color.inkSecondary)
                    .accessibilityLabel("Meals that need " + item.name)
            }
        }
    }

    private func selectedQuantity(_ item: GroceryItem) -> Double {
        item.sources.isEmpty ? item.quantity : item.sources.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }.reduce(0) { $0 + $1.quantity }
    }

    private func orderWithInstacart() {
        guard !openingInstacart, !unchecked.isEmpty else { return }
        let lines = unchecked.map { InstacartService.Line(name: $0.name, quantity: needed($0), unit: $0.unit) }
        openingInstacart = true
        exportResult = nil
        Task {
            defer { openingInstacart = false }
            do {
                let url = try await InstacartService.shared.shoppingURL(lines: lines)
                openURL(url) { accepted in
                    exportResult = accepted ? "Review products and checkout in Instacart." : "Couldn't open Instacart. Try again."
                }
                Haptic.plate()
            } catch {
                exportResult = error.localizedDescription
                Haptic.warn()
            }
        }
    }

    private var shoppingControls: some View {
        VStack(spacing: 14) {
            HStack {
                DatePicker("Shop from", selection: $shoppingStart, displayedComponents: .date)
                    .plType(.footnote).tint(Color.accentText)
                Spacer()
                Text("7 days").plType(.caption).foregroundStyle(Color.inkSecondary)
            }
            Picker("Shop for", selection: $byMeal) {
                Text("Whole week").tag(false)
                Text("By meal").tag(true)
            }.pickerStyle(.segmented)
            if byMeal {
                Button { mealPickerShown = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife").font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedMeals.isEmpty ? "Choose meals" : "\(selectedMeals.count) \(selectedMeals.count == 1 ? "meal" : "meals") selected").plType(.body, .semibold)
                            Text("One dinner or a few. Shop your way.").plType(.caption).foregroundStyle(Color.inkSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right").font(.system(size: 12))
                    }.padding(16).background(Color.fill, in: Radius.shape(Radius.chip)).contentShape(Rectangle())
                }.buttonStyle(.pressable)
            }
            HStack {
                Text("\(currentItems.count - unchecked.count) of \(currentItems.count) checked")
                Spacer()
                Text("\(plannedMeals.count) planned meals")
            }.plType(.caption).foregroundStyle(Color.inkSecondary)
            GeometryReader { g in
                Capsule().fill(Color.fill)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.completion).frame(width: currentItems.isEmpty ? 0 : g.size.width * CGFloat(currentItems.count - unchecked.count) / CGFloat(currentItems.count))
                    }
            }.frame(height: 3).animation(.plSnap, value: unchecked.count)
        }.foregroundStyle(Color.ink).padding(.horizontal, 24).padding(.top, 16)
    }

    private var mealSelector: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(plannedMeals) { meal in
                        if let id = meal.shoppingID {
                            Button {
                                Haptic.select()
                                if selectedMeals.contains(id) { selectedMeals.remove(id) } else { selectedMeals.insert(id) }
                            } label: {
                                HStack(spacing: 12) {
                                    RecipeArtwork(data: meal.recipe?.photoData, title: meal.title, ratio: 1, radius: Radius.small).frame(width: 56)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(meal.title).plType(.body, .semibold).foregroundStyle(Color.ink)
                                        Text(meal.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " · Serves \(meal.servings)")
                                            .plType(.caption).foregroundStyle(Color.inkSecondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: selectedMeals.contains(id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24)).foregroundStyle(selectedMeals.contains(id) ? Color.completion : Color.inkSecondary)
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedMeals.contains(id) ? .isSelected : [])
                            Divider()
                        }
                    }
                    Toggle("Include extra items", isOn: $includeExtras).plType(.body).tint(Color.completion).padding(.vertical, 20)
                }.padding(.horizontal, 24)
            }.background(Color.canvas).navigationTitle("Shop by meal").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { mealPickerShown = false } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
    }

    private func rebuild() {
        do {
            try GroceryListBuilder(context: context).rebuild(weekOf: shoppingStart)
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
        let start = shoppingStart.startOfDay
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
                let unchecked = currentItems.filter { !checked($0) }
                let quantities = Dictionary(uniqueKeysWithValues: unchecked.map { ($0.persistentModelID, needed($0)) })
                let count = try await RemindersExporter.shared.export(unchecked, quantities: quantities)
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
