import SwiftUI
import SwiftData
import PhotosUI

/// The + sheet. A recipe here is a photo you took, a name, three facts,
/// and a decision about who gets to see it. Ninety seconds, tops.
struct NewRecipeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @Query private var meals: [PlannedMeal]

    @State private var title = ""
    @State private var minutes = 25
    @State private var serves = 4
    @State private var visibility = "household"
    @State private var householdCanEdit = true
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoLoading = false

    private let minuteChoices = [15, 25, 40, 60, 90]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.jakarta(15, .bold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                Spacer()
                Text("New recipe")
                    .font(.gabarito(19, .extraBold))
                    .foregroundStyle(Color.ink)
                Spacer()
                Color.clear.frame(width: 48, height: 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    photoWell

                    TextField("Name the dish", text: $title)
                        .font(.gabarito(27, .extraBold))
                        .tracking(-0.5)
                        .foregroundStyle(Color.ink)
                        .tint(Color.tomato)
                        .padding(.bottom, 8)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color.hairline).frame(height: 2)
                        }

                    HStack(spacing: 8) {
                        Menu {
                            ForEach(minuteChoices, id: \.self) { choice in
                                Button("\(choice) min") { minutes = choice }
                            }
                        } label: {
                            factCard("Time", "\(minutes) min")
                        }
                        Menu {
                            ForEach(1...12, id: \.self) { count in
                                Button("\(count)") { serves = count }
                            }
                        } label: {
                            factCard("Serves", "\(serves)")
                        }
                        factCard("Effort", minutes < 30 ? "Easy" : (minutes < 60 ? "Weekend" : "Project"))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Who can see it")
                        visibilityPicker
                        HStack {
                            Text("Household can edit")
                                .font(.jakarta(14, .semibold))
                                .foregroundStyle(Color.ink)
                            Spacer()
                            Toggle("", isOn: $householdCanEdit)
                                .labelsHidden()
                                .tint(Color.basil)
                        }
                        .padding(.horizontal, 4)
                        .opacity(visibility == "private" ? 0.35 : 1)
                        .disabled(visibility == "private")
                        Text(editCaption)
                            .font(.jakarta(12, .medium))
                            .foregroundStyle(Color.inkFaint)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 20)
            }

            VStack(spacing: 10) {
                TomatoPillButton(title: "Save to cookbook", systemImage: "circle.circle") {
                    save(plating: nil)
                }
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
                if let night = nextOpenNight {
                    Button {
                        save(plating: night)
                    } label: {
                        Text("Save & plate it for \(nightLabel(night))")
                            .font(.jakarta(13, .semibold))
                            .foregroundStyle(Color.inkSecondary)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoLoading = true
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self) {
                    photoData = Self.processed(raw)
                }
                photoLoading = false
            }
        }
    }

    // MARK: Pieces

    private var photoWell: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                        .plCardShadow()
                        .overlay(alignment: .topLeading) {
                            Text("YOUR PHOTO")
                                .font(.jakarta(11, .extraBold))
                                .tracking(0.7)
                                .foregroundStyle(Color.ink)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(12)
                        }
                    HStack(spacing: 6) {
                        Image(systemName: "camera")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Retake")
                            .font(.jakarta(12, .bold))
                    }
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(12)
                } else {
                    RoundedRectangle(cornerRadius: Radius.hero)
                        .strokeBorder(Color.hairlineDashed, style: StrokeStyle(lineWidth: 2, dash: [8, 7]))
                        .frame(maxWidth: .infinity)
                        .frame(height: 240)
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "camera")
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(Color.inkFaint)
                                Text("Add a photo of the plate")
                                    .font(.jakarta(15, .bold))
                                    .foregroundStyle(Color.inkSecondary)
                                Text("Your photo, your dish — no stock food here.")
                                    .font(.jakarta(12, .medium))
                                    .foregroundStyle(Color.inkFaint)
                            }
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func factCard(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label.uppercased())
                .font(.jakarta(10, .extraBold))
                .tracking(0.6)
                .foregroundStyle(Color.inkFaint)
            Text(value)
                .font(.jakarta(15, .bold))
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
        .contentShape(Rectangle())
    }

    private var visibilityPicker: some View {
        HStack(spacing: 0) {
            visibilitySegment("private", label: "Just me", icon: "lock")
            visibilitySegment("household", label: "Household", icon: nil)
            visibilitySegment("table", label: "My Table", icon: nil)
        }
        .padding(2)
        .background(Color.hairlineSoft, in: Capsule())
    }

    private func visibilitySegment(_ value: String, label: String, icon: String?) -> some View {
        let active = visibility == value
        return Button {
            Haptic.tap()
            withAnimation(.plSnap) { visibility = value }
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 11, weight: .bold))
                }
                Text(label).font(.jakarta(13, .bold))
            }
            .foregroundStyle(active ? Color.ink : Color.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .contentShape(Capsule())
            .background {
                if active {
                    Capsule()
                        .fill(Color.raisedFill)
                        .overlay(Capsule().strokeBorder(Color.navHairline))
                        .shadow(color: Color.shadowWarm.opacity(0.12), radius: 4, y: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var editCaption: String {
        if visibility == "private" { return "Only you can see or change it." }
        let names = members.filter { !$0.isOwner }.map(\.name)
        guard householdCanEdit, !names.isEmpty else { return "Only you can change it." }
        let list = names.count > 1
            ? names.dropLast().joined(separator: ", ") + " and " + names.last!
            : names[0]
        return "\(list) can tweak it. Only you can delete it."
    }

    /// Saving waits for the photo to finish processing so a picked photo is
    /// never silently dropped.
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !photoLoading
    }

    private var nextOpenNight: Date? {
        let today = Calendar.current.startOfDay(for: .now)
        return (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: today) }
            .first { date in
                !meals.contains { Calendar.current.isSameDay($0.date, date) && $0.slotValue == .dinner }
            }
    }

    private func nightLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    // MARK: Save

    private func save(plating night: Date?) {
        Haptic.plate()
        let recipe = Recipe(
            title: title.trimmingCharacters(in: .whitespaces),
            servings: serves,
            prepMinutes: minutes / 2,
            cookMinutes: minutes - minutes / 2
        )
        recipe.visibility = visibility
        recipe.householdCanEdit = visibility == "private" ? false : householdCanEdit
        recipe.photoData = photoData
        context.insert(recipe)

        if let night {
            let cook = members.first { $0.cookWeekdays.contains(Calendar.current.component(.weekday, from: night)) }
                ?? members.first(where: \.isOwner)
            context.insert(PlannedMeal(
                date: night, slot: .dinner, recipe: recipe,
                servings: serves, cook: cook
            ))
        }
        dismiss()
    }

    /// Downscale to ~1200px and recompress — CloudKit charges by the byte.
    private static func processed(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let maxSide: CGFloat = 1200
        let scale = min(1, maxSide / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.75)
    }
}
