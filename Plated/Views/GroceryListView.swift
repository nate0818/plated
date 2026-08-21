import SwiftUI
import SwiftData

/// The shopping list for one week, grouped by store aisle, with a one-tap
/// export into Apple Reminders.
struct GroceryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \GroceryItem.name) private var allItems: [GroceryItem]

    @State private var weekAnchor = Date.now
    @State private var includePantryStaples = false
    @State private var newItemName = ""
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isExporting = false

    private var weekStart: Date { Calendar.current.startOfWeek(for: weekAnchor) }

    private var items: [GroceryItem] {
        allItems.filter { Calendar.current.isSameDay($0.weekStart, weekStart) }
    }

    private var grouped: [(aisle: GroceryAisle, items: [GroceryItem])] {
        Dictionary(grouping: items, by: \.aisleValue)
            .map { (aisle: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.aisle.sortOrder < $1.aisle.sortOrder }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        TextField("Add an item", text: $newItemName)
                        Button("Add") { addManualItem() }
                            .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    Toggle("Include pantry staples", isOn: $includePantryStaples)
                }

                ForEach(grouped, id: \.aisle) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                item.isChecked.toggle()
                            } label: {
                                HStack {
                                    Image(systemName: item.isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.isChecked ? Color.accentColor : Color.secondary)
                                    Text(item.displayText)
                                        .strikethrough(item.isChecked, color: .secondary)
                                        .foregroundStyle(item.isChecked ? .secondary : .primary)
                                    Spacer()
                                    if item.isManual {
                                        Image(systemName: "hand.draw")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(group.items[index]) }
                        }
                    } header: {
                        Label(group.aisle.rawValue, systemImage: group.aisle.symbolName)
                    }
                }
            }
            .navigationTitle("Grocery")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView(
                        "Nothing on the list",
                        systemImage: "cart",
                        description: Text("Build the list from this week's planned meals.")
                    )
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button("Previous week", systemImage: "chevron.left") { shiftWeek(by: -1) }
                    Button("Next week", systemImage: "chevron.right") { shiftWeek(by: 1) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Rebuild from meal plan", systemImage: "arrow.clockwise", action: rebuild)
                        Button("Send to Reminders", systemImage: "square.and.arrow.up") {
                            Task { await exportToReminders() }
                        }
                        .disabled(isExporting || items.isEmpty)
                        Button("Clear checked items", systemImage: "trash", role: .destructive, action: clearChecked)
                    } label: {
                        Label("Actions", systemImage: "ellipsis.circle")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(.thinMaterial)
                }
            }
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

    private func rebuild() {
        do {
            let created = try GroceryListBuilder(context: context)
                .rebuild(weekOf: weekStart, includePantryStaples: includePantryStaples)
            statusMessage = "Built \(created.count) item\(created.count == 1 ? "" : "s") from this week's meals."
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
        let item = GroceryItem(
            name: newItemName.trimmingCharacters(in: .whitespaces),
            weekStart: weekStart,
            isManual: true
        )
        context.insert(item)
        newItemName = ""
    }

    private func clearChecked() {
        for item in items where item.isChecked {
            context.delete(item)
        }
    }

    private func shiftWeek(by delta: Int) {
        guard let next = Calendar.current.date(byAdding: .weekOfYear, value: delta, to: weekAnchor) else { return }
        weekAnchor = next
    }
}

#Preview {
    GroceryListView()
        .modelContainer(SampleData.previewContainer)
}
