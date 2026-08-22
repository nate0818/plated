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

    private var currentItems: [GroceryItem] {
        let windowStart = Calendar.current.startOfDay(for: .now)
        // Manual lines keep the window key of the day they were typed; give
        // them a week of life so they don't vanish as the window rolls.
        let manualHorizon = Calendar.current.date(byAdding: .day, value: -7, to: windowStart) ?? windowStart
        return items.filter {
            $0.isManual
                ? $0.weekStart >= manualHorizon
                : Calendar.current.isSameDay($0.weekStart, windowStart)
        }
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
                Text("Grocery")
                    .font(.gabarito(22, .extraBold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)

            if currentItems.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "basket")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Color.inkFaint)
                        .plBreathing()
                    Text("Nothing to shop for yet")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                    Text("Plate a few nights and the list builds itself.")
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
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 16)
                }

                VStack(spacing: 8) {
                    TomatoPillButton(title: exporting ? "Sending…" : "Send to Reminders", systemImage: "checklist") {
                        exportToReminders()
                    }
                    Button {
                        orderWithInstacart()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "cart")
                                .font(.system(size: 15, weight: .semibold))
                            Text("Order with Instacart")
                                .font(.jakarta(15, .bold))
                        }
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)
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

    private func itemRow(_ item: GroceryItem) -> some View {
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
                        // The check lands like a pen stroke, not a repaint.
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Color.canvas)
                            .transition(.scale(scale: 0.4).combined(with: .opacity))
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
        if !item.unit.isEmpty { parts.append(item.unit) }
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
        exportResult = "List copied — paste items into your Instacart cart"
        Notifier.post(
            .groceriesOrdered, actor: "",
            body: "A delivery run started — \(unchecked.count) items headed to Instacart.",
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
                withAnimation(.plSnap) { exportResult = "\(count) items sent to Reminders" }
                Haptic.kiss()
            } catch {
                withAnimation(.plSnap) { exportResult = "Reminders access is off in Settings" }
                Haptic.warn()
            }
            exporting = false
        }
    }
}
