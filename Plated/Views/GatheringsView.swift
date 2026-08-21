import SwiftUI
import SwiftData

/// Larger events — holidays, birthdays, having people over. A gathering groups
/// several planned meals and mirrors into the system calendar.
struct GatheringsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Gathering.startDate) private var gatherings: [Gathering]

    @State private var editing: Gathering?

    var body: some View {
        NavigationStack {
            List {
                ForEach(gatherings) { gathering in
                    NavigationLink(value: gathering) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(gathering.title.isEmpty ? "Untitled gathering" : gathering.title)
                            HStack(spacing: 8) {
                                Text(gathering.startDate.formatted(date: .abbreviated, time: .shortened))
                                if gathering.guestCount > 0 {
                                    Label("\(gathering.guestCount)", systemImage: "person.2")
                                }
                                if gathering.isSyncedToCalendar {
                                    Image(systemName: "calendar.badge.checkmark")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(gatherings[index]) }
                }
            }
            .navigationTitle("Gatherings")
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .overlay {
                if gatherings.isEmpty {
                    ContentUnavailableView(
                        "No gatherings planned",
                        systemImage: "person.3",
                        description: Text("Thanksgiving, a birthday, friends coming over — plan the menu and put it on the calendar.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add gathering", systemImage: "plus", action: addGathering)
                }
            }
            .sheet(item: $editing) { gathering in
                NavigationStack {
                    GatheringEditorView(gathering: gathering)
                }
            }
        }
    }

    private func addGathering() {
        let gathering = Gathering(
            title: "",
            startDate: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        )
        context.insert(gathering)
        editing = gathering
    }
}

struct GatheringDetailView: View {
    @Bindable var gathering: Gathering

    @State private var isEditing = false
    @State private var isSyncing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("When") {
                LabeledContent("Starts", value: gathering.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Ends", value: gathering.endDate.formatted(date: .abbreviated, time: .shortened))
                if !gathering.location.isEmpty {
                    LabeledContent("Where", value: gathering.location)
                }
                LabeledContent("Cooking for", value: "\(gathering.guestCount)")
            }

            if !gathering.notes.isEmpty {
                Section("Notes") { Text(gathering.notes) }
            }

            Section("Menu") {
                if gathering.meals.isEmpty {
                    Text("Nothing on the menu yet. Assign planned meals to this gathering from the week plan.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(gathering.meals) { meal in
                        HStack {
                            Label(meal.title, systemImage: meal.slotValue.symbolName)
                            Spacer()
                            Text("\(meal.servings)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                Button {
                    Task { await syncToCalendar() }
                } label: {
                    Label(
                        gathering.isSyncedToCalendar ? "Update calendar event" : "Add to Calendar",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .disabled(isSyncing)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(gathering.title.isEmpty ? "Gathering" : gathering.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            NavigationStack { GatheringEditorView(gathering: gathering) }
        }
        .alert("Couldn't sync", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func syncToCalendar() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await CalendarSync.shared.sync(gathering)
            statusMessage = "Synced to your calendar."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct GatheringEditorView: View {
    @Bindable var gathering: Gathering
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Title", text: $gathering.title)
                TextField("Location", text: $gathering.location)
                Stepper("Cooking for \(gathering.guestCount)", value: $gathering.guestCount, in: 0...200)
            }
            Section("When") {
                DatePicker("Starts", selection: $gathering.startDate)
                DatePicker("Ends", selection: $gathering.endDate)
            }
            Section("Notes") {
                TextField("Anything to remember", text: $gathering.notes, axis: .vertical)
                    .lineLimit(3...10)
            }
        }
        .navigationTitle("Edit Gathering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

#Preview {
    GatheringsView()
        .modelContainer(SampleData.previewContainer)
}
