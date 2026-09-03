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
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var raw = ""
    @State private var draft: ImportedRecipe?
    @State private var reading = false
    /// Why the read did not produce a recipe.
    ///
    /// One Bool used to answer three different questions with one sentence.
    /// "No recipe found. Check that the ingredients and steps are included."
    /// is true of a paste that had neither; it is a wrong instruction after a
    /// photo Vision could not read a character of, and it is beside the point
    /// when what was pasted is a link this app has no way to open.
    enum ReadFailure {
        case noRecipe
        case unreadablePhoto
        case pastedLink

        var line: String {
            switch self {
            case .noRecipe:
                return "No recipe found. Check that the ingredients and steps are included."
            case .unreadablePhoto:
                return "Couldn't read that photo. Try a straighter shot with more light."
            case .pastedLink:
                return "That's a link. Open it, copy the recipe text, and paste that."
            }
        }
    }

    @State private var failure: ReadFailure?
    @State private var discardAsked = false
    @State private var nothingToPaste = false
    @State private var scannerShown = false
    @State private var editorShown = false
    /// Set by the editor before it closes, so the import sheet can leave
    /// with it instead of reappearing behind a finished recipe.
    @State private var savedInEditor = false
    @State private var photoItem: PhotosPickerItem?
    @FocusState private var editing: Bool
    @FocusState private var namingDish: Bool

    /// Up to eight thousand characters of pasted or photographed source, plus
    /// whatever the cook has corrected in the review. There is no other copy.
    private var hasWork: Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                VStack(spacing: 2) {
                    MicroLabel(draft == nil ? "To your cookbook" : "New recipe")
                    Text(draft == nil ? "Add a recipe" : "Does this look right?")
                        .plType(.title)
                        .foregroundStyle(Color.ink)
                }
                // The masthead was an eyebrow over a title and nothing else,
                // so the drag indicator was this sheet's only exit — and the
                // drag threw away the whole import silently, which on the scan
                // path costs another pass with the camera. The guard below
                // needs a door to exist first, or it is a trap.
                HStack {
                    Button("Cancel") {
                        Haptic.tap()
                        if hasWork { discardAsked = true } else { dismiss() }
                    }
                    .plType(.callout, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .plTapTarget()
                    .buttonStyle(.pressable)
                    Spacer()
                }
            }
            .padding(.horizontal, 20)
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
        .interactiveDismissDisabled(hasWork)
        .confirmationDialog("Discard this import?", isPresented: $discardAsked, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep it", role: .cancel) {}
        }
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

            if let failure {
                Text(failure.line)
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.tomato)
                    .multilineTextAlignment(.center)
                    // No retry control: the Paste, Scan and Photos chips are
                    // directly below this line.
            }

            // Three peers, one geometry. "Choose photo" needed about 108pt
            // of content in a 111pt chip, so on a real phone — where text
            // sets a hair wider than the simulator, the trap CLAUDE.md
            // names — it wrapped to two lines and that one chip stood
            // taller than the two beside it. The label is a word now, the
            // labels cannot wrap at all, and above xxLarge the three stop
            // sharing one row instead of crushing each other.
            sourceRow {
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
                    // "Photos" rather than "Choose photo": it names where
                    // the picture comes from, which is the one thing that
                    // distinguishes it from Scan beside it, and it fits.
                    ghostLabel("Photos", icon: "photo")
                }
                .buttonStyle(.pressable)
            }

            // The shared pill. Hand-built at 48pt and .body/.bold, this
            // lost TomatoPillStyle's pressed tomato and its float shadow,
            // and stood 8pt shorter than every other committing action in
            // the app.
            TomatoPillButton(title: reading ? "Reading…" : "Read it",
                             busy: reading, haptic: Haptic.plate) {
                editing = false
                read(raw)
            }
            .disabled(raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || reading)

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

    /// Three ways in, side by side while they fit and stacked when they do
    /// not. Chips this small have nowhere to reflow inside themselves, so
    /// the row reflows instead: at accessibility sizes a third of a screen
    /// cannot hold a word plus an icon, and squeezing them is how "Choose
    /// photo" wrapped in the first place.
    @ViewBuilder
    private func sourceRow(@ViewBuilder _ content: () -> some View) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 8) { content() }
        } else {
            HStack(spacing: 8) { content() }
        }
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
                // One line, always. A chip that grows a second line is a
                // chip with different geometry from the two beside it, and
                // DESIGN.md's rule is that peers look like peers.
                .lineLimit(1)
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

                    TomatoPillButton(title: unnamed ? "Name it to save" : "Save to cookbook",
                                     haptic: Haptic.kiss) {
                        save(bound.wrappedValue)
                    }
                    .disabled(unnamed)
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
                       : draft.wrappedValue.ingredients.count.things("ingredient"))
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
        // Caught before the parser rather than after it. A URL survives every
        // shape test a title has to pass, so the review step used to open
        // over a web address with no ingredients and a live Save button.
        if Self.isLink(text) {
            Haptic.warn()
            withAnimation(.plSnap) { failure = .pastedLink }
            return
        }
        reading = true
        failure = nil
        Task {
            let parsed = await RecipeImporter.parse(text)
            reading = false
            // `hasContent`, not `!isEmpty`: a title on its own is not a
            // recipe. See ImportedRecipe.
            if !parsed.hasContent {
                Haptic.warn()
                withAnimation(.plSnap) { failure = .noRecipe }
            } else {
                withAnimation(.plSettle) { draft = parsed }
                // The parser leaves the name blank rather than guessing
                // wrong. Put the cursor where the one remaining question is.
                if parsed.title.isEmpty { namingDish = true }
            }
        }
    }

    /// A pasted web address: one token, no spaces, and a scheme or a host.
    private static func isLink(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !t.contains(where: \.isNewline), !t.contains(" ") else { return false }
        if t.contains("://") || t.lowercased().hasPrefix("www.") { return true }
        return t.range(of: #"\.[a-z]{2,}(/|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Photographed pages → text → structure.
    ///
    /// The OCR result is written back into the paste box on the way through,
    /// so a misread card is visible and correctable rather than mysterious.
    private func scan(_ pages: [UIImage]) {
        guard !pages.isEmpty else { return }
        reading = true
        failure = nil
        Task {
            let text = await RecipeScanner.read(pages)
            reading = false
            // `raw` is assigned only when there is something to assign.
            // Writing it first meant scanning a blank photo silently
            // destroyed whatever the cook had already pasted.
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Haptic.warn()
                withAnimation(.plSnap) { failure = text == nil ? .unreadablePhoto : .noRecipe }
                return
            }
            raw = text
            read(text)
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
