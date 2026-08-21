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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Gatherings")
                        .font(.heroTitle)
                        .foregroundStyle(Color.ink)
                        .padding(.top, 8)

                    if gatherings.isEmpty {
                        emptyState
                    }

                    ForEach(gatherings) { gathering in
                        NavigationLink(value: gathering) {
                            GatheringCard(gathering: gathering)
                        }
                        .buttonStyle(PressableCardStyle())
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                withAnimation(.appSmooth) { context.delete(gathering) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .background(Color.canvas)
            .scrollIndicators(.hidden)
            .navigationDestination(for: Gathering.self) { GatheringDetailView(gathering: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add gathering", systemImage: "plus", action: addGathering)
                        .foregroundStyle(Color.ink)
                }
            }
            .toolbarBackground(Color.canvas, for: .navigationBar)
            .tint(.ink)
            .sheet(item: $editing) { gathering in
                NavigationStack {
                    GatheringEditorView(gathering: gathering)
                }
                .presentationCornerRadius(Radius.sheet)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cooking for a crowd?")
                .font(.cardTitle)
                .foregroundStyle(Color.ink)
            Text("Thanksgiving, a birthday, friends over Sunday — plan the menu here and put it on the calendar.")
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            Button("Plan a gathering", action: addGathering)
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

    private func addGathering() {
        let gathering = Gathering(
            title: "",
            startDate: Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
        )
        context.insert(gathering)
        editing = gathering
    }
}

private struct GatheringCard: View {
    let gathering: Gathering

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(gathering.startDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()), color: .mulledWine)
                Spacer()
                if gathering.isSyncedToCalendar {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.successTone)
                }
            }

            Text(gathering.title.isEmpty ? "Untitled gathering" : gathering.title)
                .font(.cardTitle)
                .foregroundStyle(Color.ink)

            HStack(spacing: 12) {
                Label(gathering.startDate.formatted(date: .omitted, time: .shortened), systemImage: "clock")
                if gathering.guestCount > 0 {
                    Label("\(gathering.guestCount) guests", systemImage: "person.2")
                }
                if !gathering.meals.isEmpty {
                    Label("\(gathering.meals.count) on the menu", systemImage: "fork.knife")
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface()
    }
}

struct GatheringDetailView: View {
    @Bindable var gathering: Gathering

    @State private var isEditing = false
    @State private var isSyncing = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(gathering.startDate.formatted(.dateTime.weekday(.wide).month(.wide).day()), color: .mulledWine)
                    Text(gathering.title.isEmpty ? "Gathering" : gathering.title)
                        .font(.screenTitle)
                        .foregroundStyle(Color.ink)
                    if !gathering.notes.isEmpty {
                        Text(gathering.notes)
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.top, 8)

                VStack(spacing: 0) {
                    detailRow("Starts", gathering.startDate.formatted(date: .abbreviated, time: .shortened))
                    Divider().overlay(Color.hairline).padding(.leading, 16)
                    detailRow("Ends", gathering.endDate.formatted(date: .abbreviated, time: .shortened))
                    if !gathering.location.isEmpty {
                        Divider().overlay(Color.hairline).padding(.leading, 16)
                        detailRow("Where", gathering.location)
                    }
                    Divider().overlay(Color.hairline).padding(.leading, 16)
                    detailRow("Cooking for", "\(gathering.guestCount)")
                }
                .cardSurface()

                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow("Menu")
                    if gathering.meals.isEmpty {
                        Text("Nothing on the menu yet. Assign planned meals to this gathering from the week plan.")
                            .font(.subheadline)
                            .foregroundStyle(Color.inkSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                                    .strokeBorder(Color.hairline, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                            )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(gathering.meals.enumerated()), id: \.element.persistentModelID) { index, meal in
                                if index > 0 { Divider().overlay(Color.hairline).padding(.leading, 16) }
                                HStack {
                                    Text(meal.title)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Color.ink)
                                    Spacer()
                                    SlotChip(slot: meal.slotValue)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                        .cardSurface()
                    }
                }

                Button {
                    Task { await syncToCalendar() }
                } label: {
                    Label(
                        gathering.isSyncedToCalendar ? "Update calendar event" : "Add to Calendar",
                        systemImage: "calendar.badge.plus"
                    )
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isSyncing)
                .padding(.top, 8)

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Color.canvas)
        .scrollIndicators(.hidden)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
                    .foregroundStyle(Color.ink)
            }
        }
        .toolbarBackground(Color.canvas, for: .navigationBar)
        .sheet(isPresented: $isEditing) {
            NavigationStack { GatheringEditorView(gathering: gathering) }
                .presentationCornerRadius(Radius.sheet)
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

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.inkSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Color.ink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func syncToCalendar() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            try await CalendarSync.shared.sync(gathering)
            withAnimation(.appSmooth) { statusMessage = "Synced to your calendar." }
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
                    .monospacedDigit()
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
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .tint(.tomato)
        .navigationTitle("Edit Gathering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundStyle(Color.tomato)
            }
        }
    }
}

#Preview {
    GatheringsView()
        .modelContainer(SampleData.previewContainer)
}
