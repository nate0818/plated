import SwiftUI
import SwiftData
import PhotosUI

/// Bring a recipe in from wherever it lives — a chat window, a website, a
/// card in a shoebox — and keep it.
///
/// Three states in one sheet: bring it in, reading, review. An import that
/// navigates away from the source makes a bad parse impossible to diagnose,
/// so the source text stays put behind the review and a scan writes what it
/// read back into the box. The review step is not a formality and is not
/// read-only: the cook fixes the name and the list HERE, before anything
/// reaches the cookbook, because the alternative — save it wrong, then go
/// hunting through the editor — is the clunky path this screen exists to
/// avoid.
struct RecipeImportSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var raw = ""
    @State private var draft: ImportedRecipe?
    @State private var reading = false
    @State private var readFailed = false
    @State private var nothingToPaste = false
    @State private var scannerShown = false
    @State private var editorShown = false
    /// Set by the editor before it closes, so the import sheet can leave
    /// with it instead of reappearing behind a finished recipe.
    @State private var savedInEditor = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var editing: Bool
    @FocusState private var namingDish: Bool

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel(draft == nil ? "To your cookbook" : "New recipe")
                Text(draft == nil ? "Add a recipe" : "Does this look right?")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 14)

            if draft != nil {
                review
            } else {
                intake
            }
        }
        .background(Color.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.canvas)
        .presentationCornerRadius(Radius.sheet)
        .fullScreenCover(isPresented: $scannerShown) {
            DocumentScanner(
                onScan: { pages in
                    scannerShown = false
                    scan(pages)
                },
                onCancel: { scannerShown = false }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $editorShown, onDismiss: {
            if savedInEditor { dismiss() }
        }) {
            RecipeEditorView { _ in savedInEditor = true }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    scan([image])
                }
                photoItem = nil
            }
        }
    }

    // MARK: Bring it in

    private var intake: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topLeading) {
                if raw.isEmpty {
                    // The promise this makes is now one the parser keeps:
                    // headed sections are read as sections, and "Notes",
                    // "Nutrition" and the story are dropped on the floor.
                    Text("Paste the whole thing. We'll keep the recipe and drop the rest.")
                        .plType(.body, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $raw)
                    .plType(.body, .medium)
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($editing)
            }
            .frame(maxHeight: .infinity)
            // The fill IS the well. A `hairline` border on a `fill` ground
            // measures 1.05:1, so this drew a stroke nobody has ever seen
            // and the rounded rectangle was already being described twice.
            .background(Color.fill, in: Radius.shape(Radius.card))

            if nothingToPaste {
                Text("Nothing on the clipboard. Copy the recipe first.")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
            }

            if readFailed {
                Text("No recipe found. Check that the ingredients and steps are included.")
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.tomato)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                ghostButton("Paste", icon: "doc.on.clipboard") {
                    // An empty clipboard used to be indistinguishable from a
                    // broken button: the tap did nothing and said nothing.
                    if let s = UIPasteboard.general.string,
                       !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        raw = s
                        nothingToPaste = false
                    } else {
                        Haptic.warn()
                        withAnimation(.plSnap) { nothingToPaste = true }
                    }
                }
                if DocumentScanner.isAvailable {
                    ghostButton("Scan", icon: "doc.viewfinder") { scannerShown = true }
                }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ghostLabel("Choose photo", icon: "photo")
                }
                .buttonStyle(.pressable)
            }

            Button {
                Haptic.plate()
                editing = false
                read(raw)
            } label: {
                HStack(spacing: 8) {
                    if reading { ProgressView().tint(Color.onTomato) }
                    Text(reading ? "Reading…" : "Read it")
                        .plType(.body, .bold)
                }
                .foregroundStyle(Color.onTomato)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 48)
                .background(Color.tomato, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reading)
            .opacity(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

            // The last way in. It used to be its own row in the + menu,
            // sitting beside "Paste a recipe" — which asked people to pick
            // how they were adding a recipe before they'd picked adding
            // one. It belongs here, next to paste and scan and photo, as
            // one more way to fill the same cookbook.
            Button {
                Haptic.tap()
                editorShown = true
            } label: {
                Text("Write it out")
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)

            Text("Photos and scans are read on your phone. Nothing is uploaded.")
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
    }

    private func ghostButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            action()
        } label: {
            ghostLabel(title, icon: icon)
        }
        .buttonStyle(.pressable)
    }

    private func ghostLabel(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .plType(.footnote, .bold)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
        // After the overlay, not before: a stroked capsule is a hollow ring,
        // so without this the tap lands only where the letters are.
        .contentShape(Capsule())
    }

    // MARK: Review — editable, because the parse is a first draft

    @ViewBuilder
    private var review: some View {
        if let bound = Binding($draft) {
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        nameField(bound)

                        HStack(spacing: 0) {
                            CountBlock(value: "\(bound.wrappedValue.servings)", label: "Serves")
                            CountDivider()
                            CountBlock(value: "\(bound.wrappedValue.prepMinutes)", label: "Prep min")
                            CountDivider()
                            CountBlock(value: "\(bound.wrappedValue.cookMinutes)", label: "Cook min")
                        }

                        ingredientsBlock(bound)
                        stepsBlock(bound)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                HStack(spacing: 10) {
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) { draft = nil }
                    } label: {
                        Text("Start over")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    Button {
                        Haptic.kiss()
                        save(bound.wrappedValue)
                    } label: {
                        Text(unnamed ? "Name it to save" : "Save to cookbook")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.onTomato)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .background(Color.tomato, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(unnamed)
                    .opacity(unnamed ? 0.5 : 1)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var unnamed: Bool {
        (draft?.title ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The name, always editable and empty when we could not tell.
    ///
    /// An empty box that asks is the whole point. The parser used to hand
    /// back the first few sentences of the paste as the dish's name, which
    /// is worse than silence in both directions: it is wrong, and it looks
    /// deliberate enough that it is easy to save without noticing.
    private func nameField(_ draft: Binding<ImportedRecipe>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("Name")
            TextField("Name the dish", text: draft.title)
                .plType(.heading)
                .foregroundStyle(Color.ink)
                .focused($namingDish)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(unnamed ? Color.tomato : Color.hairline, lineWidth: unnamed ? 1.5 : 1)
                )
                .plTapToFocus(radius: Radius.card) { namingDish = true }
            if !draft.wrappedValue.summary.isEmpty {
                Text(draft.wrappedValue.summary)
                    .plType(.footnote)
                    .foregroundStyle(Color.inkSecondary)
            }
        }
    }

    private func ingredientsBlock(_ draft: Binding<ImportedRecipe>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(draft.wrappedValue.ingredients.isEmpty
                       ? "Ingredients"
                       : "\(draft.wrappedValue.ingredients.count) ingredients")
            VStack(spacing: 0) {
                ForEach(draft.wrappedValue.ingredients) { ingredient in
                    HStack(spacing: 10) {
                        Text(line(for: ingredient))
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.ink)
                        Spacer(minLength: 8)
                        removeButton("Remove \(ingredient.name)") {
                            draft.wrappedValue.ingredients.removeAll { $0.id == ingredient.id }
                        }
                    }
                    .padding(.vertical, 5)
                }
                IngredientEntryField { added in
                    draft.wrappedValue.ingredients.append(contentsOf: added)
                }
                .padding(.top, draft.wrappedValue.ingredients.isEmpty ? 0 : 8)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
        }
    }

    @ViewBuilder
    private func stepsBlock(_ draft: Binding<ImportedRecipe>) -> some View {
        if !draft.wrappedValue.steps.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                MicroLabel("\(draft.wrappedValue.steps.count) \(draft.wrappedValue.steps.count == 1 ? "step" : "steps")")
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(draft.wrappedValue.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 10) {
                            // Fixed-size first: a 16pt box broke "10"
                            // onto two lines, so every step past nine
                            // read as a stacked pair of digits.
                            Text("\(i + 1)")
                                .plType(.micro, .extraBold)
                                .foregroundStyle(Color.tomato)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 18, alignment: .leading)
                            Text(step)
                                .plType(.footnote)
                                .foregroundStyle(Color.ink)
                            Spacer(minLength: 8)
                            removeButton("Remove step \(i + 1)") {
                                guard draft.wrappedValue.steps.indices.contains(i) else { return }
                                draft.wrappedValue.steps.remove(at: i)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))
            }
        }
    }

    private func removeButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Image(systemName: "xmark")
                .accessibilityLabel(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.inkFaint)
                .frame(minWidth: 44, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func line(for ing: ImportedIngredient) -> String {
        Ingredient.line(quantity: ing.quantity, unit: ing.unit, name: ing.name)
    }

    // MARK: Work

    private func read(_ text: String) {
        reading = true
        readFailed = false
        Task {
            let parsed = await RecipeImporter.parse(text)
            reading = false
            if parsed.isEmpty {
                Haptic.warn()
                withAnimation(.plSnap) { readFailed = true }
            } else {
                withAnimation(.plSettle) { draft = parsed }
                // The parser leaves the name blank rather than guessing
                // wrong. Put the cursor where the one remaining question is.
                if parsed.title.isEmpty { namingDish = true }
            }
        }
    }

    /// Photographed pages → text → structure.
    ///
    /// The OCR result is written back into the paste box on the way through,
    /// so a misread card is visible and correctable rather than mysterious.
    private func scan(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        reading = true
        readFailed = false
        Task {
            let text = await RecipeScanner.read(pages)
            raw = text
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                reading = false
                Haptic.warn()
                withAnimation(.plSnap) { readFailed = true }
            } else {
                read(text)
            }
        }
    }

    private func save(_ r: ImportedRecipe) {
        let title = r.title.trimmingCharacters(in: .whitespaces)
        let recipe = Recipe(
            title: title.isEmpty ? "Untitled dish" : title,
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
        Persist.save(context)
        dismiss()
    }
}

/// One field that accepts one ingredient or twenty.
///
/// Shared by the import review and the recipe editor, because the thing a
/// cook naturally does — copy the whole ingredient list and paste it into
/// the ingredient box — has to work in both places. It used to work in
/// neither: the field took the entire block as a single ingredient with a
/// very long name, and the only way forward was to delete it and type the
/// list back in one line at a time.
struct IngredientEntryField: View {
    var onAdd: ([ImportedIngredient]) -> Void

    @State private var entry = ""
    @FocusState private var focused: Bool

    private var pieces: [String] {
        RecipeImporter.splitIngredientBlock(entry)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        HStack(spacing: 8) {
            TextField("Add one, or paste the whole list", text: $entry, axis: .vertical)
                .plType(.body, .medium)
                .lineLimit(1...6)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                .onSubmit(commit)
                .plTapToFocus { focused = true }

            // The count is the affordance: paste eight lines and the button
            // says 8, so what is about to happen is visible before it does.
            AddCircleButton(
                label: "Add ingredient",
                count: pieces.count,
                disabled: pieces.isEmpty,
                action: commit
            )
        }
    }

    private func commit() {
        let parsed = pieces.map(RecipeImporter.parseIngredientLine).filter { !$0.name.isEmpty }
        guard !parsed.isEmpty else { return }
        Haptic.tap()
        withAnimation(.plSnap) { onAdd(parsed) }
        entry = ""
    }
}
