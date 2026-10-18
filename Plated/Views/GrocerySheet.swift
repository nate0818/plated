import SwiftUI
import SwiftData

/// Grocery is *of* the week, not a destination — the basket in the week
/// header opens it. Everything uncooked on the plan, rolled up by aisle,
/// one tap from Reminders.
struct GrocerySheet: View {
    var embedded = false
    @State private var mealPickerShown = false
    @State private var activityShown = false
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabPop) private var tabPop
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var shortWindow: Bool { verticalSizeClass == .compact && !typeSize.isAccessibilitySize }
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
    @State private var datePickerShown = false
    @State private var shoppingOptionsExpanded = false
    @State private var aisleOrderShown = false
    @State private var aisleOrderDraft = GroceryAisle.allCases
    @State private var byMeal = false
    @State private var selectedMeals: Set<String> = []
    @State private var includeExtras = false
    /// Pantry flags are a recipe author's "usually have" suggestion, not an
    /// inventory claim. Keep them hidden by default, but make that choice
    /// visible and reversible for every shopping window.
    @AppStorage("grocery.includePantryStaples") private var includePantryStaples = false
    @AppStorage("grocery.preferredStore") private var preferredStore = ""
    @AppStorage("grocery.budgetTarget") private var budgetTargetText = ""
    @AppStorage("grocery.aisleOrder") private var aisleOrderRaw = ""
    @State private var undoRemoval: GroceryItem?
    @State private var removalProblem: String?
    @State private var undoCheck: (GroceryItem, Data?, Bool)?
    @State private var sourceShown: GroceryItem?
    private var selectedIDs: Set<String>? { byMeal ? selectedMeals : nil }
    private var plannedMeals: [PlannedMeal] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: shoppingStart) ?? shoppingStart
        return meals.filter { $0.date >= shoppingStart && $0.date < end && $0.cookedAt == nil && $0.recipe != nil }.sorted { $0.date < $1.date }
    }
    /// Pickable nights from both halves of the household plan. Their ids are
    /// the same ids each GrocerySource carries, so one selection filters both
    /// local and remote ingredients without a second interpretation layer.
    private var mealChoices: [GroceryListBuilder.ShoppingChoice] {
        let end = Calendar.current.date(byAdding: .day, value: 7, to: shoppingStart) ?? shoppingStart
        return GroceryListBuilder.shoppingChoices(
            meals: meals, remote: PlanLedger.shared.all,
            from: shoppingStart, to: end
        )
    }
    /// A household edit arriving while shopping must update quantities too,
    /// even when the number of meals and ingredients stays the same.
    private var planRevision: [String] {
        let local = plannedMeals.map { meal in
            let ingredients = meal.scaledIngredients.map {
                "\($0.ingredient.name)|\($0.quantity)|\($0.ingredient.unit)|\($0.ingredient.isPantryStaple)"
            }.joined(separator: ";")
            return "local|\(meal.shoppingID ?? "")|\(meal.date)|\(meal.title)|\(ingredients)"
        }
        // Other household members' nights live only in PlanLedger, not in
        // `meals`. Reading the observable ledger here makes the onChange below
        // fire while Groceries remains open, rather than leaving a stale list
        // until somebody closes and reopens it.
        return local + GroceryListBuilder.remoteRevision(PlanLedger.shared.all)
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
        // Unbought manual extras remain until explicitly completed or removed.
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: windowStart) ?? windowStart
        let windowEnd = Calendar.current.date(byAdding: .day, value: 7, to: windowStart) ?? windowStart
        return items.filter {
            guard !$0.isDismissed else { return false }
            if byMeal {
                if $0.isManual { guard includeExtras else { return false } }
                else { guard $0.sources.contains(where: { selectedMeals.contains($0.id) }) else { return false } }
            }
            return $0.isManual
                ? (!$0.isChecked || ($0.weekStart >= manualHorizon && $0.weekStart < windowEnd))
                : Calendar.current.isSameDay($0.weekStart, windowStart)
        }
    }

    /// Extra hand-written lines exist independently of the current meal
    /// filter. The picker only offers "Include extra items" when there is
    /// actually something for that switch to reveal.
    private var hasManualItemsInWindow: Bool {
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: shoppingStart) ?? shoppingStart
        let windowEnd = Calendar.current.date(byAdding: .day, value: 7, to: shoppingStart) ?? shoppingStart
        return items.contains {
            !$0.isDismissed && $0.isManual
                && (!$0.isChecked || ($0.weekStart >= manualHorizon && $0.weekStart < windowEnd))
        }
    }

    private var unchecked: [GroceryItem] {
        currentItems.filter { !checked($0) }
    }

    private var grouped: [(GroceryAisle, [GroceryItem])] {
        let positions = Dictionary(uniqueKeysWithValues: aisleOrder.enumerated().map { ($1, $0) })
        return Dictionary(grouping: currentItems, by: \.aisleValue)
            .sorted { positions[$0.key, default: .max] < positions[$1.key, default: .max] }
            .map { ($0.key, $0.value.sorted { $0.name < $1.name }) }
    }

    private var removedItems: [GroceryItem] {
        items.filter { $0.isDismissed && ($0.isManual || Calendar.current.isSameDay($0.weekStart, shoppingStart)) }
    }

    private var aisleOrder: [GroceryAisle] {
        let saved = aisleOrderRaw.split(separator: "|").compactMap { GroceryAisle(rawValue: String($0)) }
        return saved + GroceryAisle.allCases.filter { !saved.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Keep the fixed check-off footer, but let the header and its
            // shopping controls scroll with the estimate and aisles. In a
            // short sheet/window, fixing both ends left only a sliver for
            // the actual list.
            ScrollViewReader { scroll in
            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 0).id("groceries-top")
                    if shortWindow {
                        HStack(spacing: 12) {
                            Text("Groceries").plType(.pageTitle).accessibilityAddTraits(.isHeader)
                            Spacer()
                            if embedded {
                                shoppingMenu
                                ActivityBellButton(size: 44) { activityShown = true }
                            } else { DesignIconButton(symbol: "xmark", label: "Close groceries") { dismiss() } }
                        }.plChrome().padding(.horizontal, Spacing.page).padding(.top, 4)
                    } else {
                    PlatedMasthead(title: "Groceries", showsCreate: false) {
                        if embedded {
                            HStack(spacing: 8) {
                                shoppingMenu
                                ActivityBellButton(size: 44) { activityShown = true }
                            }
                        } else {
                            DesignIconButton(symbol: "xmark", label: "Close groceries") { dismiss() }
                        }
                    }
                    .padding(.horizontal, Spacing.page)
                    // The embedded grocery destination is hosted inside the
                    // shell's tab stack; keep its masthead clear of the status
                    // bar while allowing it to scroll in compact windows.
                    .padding(.top, embedded ? 4 : 0)
                    }

                    shoppingControls
                    if !currentItems.isEmpty { addRow.padding(.horizontal, Spacing.page) }

                    if currentItems.isEmpty {
                        if !removedItems.isEmpty {
                            DisclosureGroup("Removed items") {
                                ForEach(removedItems) { item in
                                    Button("Restore \(item.name)") { restore(item) }
                                        .plType(.footnote).plActionLabel().plTapTarget()
                                }
                            }.plType(.footnote).padding(.horizontal, Spacing.page)
                        }
                        emptyContent
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, Spacing.page)
                            .padding(.top, 36)
                            .padding(.bottom, 40)
                    } else {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(grouped, id: \.0) { aisle, aisleItems in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        MicroLabel(aisle.rawValue)
                                        Spacer()
                                        Text("\(aisleItems.count) items").plType(.caption).foregroundStyle(Color.inkSecondary)
                                    }.padding(.bottom, 6)
                                    ForEach(aisleItems, id: \.persistentModelID) { item in
                                        itemRow(item)
                                    }
                                }
                            }
                            if !removedItems.isEmpty {
                                DisclosureGroup("Removed items") {
                                    ForEach(removedItems) { item in
                                        Button("Restore \(item.name)") { restore(item) }
                                            .plType(.footnote).plActionLabel().plTapTarget()
                                    }
                                }.plType(.footnote)
                            }
                        }
                        .padding(.horizontal, Spacing.page)
                        .padding(.top, 18)
                        .padding(.bottom, 16)
                    }
                }
            }

            .scrollIndicators(.hidden)
            .onChange(of: tabPop) { _, request in
                guard request.tab == .groceries else { return }
                withAnimation(.plSnap) { scroll.scrollTo("groceries-top", anchor: .top) }
            }
            }

            if undoRemoval != nil {
                Button("Undo remove") { if let item = undoRemoval { restore(item) } }
                    .plType(.footnote, .semibold).plActionLabel().plTapTarget()
            }
            if !currentItems.isEmpty {
                shoppingFooter.plChrome()
                    .padding(.horizontal, Spacing.page)
                    .padding(.bottom, shortWindow ? 4 : 16)
            }
        }
        .padding(.bottom, embedded ? Layout.floatingChromeInset : 0)
        .background(Color.canvas.ignoresSafeArea())
        .alert("Couldn't update groceries", isPresented: Binding(get: { removalProblem != nil }, set: { if !$0 { removalProblem = nil } })) {
            Button("OK") { removalProblem = nil }
        } message: { Text(removalProblem ?? "Please try again.") }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $activityShown) {
            NotificationsView(homeTab: .groceries)
        }
        .presentationDetents([.medium, .large], selection: $sheetDetent)
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()

        .task { rebuild() }
        .onChange(of: shoppingStart) {
            reconcileMealSelection()
            rebuild()
        }
        .onChange(of: planRevision) {
            reconcileMealSelection()
            rebuild()
        }
        .onChange(of: includePantryStaples) { rebuild() }
        .onChange(of: byMeal) { _, active in
            if active && selectedMeals.isEmpty, let id = mealChoices.first?.id { selectedMeals.insert(id) }
        }
        .onChange(of: tabPop) { _, request in
            guard request.tab == .groceries else { return }
            activityShown = false
        }
        .onChange(of: datePickerShown) { _, shown in
            // The graphical calendar cannot fit honestly in the medium
            // detent. Expand before revealing it instead of clipping its
            // final week and the controls below.
            if shown { sheetDetent = .large }
        }
        .sheet(isPresented: Binding(get: { mealPickerShown || sourceShown != nil || aisleOrderShown }, set: { if !$0 { mealPickerShown = false; sourceShown = nil; aisleOrderShown = false } })) {
            if mealPickerShown { mealSelector }
            else if let item = sourceShown {
            VStack(alignment: .leading, spacing: 16) {
                Text(item.name).plType(.title)
                ForEach(item.sources) { source in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.title).plType(.body, .bold)
                        Text(source.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " · " + GroceryMeasure.shopping(source.quantity, item.unit).text)
                            .plType(.footnote).foregroundStyle(Color.inkSecondary)
                        if let package = source.package, package.isUsable,
                           let size = package.size, let price = package.price {
                            Text("Package: \(Ingredient.format(size)) \(package.unit) · \(price.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) at \(package.store)")
                                .plType(.caption).foregroundStyle(Color.inkSecondary)
                            Text("Price source: \(package.source)")
                                .plType(.caption).foregroundStyle(Color.inkSecondary)
                        }
                    }
                }
                Text("Choose a package that covers at least the amount shown. Package sizes vary by store.")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
                Button("Done") { sourceShown = nil }.foregroundStyle(Color.ink).plTapTarget()
            }.padding(24).plFitsOrScrolls().presentationDetents([.medium, .large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
            }
            else if aisleOrderShown { aisleOrderEditor }
        }
        // A receipt must not outlive its truth: "12 items sent to Reminders"
        // stayed on screen while the list underneath it changed.
        .onChange(of: unchecked.map { "\($0.name)|\($0.unit)|\(needed($0))" }) { exportResult = nil }
        .onChange(of: exportResult) { _, result in
            if let result { AccessibilityNotification.Announcement(result).post() }
        }
    }

    private var estimateCard: some View {
        let result = costEstimate
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Shopping estimate")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                Spacer()
                if let total = result.total {
                    Text(total.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                        .plType(.title, .semibold)
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                } else {
                    Text("Unavailable")
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }

            if let total = result.total {
                Text("\(result.packageCount) full packages · recent prices for \(result.store). This is an estimate, not a checkout total.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let budget = Double(budgetTargetText), budget > 0 {
                    Text(total <= budget
                         ? "Within your \(budget.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) target"
                         : "\((total - budget).formatted(.currency(code: Locale.current.currency?.identifier ?? "USD"))) over your target")
                        .plType(.caption, .semibold)
                        .foregroundStyle(total <= budget ? Color.completion : Color.dangerText)
                }
            } else {
                Text(preferredStore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                     ? "Choose a store and add current package prices to recipe ingredients."
                     : "Add recent package size, price, store and source details for every item to see a total.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                TextField("Store", text: $preferredStore)
                    .plType(.footnote)
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 44)
                    .background(Color.canvas, in: Radius.shape(Radius.chip))
                    .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                    .accessibilityLabel("Store for grocery estimate")
                TextField("Budget", text: $budgetTargetText)
                    .plType(.footnote)
                    .keyboardType(.decimalPad)
                    .padding(.horizontal, 10)
                    .frame(width: 112)
                    .frame(minHeight: 44)
                    .background(Color.canvas, in: Radius.shape(Radius.chip))
                    .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                    .accessibilityLabel("Optional grocery budget target")
            }
        }
        .padding(14)
        .background(Color.fill, in: Radius.shape(Radius.card))
    }

    private var costEstimate: GroceryCostEstimate.Result {
        GroceryCostEstimate.calculate(
            lines: currentItems.compactMap { item in
                let quantity = needed(item)
                guard quantity > 0 else { return nil }
                return GroceryCostEstimate.InputLine(
                    name: item.name, quantity: quantity, unit: item.unit, package: packageFor(item)
                )
            },
            store: preferredStore
        )
    }

    /// Shopping is the job; export is a convenience. A full-width olive
    /// button made Reminders look like the goal and consumed nearly another
    /// aisle of the first viewport. Keep progress and the next utility close
    /// to the thumb without competing with the check rows above it.
    private var shoppingFooter: some View {
        let completed = max(0, currentItems.count - unchecked.count)
        return VStack(spacing: 4) {
            ProgressView(value: Double(completed), total: Double(max(1, currentItems.count)))
                .tint(unchecked.isEmpty ? Color.completion : Color.olive)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text(unchecked.isEmpty ? "Everything checked off" : "\(unchecked.count) items left · \(completed) of \(currentItems.count) checked")
                    .plType(.footnote).foregroundStyle(Color.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if undoCheck != nil {
                    Button("Undo") {
                        guard let (item, data, checked) = undoCheck else { return }
                        item.purchasesData = data
                        item.isChecked = checked
                        item.recordMark()
                        undoCheck = nil
                        Persist.save(context)
                    }
                    .plType(.footnote, .semibold).foregroundStyle(Color.accentText).plTapTarget()
                    .accessibilityLabel("Undo last check")
                }

            }
            if let exportResult {
                Text(exportResult).plType(.caption).foregroundStyle(Color.inkSecondary)
            }
        }
        .padding(.top, 8)
        .background(Color.canvas)
    }

    private var shoppingMenu: some View {
        Menu {
                    Button("Shopping options", systemImage: "slider.horizontal.3") { shoppingOptionsExpanded = true }
                    Button("Send to Reminders", systemImage: "checklist") { exportToReminders() }
                        .disabled(unchecked.isEmpty || exporting)
                    if InstacartService.isOffered {
                        Button("Shop with Instacart", systemImage: "cart") { orderWithInstacart() }
                            .disabled(unchecked.isEmpty || openingInstacart)
                    }
                } label: {
                    Image(systemName: "ellipsis").foregroundStyle(Color.ink).plTapTarget()
                }
                .accessibilityLabel("Shopping and export options")
    }

    private func compactUtilityLabel(title: String, symbol: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .plType(.caption, .bold)
                .plActionLabel(0.72)
        }
        .foregroundStyle(Color.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .background(Color.canvas, in: Radius.shape(Radius.chip))
        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
        .contentShape(Radius.shape(Radius.chip))
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
            TextField("Add an item or amount", text: $newItemName)
                .plType(.body)
                .focused($addFieldFocused)
                .submitLabel(.done)
                .onSubmit(addManualItem)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .overlay {
            RoundedRectangle(cornerRadius: Radius.chip, style: .continuous)
                .strokeBorder(Color.hairline, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { addFieldFocused = true }
        .padding(.top, 4)
    }

    private func addManualItem() {
        let line = newItemName.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { return }
        let parsed = RecipeImporter.parseIngredientLine(line)
        let name = parsed.name.isEmpty ? line : parsed.name
        // A line arriving on the list is something landing. This fired the
        // chrome tap while remove() fired the landing buzz, which is the
        // vocabulary exactly backwards.
        Haptic.plate()
        withAnimation(.plSnap) {
            context.insert(GroceryItem(
                name: name,
                quantity: parsed.quantity,
                unit: parsed.unit,
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
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Color.hairlineSoft.frame(height: 0.5) }
        }
        .contextMenu {
            if !item.sources.isEmpty {
                Button("Meal details", systemImage: "info.circle") { sourceShown = item }
            }
            Button("Remove item", systemImage: "trash", role: .destructive) { remove(item) }
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
        swipedItem = nil
        item.isDismissed = true
        guard Persist.save(context, "remove grocery") else {
            item.isDismissed = false
            removalProblem = "Your item is still on the list. Please try again."
            return
        }
        item.recordMark()
        undoRemoval = item
    }

    private func restore(_ item: GroceryItem) {
        item.isDismissed = false
        guard Persist.save(context, "restore grocery") else {
            item.isDismissed = true
            removalProblem = "Your item could not be restored. Please try again."
            return
        }
        item.recordMark()
        undoRemoval = nil
    }

    private func checkRow(_ item: GroceryItem) -> some View {
        let isChecked = checked(item)
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        let measure = GroceryMeasure.shopping(isChecked ? selectedQuantity(item) : needed(item), item.unit).text
        return layout {
            Button {
                Haptic.select()
                undoCheck = (item, item.purchasesData, item.isChecked)
                withAnimation(.plSnap) { item.setPurchased(!isChecked, for: selectedIDs) }
                Persist.save(context)
                exportResult = nil
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 21, weight: .regular))
                        .foregroundStyle(isChecked ? Color.basil : Color.inkSecondary)
                        .contentTransition(.symbolEffect(.replace))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.name).plType(.body, .medium)
                            .strikethrough(isChecked).foregroundStyle(isChecked ? Color.inkSecondary : Color.ink)
                        if let origin = groceryOriginLine(item) {
                            Text(origin)
                                .plType(.caption).foregroundStyle(Color.inkSecondary).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                        if typeSize.isAccessibilitySize {
                            Text(measure).plType(.footnote, .semibold).foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let hint = packageHint(item) {
                            Text(hint)
                                .plType(.caption, .semibold)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if !typeSize.isAccessibilitySize {
                        Spacer(minLength: 6)
                        Text(measure).plType(.footnote, .semibold).foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }.frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.name + ", " + GroceryMeasure.shopping(selectedQuantity(item), item.unit).text)
            .accessibilityValue(isChecked ? "Purchased" : "To buy")
            .accessibilityActions {
                if !item.sources.isEmpty {
                    Button("Meals that need " + item.name) { sourceShown = item }
                }
            }

        }
    }

    private func selectedQuantity(_ item: GroceryItem) -> Double {
        item.sources.isEmpty ? item.quantity : item.sources.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }.reduce(0) { $0 + $1.quantity }
    }

    private func packageFor(_ item: GroceryItem) -> IngredientPackage? {
        let sources = item.sources.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }
        guard !sources.isEmpty,
              let package = sources.first?.package,
              sources.allSatisfy({ $0.package == package }) else { return nil }
        return package
    }

    private func packageHint(_ item: GroceryItem) -> String? {
        guard let package = packageFor(item),
              let size = package.size, size > 0 else { return nil }
        let need = GroceryMeasure.canonical(needed(item), item.unit)
        let pack = GroceryMeasure.canonical(size, package.unit)
        guard need.unit == pack.unit, pack.quantity > 0 else { return nil }
        let count = max(1, Int(ceil(need.quantity / pack.quantity - 0.000001)))
        return "Buy \(count) \(count == 1 ? "pack" : "packs") · \(Ingredient.format(size)) \(package.unit) each"
    }

    private func groceryOriginLine(_ item: GroceryItem) -> String? {
        let selected = item.sources.filter { selectedIDs == nil || selectedIDs!.contains($0.id) }
        if !selected.isEmpty {
            return selected.map {
                $0.date.formatted(.dateTime.weekday(.abbreviated)) + " · " + $0.title
            }.joined(separator: " · ")
        }
        guard !item.originTitle.isEmpty else { return nil }
        return "From \(item.originTitle)"
    }

    private func orderWithInstacart() {
        // Dead "Review products and checkout in Instacart." is worse than
        // no button: the partner path is not configured, so this must not
        // run even if a future caller shows the pill.
        guard InstacartService.isOffered, !openingInstacart, !unchecked.isEmpty else { return }
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
            if !shoppingOptionsExpanded {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { shoppingOptionsExpanded = true }
                } label: {
                    let layout = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                        : AnyLayout(HStackLayout(spacing: 12))
                    layout {
                        Text(shoppingRangeText + " · " + (byMeal ? "Selected meals" : "Next 7 days"))
                            .plType(.footnote).foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Change").plType(.footnote, .semibold).foregroundStyle(Color.accentText)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Shopping window, \(shoppingRangeText), change options")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                MicroLabel("Shopping window")
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { datePickerShown.toggle() }
                } label: {
                    Group {
                        if typeSize >= .accessibility1 {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(Color.accentText)
                                    Text(shoppingRangeText)
                                        .plType(.body, .semibold)
                                        .foregroundStyle(Color.ink)
                                    Spacer(minLength: 6)
                                    Text(datePickerShown ? "Done" : "Change")
                                        .plType(.footnote, .bold)
                                        .plActionLabel()
                                        .foregroundStyle(Color.ink)
                                }
                                Text(byMeal ? "Pick from meals in this range" : "Everything planned in this range")
                                    .plType(.caption)
                                    .foregroundStyle(Color.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.accentText)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shoppingRangeText)
                                        .plType(.body, .semibold)
                                        .foregroundStyle(Color.ink)
                                    Text(byMeal ? "Pick from meals in this range" : "Everything planned in this range")
                                        .plType(.caption)
                                        .foregroundStyle(Color.inkSecondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Text(datePickerShown ? "Done" : "Change")
                                    .plType(.footnote, .bold)
                                    .plActionLabel()
                                    .foregroundStyle(Color.ink)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Shopping dates, \(shoppingRangeText)")

                if datePickerShown {
                    DatePicker("Start date", selection: $shoppingStart, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Color.accentText)
                        .transition(.plUnfold)
                }

                Divider().overlay(Color.hairline)

                groceryScopePicker

                Divider().overlay(Color.hairline)

                if typeSize >= .accessibility1 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 12) {
                            Text("Include pantry staples")
                                .plType(.body, .semibold)
                                .foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Toggle("Include pantry staples", isOn: $includePantryStaples)
                                .labelsHidden()
                                .tint(Color.completion)
                        }
                        Text("Review things recipes mark as usually on hand")
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Toggle(isOn: $includePantryStaples) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Include pantry staples")
                                .plType(.body, .semibold)
                                .foregroundStyle(Color.ink)
                            Text("Review things recipes mark as usually on hand")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .layoutPriority(1)
                    }
                    .tint(Color.completion)
                    .frame(minHeight: 44)
                }
                }
                .padding(14)
                .background(Color.cardFill, in: Radius.shape(Radius.card))
                .overlay(Radius.shape(Radius.card).strokeBorder(Color.hairlineSoft))

                if shoppingOptionsExpanded {
                    Button("Done editing shopping options") {
                        Haptic.tap()
                        withAnimation(.plSnap) {
                            datePickerShown = false
                            shoppingOptionsExpanded = false
                        }
                    }
                    .plType(.footnote, .bold)
                    .plActionLabel()
                    .foregroundStyle(Color.accentText)
                    .plTapTarget()
                }
            }

            if shoppingOptionsExpanded {
            Button {
                aisleOrderDraft = aisleOrder
                aisleOrderShown = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease")
                    Text("Customize aisle order")
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkSecondary)
                }
                .plType(.footnote, .semibold)
                .foregroundStyle(Color.accentText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityHint("Change the order of grocery aisles in your list")

            if byMeal {
                Button { mealPickerShown = true } label: { // design-ok(action-wrap): disclosure row keeps its explanatory caption multiline
                    HStack(spacing: 12) {
                        Image(systemName: "fork.knife").font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(selectedMeals.isEmpty ? "Choose meals" : "\(selectedMeals.count) \(selectedMeals.count == 1 ? "meal" : "meals") selected").plType(.body, .semibold)
                            Text("Choose any meals in \(shoppingRangeText).").plType(.caption).foregroundStyle(Color.inkSecondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "checklist")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.accentText)
                            .frame(width: 34, height: 34)
                            .background(Color.olive.opacity(0.10), in: Circle())
                    }.padding(16).background(Color.fill, in: Radius.shape(Radius.chip)).contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityIdentifier("grocery-meal-selector")
            }
            if !currentItems.isEmpty {
                HStack {
                    Text("\(currentItems.count - unchecked.count) of \(currentItems.count) checked")
                    Spacer()
                    Text("\(mealChoices.count) planned \(mealChoices.count.word("meal"))")
                }.plType(.caption).foregroundStyle(Color.inkSecondary)
                GeometryReader { g in
                    Capsule().fill(Color.fill)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.completion).frame(width: g.size.width * CGFloat(currentItems.count - unchecked.count) / CGFloat(currentItems.count))
                        }
                }.frame(height: 3).animation(.plSnap, value: unchecked.count)
            }
                DisclosureGroup("Prices and budget") { estimateCard }
                    .plType(.footnote)
            }
        }.foregroundStyle(Color.ink).padding(.horizontal, Spacing.page).padding(.top, shortWindow ? 4 : 16)
    }

    private var groceryScopePicker: some View {
        EditorialSegments(options: [false, true], selection: $byMeal,
                          label: { $0 ? "Pick meals" : "Next 7 days" }, stacked: typeSize.isAccessibilitySize)
            .accessibilityElement(children: .contain)
    }

    private var aisleOrderEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Aisle order").plType(.title, .semibold).foregroundStyle(Color.ink)
            Text("Arrange aisles to match the way you shop. This order is saved on this device.")
                .plType(.footnote).foregroundStyle(Color.inkSecondary)
            ForEach(Array(aisleOrderDraft.enumerated()), id: \.element) { index, aisle in
                HStack(spacing: 12) {
                    Image(systemName: aisle.symbolName)
                        .foregroundStyle(Color.accentText)
                        .frame(width: 24)
                    Text(aisle.rawValue).plType(.body, .semibold).foregroundStyle(Color.ink)
                    Spacer()
                    Button {
                        guard index > 0 else { return }
                        Haptic.tap()
                        aisleOrderDraft.swapAt(index, index - 1)
                    } label: {
                        Image(systemName: "arrow.up")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Move \(aisle.rawValue) up")
                    Button {
                        guard index < aisleOrderDraft.count - 1 else { return }
                        Haptic.tap()
                        aisleOrderDraft.swapAt(index, index + 1)
                    } label: {
                        Image(systemName: "arrow.down")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .disabled(index == aisleOrderDraft.count - 1)
                    .accessibilityLabel("Move \(aisle.rawValue) down")
                }
                .plType(.body)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, 8)
                .background(Color.fill, in: Radius.shape(Radius.chip))
            }
            HStack {
                Button("Reset") { aisleOrderDraft = GroceryAisle.allCases }
                    .plTapTarget()
                Spacer()
                Button("Done") {
                    aisleOrderRaw = aisleOrderDraft.map(\.rawValue).joined(separator: "|")
                    aisleOrderShown = false
                }
                .fontWeight(.semibold)
                .plTapTarget()
            }
            .foregroundStyle(Color.accentText)
        }
        .padding(24)
        .plFitsOrScrolls()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch build {
        case .building:
            // Still asking. A spinner, no words: a sentence here would be
            // a claim the app cannot make yet.
            ProgressView().tint(Color.inkSecondary)
        case .failed:
            VStack(spacing: 8) {
                Image(systemName: "basket")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                Text("Couldn't build the list")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The week is still there. This is just the list.")
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { rebuild() }
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.accentText)
                    .plTapTarget()
                    .padding(.top, 2)
            }
        case .built:
            VStack(spacing: 8) {
                Image(systemName: "basket")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.inkFaint)
                Text(byMeal && selectedMeals.isEmpty ? "Choose meals to shop for" : hasPlannedNights ? "No ingredients to buy" : "Nothing to shop for yet")
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(byMeal && selectedMeals.isEmpty ? "Select one or more meals above to build your list." : hasPlannedNights
                     ? (includePantryStaples
                        ? "There are no ingredients to buy from these recipes."
                        : "There are no ingredients to buy from these recipes. Pantry staples are hidden above.")
                     : "Plan a few nights and the list builds itself.")
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                // Manual lines remain available when the generated list is
                // empty — often the exact moment somebody needs one.
                addRow
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, typeSize >= .accessibility1 ? 0 : 40)
                    .padding(.top, 10)
            }
        }
    }

    private var shoppingRangeText: String {
        let start = shoppingStart.startOfDay
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let calendar = Calendar.current
        if calendar.component(.year, from: start) == calendar.component(.year, from: end),
           calendar.component(.month, from: start) == calendar.component(.month, from: end) {
            return start.formatted(.dateTime.month(.abbreviated).day())
                + "–"
                + end.formatted(.dateTime.day())
        }
        return start.formatted(.dateTime.month(.abbreviated).day())
            + "–"
            + end.formatted(.dateTime.month(.abbreviated).day())
    }

    private var mealSelector: some View {
        NavigationStack {
            ScrollView {
                if mealChoices.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "calendar.badge.plus")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color.inkFaint)
                        Text("No meals in this range")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Text("Plan a night first, then come back to shop for just that meal.")
                            .plType(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open Plan") {
                            openPlanFromEmptyPicker()
                        }
                        .plType(.body, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.onPrimary)
                        .padding(.horizontal, 22)
                        .frame(minHeight: 44)
                        .background(Color.primaryAction, in: Radius.shape(Radius.chip))
                        .buttonStyle(.pressable)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 36)
                    .padding(.top, 72)
                } else {
                    VStack(spacing: 0) {
                        ForEach(mealChoices) { choice in
                            Button {
                                Haptic.select()
                                if selectedMeals.contains(choice.id) { selectedMeals.remove(choice.id) }
                                else { selectedMeals.insert(choice.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    RecipeArtwork(
                                        data: artwork(for: choice), title: choice.title,
                                        ratio: 1, radius: Radius.small
                                    )
                                    .frame(width: 56)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(choice.title).plType(.body, .semibold).foregroundStyle(Color.ink)
                                        Text(choiceLine(choice))
                                            .plType(.caption).foregroundStyle(Color.inkSecondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: selectedMeals.contains(choice.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 24)).foregroundStyle(selectedMeals.contains(choice.id) ? Color.completion : Color.inkSecondary)
                                }.padding(.vertical, 14).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedMeals.contains(choice.id) ? .isSelected : [])
                            Divider()
                        }
                        if hasManualItemsInWindow {
                            Toggle("Include extra items", isOn: $includeExtras)
                                .plType(.body)
                                .tint(Color.completion)
                                .padding(.vertical, 20)
                        }
                    }.padding(.horizontal, Spacing.page)
                }
            }.background(Color.canvas).navigationTitle("Pick meals").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { mealPickerShown = false } } }
        }.presentationDetents([.large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
    }

    /// A modal grocery list sits above Plan, so changing the selected tab
    /// alone leaves that sheet covering the destination and makes this CTA
    /// look inert. Close the picker, then the outer list when it has one,
    /// before handing the route back to the shell.
    private func openPlanFromEmptyPicker() {
        mealPickerShown = false
        Task { @MainActor in
            await Task.yield()
            if !embedded {
                dismiss()
                await Task.yield()
            }
            LinkRelay.open(DeepLink.url(.plan))
        }
    }

    private func rebuild() {
        do {
            try GroceryListBuilder(context: context).rebuild(
                weekOf: shoppingStart,
                includePantryStaples: includePantryStaples
            )
            build = .built
        } catch {
            // assertionFailure here was a crash under `make phone` and total
            // silence in TestFlight: the two worst answers, one per build
            // configuration.
            print("PLATED GROCERY: rebuild failed — \(error)")
            build = .failed
        }
    }

    private func reconcileMealSelection() {
        let available = Set(mealChoices.map(\.id))
        selectedMeals.formIntersection(available)
        if byMeal && selectedMeals.isEmpty, let first = mealChoices.first?.id {
            selectedMeals.insert(first)
        }
    }

    private func artwork(for choice: GroceryListBuilder.ShoppingChoice) -> Data? {
        if let record = choice.remoteRecordName {
            return PlanLedger.shared.photo(for: record)
        }
        return plannedMeals.first { $0.shoppingID == choice.id }?.recipe?.photoData
    }

    private func choiceLine(_ choice: GroceryListBuilder.ShoppingChoice) -> String {
        var parts = [
            choice.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
            "Serves \(choice.servings)"
        ]
        if choice.isRemote, !choice.authorName.isEmpty {
            parts.append("\(choice.authorName)'s plan")
        }
        return parts.joined(separator: " · ")
    }

    private var hasPlannedNights: Bool {
        let start = shoppingStart.startOfDay
        guard let end = Calendar.current.date(byAdding: .day, value: 7, to: start) else { return false }
        return GroceryListBuilder.hasPlan(
            meals: meals, remote: PlanLedger.shared.all,
            from: start, to: end
        )
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
