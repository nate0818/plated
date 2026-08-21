import SwiftUI
import SwiftData

/// The shopping list — aisle-grouped cards, a checkbox worth tapping, and a
/// one-tap export into Apple Reminders.
struct GroceryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryItem.name) private var allItems: [GroceryItem]

    @State private var weekAnchor = Date.now
    @State private var includePantryStaples = false
    @State private var newItemName = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isExporting = false
    @State private var cartExpanded = false

    private var weekStart: Date { Calendar.current.startOfWeek(for: weekAnchor) }

    private var items: [GroceryItem] {
        allItems.filter { Calendar.current.isSameDay($0.weekStart, weekStart) }
    }

    private var unchecked: [GroceryItem] { items.filter { !$0.isChecked } }
    private var checked: [GroceryItem] { items.filter(\.isChecked) }

    private var grouped: [(aisle: GroceryAisle, items: [GroceryItem])] {
        Dictionary(grouping: unchecked, by: \.aisleValue)
            .map { (aisle: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.aisle.sortOrder < $1.aisle.sortOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    addRow

                    if items.isEmpty {
                        emptyState
                    }

                    ForEach(grouped, id: \.aisle) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Eyebrow("\(group.aisle.rawValue) — \(group.items.count)")
                            VStack(spacing: 0) {
                                ForEach(Array(group.items.enumerated()), id: \.element.persistentModelID) { index, item in
                                    if index > 0 {
                                        Divider().overlay(Color.hairline).padding(.leading, 52)
                                    }
                                    GroceryRow(item: item) { toggle(item) }
                                        .contextMenu {
                                            Button("Delete", systemImage: "trash", role: .destructive) {
                                                withAnimation(.appSmooth) { context.delete(item) }
                                            }
                                        }
                                }
                            }
                            .cardSurface()
                            .overlay(alignment: .leading) {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: Radius.card,
                                    bottomLeadingRadius: Radius.card,
                                    style: .continuous
                                )
                                .fill(aisleTone(group.aisle))
                                .frame(width: 2)
                            }
                        }
                    }

                    if !checked.isEmpty {
                        inCartGroup
                    }

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Previous week", systemImage: "chevron.left") { shiftWeek(by: -1) }
                        Button("Next week", systemImage: "chevron.right") { shiftWeek(by: 1) }
                        Divider()
                        Button("Rebuild from meal plan", systemImage: "arrow.clockwise", action: rebuild)
                        Toggle("Include pantry staples", isOn: $includePantryStaples)
                        Button("Send to Reminders", systemImage: "square.and.arrow.up") {
                            Task { await exportToReminders() }
                        }
                        .disabled(isExporting || items.isEmpty)
                        Button("Clear checked items", systemImage: "trash", role: .destructive, action: clearChecked)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(Color.ink)
                    }
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .tint(.ink)
            .sensoryFeedback(.success, trigger: unchecked.isEmpty && !checked.isEmpty)
            .alert("Couldn't finish", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var header: some View {
        Masthead(
            eyebrow: "Week of \(weekStart.formatted(.dateTime.month(.wide).day()))",
            title: "Grocery"
        ) {
            if !items.isEmpty {
                HStack(spacing: 8) {
                    ProgressRing(progress: checkProgress, size: 40, tone: .successTone)
                    Text("\(checked.count) OF \(items.count)")
                        .font(.caption.weight(.semibold))
                        .fontWidth(.condensed)
                        .monospacedDigit()
                        .foregroundStyle(Color.inkSecondary)
                        .contentTransition(.numericText(value: Double(checked.count)))
                }
            }
        }
        .padding(.top, 8)
        .contentShape(.rect)
        .simultaneousGesture(
            DragGesture(minimumDistance: 30).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                shiftWeek(by: value.translation.width < 0 ? 1 : -1)
            }
        )
    }

    private var addRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.inkTertiary)
            TextField("Add an item", text: $newItemName)
                .font(.body)
                .foregroundStyle(Color.ink)
                .onSubmit(addManualItem)
            if !newItemName.trimmingCharacters(in: .whitespaces).isEmpty {
                Button("Add", action: addManualItem)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tomato)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing on the list yet.")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            Text("Build it from this week's planned meals — quantities scale to your servings and duplicates merge.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            Button("Build from meal plan", action: rebuild)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.tomato)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.hero, style: .continuous)
                .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        )
    }

    private var inCartGroup: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(.appSmooth) { cartExpanded.toggle() }
            } label: {
                HStack {
                    Text("IN CART (\(checked.count))")
                        .font(.caption.weight(.semibold))
                        .fontWidth(.condensed)
                        .tracking(1.5)
                        .foregroundStyle(Color.inkWellText.opacity(0.7))
                        .contentTransition(.numericText(value: Double(checked.count)))
                    Spacer()
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if cartExpanded {
                VStack(spacing: 0) {
                    ForEach(checked) { item in
                        HStack(spacing: 12) {
                            PlateView(state: .cleared, diameter: 26)
                            Text(item.displayText)
                                .font(.body)
                                .foregroundStyle(Color.inkWellText.opacity(0.55))
                                .strikethrough(true, color: .inkWellText.opacity(0.35))
                                .lineLimit(1)
                            Spacer()
                        }
                        .frame(height: 44)
                        .contentShape(.rect)
                        .onTapGesture { toggle(item) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.inkWell)
        .padding(.horizontal, -20)
        .padding(.top, 8)
    }

    private func aisleTone(_ aisle: GroceryAisle) -> Color {
        switch aisle {
        case .produce: return .basil
        case .meat: return .mulledWine
        case .dairy, .bakery: return .honey
        default: return .copper
        }
    }

    private var checkProgress: Double {
        items.isEmpty ? 0 : Double(checked.count) / Double(items.count)
    }

    // MARK: - Actions

    private func toggle(_ item: GroceryItem) {
        withAnimation(.appBouncy) {
            item.isChecked.toggle()
        }
    }

    private func rebuild() {
        do {
            let created = try GroceryListBuilder(context: context)
                .rebuild(weekOf: weekStart, includePantryStaples: includePantryStaples)
            withAnimation(.appSmooth) {
                statusMessage = "Built \(created.count) item\(created.count == 1 ? "" : "s") from this week's meals."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportToReminders() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let count = try await RemindersExporter.shared.export(items)
            statusMessage = "Sent \(count) item\(count == 1 ? "" : "s") to Reminders."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addManualItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        withAnimation(.appSmooth) {
            context.insert(GroceryItem(name: name, weekStart: weekStart, isManual: true))
        }
        newItemName = ""
    }

    private func clearChecked() {
        withAnimation(.appSmooth) {
            for item in checked { context.delete(item) }
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekAnchor) else { return }
        withAnimation(.appSmooth) { weekAnchor = next }
    }
}

// MARK: - Row + the signature checkbox

private struct GroceryRow: View {
    let item: GroceryItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    PlateView(state: .empty, diameter: 26)
                    Circle()
                        .fill(Color.successTone)
                        .scaleEffect(item.isChecked ? 0.999 : 0.001)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .opacity(item.isChecked ? 1 : 0)
                        .scaleEffect(item.isChecked ? 1 : 0.4)
                }
                .frame(width: 26, height: 26)
                .animation(.appBouncy, value: item.isChecked)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.displayText)
                        .font(.body)
                        .foregroundStyle(item.isChecked ? Color.inkTertiary : Color.ink)
                        .strikethrough(item.isChecked, color: .inkTertiary)
                        .lineLimit(1)
                    if !item.originTitle.isEmpty {
                        HStack(spacing: 5) {
                            DishView(title: item.originTitle, diameter: 14)
                            Text(item.originTitle.uppercased())
                                .font(.system(size: 10, weight: .semibold))
                                .fontWidth(.condensed)
                                .tracking(0.5)
                                .foregroundStyle(Color.inkTertiary)
                        }
                    }
                }

                Spacer()

                if item.isManual {
                    Image(systemName: "hand.draw")
                        .font(.caption2)
                        .foregroundStyle(Color.inkTertiary)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: item.isChecked)
    }
}

#Preview {
    GroceryListView()
        .modelContainer(SampleData.previewContainer)
}
