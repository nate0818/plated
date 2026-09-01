import SwiftUI
import SwiftData

/// Paste a recipe in, see what we made of it, then keep it.
///
/// Three states in one sheet — paste, reading, review — because an import
/// that navigates away from what you pasted makes a bad parse impossible to
/// diagnose. The review step is not a formality: the cook approves the
/// structure before anything reaches the cookbook, so a misread heading
/// costs a tap, not a cleanup.
struct RecipeImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var raw = ""
    @State private var draft: ImportedRecipe?
    @State private var reading = false
    @State private var readFailed = false
    @FocusState private var editing: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel(draft == nil ? "From anywhere" : "Check it over")
                Text(draft == nil ? "Paste a recipe" : "Does this look right?")
                    .font(.gabarito(22, .semibold))
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            if let draft {
                review(draft)
            } else {
                paste
            }
        }
        .background(Color.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
    }

    // MARK: Paste

    private var paste: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topLeading) {
                if raw.isEmpty {
                    Text("Paste the whole thing — ingredients, method, the blogger's childhood story. We'll keep the recipe and drop the rest.")
                        .font(.jakarta(14, .medium))
                        .foregroundStyle(Color.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $raw)
                    .font(.jakarta(14, .medium))
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($editing)
            }
            .frame(maxHeight: .infinity)
            .background(Color.fill, in: RoundedRectangle(cornerRadius: Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))

            if readFailed {
                Text("That didn't look like a recipe. Check there are ingredients and steps in there.")
                    .font(.jakarta(12, .semibold))
                    .foregroundStyle(Color.tomato)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    if let s = UIPasteboard.general.string { raw = s }
                } label: {
                    Text("Paste")
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                }
                .buttonStyle(.pressable)

                Button {
                    Haptic.plate()
                    editing = false
                    read()
                } label: {
                    HStack(spacing: 8) {
                        if reading { ProgressView().tint(Color.onTomato) }
                        Text(reading ? "Reading" : "Format it")
                            .font(.jakarta(14, .bold))
                    }
                    .foregroundStyle(Color.onTomato)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(Color.tomato, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reading)
                .opacity(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    // MARK: Review

    private func review(_ r: ImportedRecipe) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.title.isEmpty ? "Untitled dish" : r.title)
                            .font(.gabarito(20, .semibold))
                            .foregroundStyle(Color.ink)
                        if !r.summary.isEmpty {
                            Text(r.summary)
                                .font(.jakarta(13, .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                    }

                    HStack(spacing: 0) {
                        CountBlock(value: "\(r.servings)", label: "Serves")
                        CountDivider()
                        CountBlock(value: "\(r.prepMinutes)", label: "Prep min")
                        CountDivider()
                        CountBlock(value: "\(r.cookMinutes)", label: "Cook min")
                    }

                    if !r.ingredients.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroLabel("\(r.ingredients.count) ingredients")
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(r.ingredients) { ing in
                                    Text(line(for: ing))
                                        .font(.jakarta(13, .semibold))
                                        .foregroundStyle(Color.ink)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                        }
                    }

                    if !r.steps.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            MicroLabel("\(r.steps.count) steps")
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(Array(r.steps.enumerated()), id: \.offset) { i, step in
                                    HStack(alignment: .top, spacing: 10) {
                                        Text("\(i + 1)")
                                            .font(.jakarta(12, .extraBold))
                                            .foregroundStyle(Color.tomato)
                                            .frame(width: 16, alignment: .leading)
                                        Text(step)
                                            .font(.jakarta(13, .medium))
                                            .foregroundStyle(Color.ink)
                                    }
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .overlay(RoundedRectangle(cornerRadius: Radius.card).strokeBorder(Color.hairline))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            HStack(spacing: 10) {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { self.draft = nil }
                } label: {
                    Text("Back")
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                }
                .buttonStyle(.pressable)

                Button {
                    Haptic.kiss()
                    save(r)
                } label: {
                    Text("Add to cookbook")
                        .font(.jakarta(14, .bold))
                        .foregroundStyle(Color.onTomato)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(Color.tomato, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    private func line(for ing: ImportedIngredient) -> String {
        var parts: [String] = []
        if ing.quantity > 0 {
            // 2, not 2.0 — and 0.5 stays 0.5 rather than becoming 1.
            let whole = ing.quantity.rounded() == ing.quantity
            parts.append(whole ? String(Int(ing.quantity)) : String(format: "%.2g", ing.quantity))
        }
        if !ing.unit.isEmpty { parts.append(ing.unit) }
        parts.append(ing.name)
        return parts.joined(separator: " ")
    }

    // MARK: Work

    private func read() {
        reading = true
        readFailed = false
        let text = raw
        Task {
            let parsed = await RecipeImporter.parse(text)
            reading = false
            if parsed.isEmpty {
                Haptic.warn()
                withAnimation(.plSnap) { readFailed = true }
            } else {
                withAnimation(.plSettle) { draft = parsed }
            }
        }
    }

    private func save(_ r: ImportedRecipe) {
        let recipe = Recipe(
            title: r.title.isEmpty ? "Untitled dish" : r.title,
            summary: r.summary,
            servings: r.servings,
            prepMinutes: r.prepMinutes,
            cookMinutes: r.cookMinutes
        )
        recipe.steps = r.steps
        context.insert(recipe)
        for (i, ing) in r.ingredients.enumerated() {
            let row = Ingredient(name: ing.name, quantity: ing.quantity, unit: ing.unit)
            row.aisle = ing.aisle
            row.sortIndex = i
            row.recipe = recipe
            context.insert(row)
        }
        try? context.save()
        dismiss()
    }
}
