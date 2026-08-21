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
                    Masthead(eyebrow: "The table", title: "Gatherings") {
                        if let next = gatherings.first(where: { $0.startDate >= .now }) {
                            Text("NEXT: \(next.startDate.formatted(.dateTime.weekday(.abbreviated)).uppercased())")
                                .font(.caption.weight(.semibold))
                                .fontWidth(.condensed)
                                .tracking(1)
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }
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
        VStack(spacing: 16) {
            PlateView(state: .empty, diameter: 120)
            Text("Feeding people is the whole point.")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Button("Plan a gathering", action: addGathering)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.tomato)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
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
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Text(gathering.startDate.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .fontWidth(.condensed)
                    .tracking(1.5)
                    .foregroundStyle(Color.inkSecondary)
                Text(gathering.startDate.formatted(.dateTime.day()))
                    .font(.system(size: 44, weight: .semibold, design: .serif))
                    .monospacedDigit()
                    .foregroundStyle(Color.ink)
            }
            .frame(width: 64)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(gathering.title.isEmpty ? "Untitled gathering" : gathering.title)
                        .font(.cardTitle)
                        .foregroundStyle(Color.ink)
                        .lineLimit(2)
                    Spacer()
                    if gathering.isSyncedToCalendar {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.caption)
                            .foregroundStyle(Color.successTone)
                    }
                }

                HStack(spacing: -12) {
                    ForEach(gathering.meals.prefix(4)) { meal in
                        if let recipe = meal.recipe {
                            DishView(recipe: recipe, diameter: 56)
                        } else {
                            DishView(title: meal.title, diameter: 56)
                        }
                    }
                    PlateView(state: .empty, diameter: 56)
                        .background(Circle().fill(Color.cardFill))
                }

                HStack(spacing: 8) {
                    if gathering.guestCount > 0 {
                        HStack(spacing: -6) {
                            ForEach(0..<min(gathering.guestCount, 5), id: \.self) { index in
                                let tone: Color = [.honey, .basil, .copper, .mulledWine][index % 4]
                                Circle()
                                    .fill(tone.wash(over: .cardFill))
                                    .overlay(Circle().strokeBorder(Color.cardFill, lineWidth: 1.5))
                                    .frame(width: 24, height: 24)
                            }
                        }
                        Text("\(gathering.guestCount) AT THE TABLE · \(gathering.startDate.formatted(date: .omitted, time: .shortened).uppercased())")
                            .font(.system(size: 10, weight: .semibold))
                            .fontWidth(.condensed)
                            .tracking(0.5)
                            .monospacedDigit()
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
            }
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
