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
    private let initialImages: [Data]

    init(initialInput: String = "", initialImages: [Data] = []) {
        self.initialImages = initialImages
        _raw = State(initialValue: initialInput)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var raw = ""
    @State private var draft: ImportedRecipe?
    @State private var reading = false
    /// Why the read did not produce a recipe.
    ///
    /// One Bool used to answer three different questions with one sentence.
    /// "No recipe found. Check that the ingredients and steps are included."
    /// is true of a paste that had neither; it is a wrong instruction after a
    /// photo Vision could not read a character of, and it is beside the point
    /// when a website refused the import request or could not be reached.
    enum ReadFailure {
        case noRecipe
        case unreadablePhoto
        case website(String)

        var line: String {
            switch self {
            case .noRecipe:
                return "No recipe found. Check that the ingredients and steps are included."
            case .unreadablePhoto:
                return "Couldn't read that photo. Try a straighter shot with more light."
            case .website(let message):
                return message
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
    @State private var duplicateToResolve: Recipe?
    @State private var pendingDuplicateDraft: ImportedRecipe?
    @State private var initialImportStarted = false
    @FocusState private var editing: Bool
    @FocusState private var namingDish: Bool

    /// Up to twenty-four thousand characters of pasted or photographed source, plus
    /// whatever the cook has corrected in the review. There is no other copy.
    private var hasWork: Bool {
        !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                // Its own row, not overlaid on the title. "Does this look
                // right?" takes the full width at xxLarge, so a leading
                // button sitting on top of it lands on the words.
                //
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
                MicroLabel(draft == nil ? "To your cookbook" : "New recipe")
                Text(draft == nil ? "Add a recipe" : "Does this look right?")
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
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
        .confirmationDialog(
            "This recipe may already be in your cookbook.",
            isPresented: Binding(
                get: { duplicateToResolve != nil },
                set: { if !$0 { duplicateToResolve = nil; pendingDuplicateDraft = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let duplicate = duplicateToResolve, let pending = pendingDuplicateDraft {
                Button("Update \(duplicate.title)") { update(duplicate, with: pending) }
                Button("Keep both") { saveNew(pending) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Update the existing copy and keep its cooking history, or save another copy.")
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
        .task {
            guard !initialImportStarted else { return }
            initialImportStarted = true
            let images = initialImages.compactMap(UIImage.init(data:))
            if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                read(raw)
            } else if !images.isEmpty {
                scan(images)
            }
        }
    }

    // MARK: Bring it in

    @ViewBuilder
    private var intake: some View {
        if typeSize.isAccessibilitySize {
            ScrollView(showsIndicators: false) {
                intakeContent
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            intakeContent
        }
    }

    private var intakeContent: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .topLeading) {
                if raw.isEmpty {
                    // The promise this makes is now one the parser keeps:
                    // headed sections are read as sections, and "Notes",
                    // "Nutrition" and the story are dropped on the floor.
                    Text("Paste a recipe or link. We'll keep the useful parts and drop the rest.")
                        .plType(.body, .medium)
                        .foregroundStyle(Color.inkSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 16)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $raw)
                    .plType(.body, .medium)
                    .foregroundStyle(Color.ink)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($editing)
            }
            .frame(
                minHeight: 190,
                maxHeight: typeSize.isAccessibilitySize ? 260 : .infinity
            )
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
                    .plActionLabel()
                    .foregroundStyle(Color.ink)
                    .frame(maxWidth: .infinity)
                    .plTapTarget()
            }
            .buttonStyle(.pressable)

            Text("Pasted text and scans stay on your phone. Website links are fetched only when you ask.")
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

                        reviewWarnings(bound.wrappedValue)

                        if let duplicate = duplicate(for: bound.wrappedValue) {
                            duplicateNotice(duplicate)
                        }

                        // "0 / Prep min" and "0 / Cook min" were the ordinary
                        // result of pasting a list out of a chat window — the
                        // parser initialises both to zero and the model is told
                        // to return zero when the recipe does not say — and
                        // they were presented as measured facts on the screen
                        // whose whole job is verification. The same rule is
                        // applied twenty lines below this and on the recipe
                        // page for this exact fact.
                        //
                        // The unit rides on the value, like the detail page,
                        // rather than sitting in the label as the app's only
                        // unit-in-label CountBlock.
                        HStack(spacing: 0) {
                            ImportFactField(value: bound.servings, label: "Serves", fallback: "4")
                            CountDivider()
                            ImportFactField(value: bound.prepMinutes, label: "Prep", suffix: "min")
                            CountDivider()
                            ImportFactField(value: bound.cookMinutes, label: "Cook", suffix: "min")
                        }

                        ingredientsBlock(bound)
                        stepsBlock(bound)
                        sourceBlock(bound.wrappedValue)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                }

                let actionLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10))
                    : AnyLayout(HStackLayout(spacing: 10))
                actionLayout {
                    Button {
                        Haptic.tap()
                        withAnimation(.plSnap) { draft = nil }
                    } label: {
                        // 56, like the pill beside it. Two buttons in one row
                        // are peers and a filled-versus-outlined pair already
                        // carries which is primary; an 8pt height difference
                        // carried nothing, and at xxLarge the tomato label
                        // wraps to two lines and the gap becomes obvious.
                        Text("Start over")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.pressable)

                    TomatoPillButton(title: unnamed ? "Name it to save" : "Save recipe",
                                     haptic: Haptic.kiss) {
                        requestSave(bound.wrappedValue)
                    }
                    .disabled(unnamed)
                }
                .padding(.horizontal, 24)
                .padding(.top, 10)
                .padding(.bottom, 24)
                // The scroll view runs under this row, so the last ingredient
                // was drawn through the buttons.
                .background(Color.canvas)
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

    @ViewBuilder
    private func reviewWarnings(_ imported: ImportedRecipe) -> some View {
        if !imported.warnings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.magnifyingglass")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Worth checking")
                        .plType(.footnote, .bold)
                }
                .foregroundStyle(Color.ink)

                ForEach(imported.warnings, id: \.self) { warning in
                    Text(warning)
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.fill, in: Radius.shape(Radius.card))
        }
    }

    private func duplicateNotice(_ duplicate: Recipe) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "books.vertical")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.inkSecondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Already in your cookbook")
                    .plType(.footnote, .bold)
                    .foregroundStyle(Color.ink)
                Text("When you save, you can update \(duplicate.title) or keep both copies.")
                    .plType(.caption)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.fill, in: Radius.shape(Radius.card))
    }

    private func ingredientsBlock(_ draft: Binding<ImportedRecipe>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel(draft.wrappedValue.ingredients.isEmpty
                       ? "Ingredients"
                       : draft.wrappedValue.ingredients.count.things("ingredient"))
            VStack(spacing: 0) {
                // Editable, which is what this screen's own doc comment says
                // it is. The parser's hazards make it concrete: a "1 1/2 cups"
                // read as "11/2 cups" is a quantity error a delete button
                // cannot answer.
                ForEach(draft.ingredients) { $ingredient in
                    HStack(spacing: 10) {
                        EditableLine(text: Binding(
                            get: { ingredient.text },
                            set: { $ingredient.wrappedValue.edited = $0 }
                        ), placeholder: "Ingredient")
                        RemoveLineButton(
                            label: "Remove \(ingredient.resolved.name.isEmpty ? "ingredient" : ingredient.resolved.name)"
                        ) {
                            draft.wrappedValue.ingredients.removeAll { $0.id == ingredient.id }
                        }
                    }
                    .padding(.vertical, 4)
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
                MicroLabel(draft.wrappedValue.steps.count.things("step"))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(draft.wrappedValue.steps.enumerated()), id: \.offset) { i, _ in
                        HStack(alignment: .top, spacing: 10) {
                            // Fixed-size first: a 16pt box broke "10"
                            // onto two lines, so every step past nine
                            // read as a stacked pair of digits.
                            //
                            // inkSecondary, not tomato: the same ordinal is
                            // inkSecondary on the recipe page and in the
                            // editor, and a static list ordinal is not an
                            // event that has earned the accent.
                            Text("\(i + 1)")
                                .plType(.micro, .extraBold, family: .display)
                                .foregroundStyle(Color.inkSecondary)
                                .monospacedDigit()
                                .lineLimit(1)
                                .fixedSize()
                                .frame(minWidth: 18, alignment: .leading)
                                .padding(.top, 12)
                            // Guarded rather than a raw `$steps[i]`: the
                            // remove button on this same row shortens the
                            // array while the row is still on screen.
                            EditableLine(text: Binding(
                                get: { draft.wrappedValue.steps.indices.contains(i)
                                    ? draft.wrappedValue.steps[i] : "" },
                                set: { if draft.wrappedValue.steps.indices.contains(i) {
                                    draft.wrappedValue.steps[i] = $0
                                } }
                            ), placeholder: "Step \(i + 1)")
                            RemoveLineButton(label: "Remove step \(i + 1)") {
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

    @ViewBuilder
    private func sourceBlock(_ imported: ImportedRecipe) -> some View {
        if !imported.sourceURL.isEmpty || !imported.sourceText.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MicroLabel("Original")
                    Spacer()
                    if let url = URL(string: imported.sourceURL), !imported.sourceURL.isEmpty {
                        Link(destination: url) {
                            Label("Open source", systemImage: "arrow.up.right")
                                .plType(.caption, .bold)
                                .foregroundStyle(Color.ink)
                        }
                    }
                }

                if !imported.sourceText.isEmpty {
                    DisclosureGroup {
                        Text(imported.sourceText)
                            .plType(.caption)
                            .foregroundStyle(Color.inkSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    } label: {
                        Text(imported.sourceName.isEmpty ? "Compare with what you added" : "Compare with \(imported.sourceName)")
                            .plType(.footnote, .semibold)
                            .foregroundStyle(Color.ink)
                    }
                    .tint(Color.ink)
                }
            }
            .padding(14)
            .background(Color.fill, in: Radius.shape(Radius.card))
        }
    }

    // MARK: Work

    private func read(_ text: String) {
        if Self.isLink(text) {
            readWebsite(text)
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

    private func readWebsite(_ text: String) {
        reading = true
        failure = nil
        Task {
            do {
                let parsed = try await RecipeURLImporter.read(text)
                reading = false
                raw = parsed.sourceURL
                withAnimation(.plSettle) { draft = parsed }
                if parsed.title.isEmpty { namingDish = true }
            } catch {
                reading = false
                Haptic.warn()
                let message = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't import a recipe from that page."
                withAnimation(.plSnap) { failure = .website(message) }
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
            // `raw` is assigned only when there is something to assign.
            // Writing it first meant scanning a blank photo silently
            // destroyed whatever the cook had already pasted.
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                reading = false
                Haptic.warn()
                withAnimation(.plSnap) { failure = text == nil ? .unreadablePhoto : .noRecipe }
                return
            }
            raw = text
            var parsed = await RecipeImporter.parse(text)
            parsed.importMethod = pages.count > 1 ? "scan" : "photo"
            parsed.sourceName = pages.count > 1 ? "Scanned pages" : "Scanned image"
            parsed.warnings.insert(
                "Text came from a photo. Check amounts and temperatures against the original.",
                at: 0
            )
            reading = false
            if !parsed.hasContent {
                Haptic.warn()
                withAnimation(.plSnap) { failure = .noRecipe }
            } else {
                withAnimation(.plSettle) { draft = parsed.withStandardWarnings() }
                if parsed.title.isEmpty { namingDish = true }
            }
        }
    }

    private func requestSave(_ r: ImportedRecipe) {
        if let duplicate = duplicate(for: r) {
            duplicateToResolve = duplicate
            pendingDuplicateDraft = r
        } else {
            saveNew(r)
        }
    }

    private func saveNew(_ r: ImportedRecipe) {
        let title = r.title.trimmingCharacters(in: .whitespaces)
        let recipe = Recipe(
            title: title.isEmpty ? "Untitled dish" : title,
            summary: r.summary,
            servings: max(1, r.servings),
            prepMinutes: max(0, r.prepMinutes),
            cookMinutes: max(0, r.cookMinutes)
        )
        applySource(from: r, to: recipe)
        // Blank lines are not steps. An editable row can be emptied, and
        // nothing else in the app can produce one.
        recipe.steps = r.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        context.insert(recipe)
        // `resolved` reads each typed line once. See ImportedIngredient.
        for (i, ing) in r.ingredients.map(\.resolved).filter({ !$0.name.isEmpty }).enumerated() {
            let row = Ingredient(name: ing.name, quantity: ing.quantity, unit: ing.unit)
            row.aisle = ing.aisle
            row.sortIndex = i
            row.recipe = recipe
            context.insert(row)
        }
        Persist.save(context)
        dismiss()
    }

    private func update(_ recipe: Recipe, with imported: ImportedRecipe) {
        recipe.title = imported.title.trimmingCharacters(in: .whitespacesAndNewlines)
        recipe.summary = imported.summary
        recipe.servings = max(1, imported.servings)
        recipe.prepMinutes = max(0, imported.prepMinutes)
        recipe.cookMinutes = max(0, imported.cookMinutes)
        recipe.steps = imported.steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        recipe.instructions = ""
        applySource(from: imported, to: recipe)

        for ingredient in recipe.ingredients ?? [] { context.delete(ingredient) }
        for (index, importedIngredient) in imported.ingredients.map(\.resolved)
            .filter({ !$0.name.isEmpty }).enumerated() {
            let row = Ingredient(
                name: importedIngredient.name,
                quantity: importedIngredient.quantity,
                unit: importedIngredient.unit
            )
            row.aisle = importedIngredient.aisle
            row.sortIndex = index
            row.recipe = recipe
            context.insert(row)
        }
        Persist.save(context)
        dismiss()
    }

    private func applySource(from imported: ImportedRecipe, to recipe: Recipe) {
        recipe.sourceURL = imported.sourceURL
        recipe.sourceName = imported.sourceName
        recipe.sourceText = imported.sourceText
        recipe.importMethod = imported.importMethod
        recipe.importedAt = .now
    }

    private func duplicate(for imported: ImportedRecipe) -> Recipe? {
        let source = canonicalURL(imported.sourceURL)
        if !source.isEmpty,
           let exactSource = recipes.first(where: { canonicalURL($0.sourceURL) == source }) {
            return exactSource
        }

        let title = normalized(imported.title)
        guard !title.isEmpty else { return nil }
        let incoming = Set(imported.ingredients.map { normalized($0.resolved.name) }.filter { !$0.isEmpty })
        return recipes.first { recipe in
            guard normalized(recipe.title) == title else { return false }
            let existing = Set(recipe.sortedIngredients.map { normalized($0.name) }.filter { !$0.isEmpty })
            if incoming.isEmpty || existing.isEmpty { return true }
            let overlap = incoming.intersection(existing).count
            let total = incoming.union(existing).count
            return total > 0 && Double(overlap) / Double(total) >= 0.65
        }
    }

    private func canonicalURL(_ raw: String) -> String {
        guard var components = URLComponents(string: raw) else { return "" }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        components.fragment = nil
        components.queryItems = components.queryItems?.filter {
            let name = $0.name.lowercased()
            return !name.hasPrefix("utm_") && !["fbclid", "gclid"].contains(name)
        }
        var value = components.string ?? ""
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

/// The import review is the only chance to correct yield and times before
/// saving. A static count here made "Does this look right?" an unanswerable
/// question for three of the six fields on screen.
private struct ImportFactField: View {
    @Binding var value: Int
    let label: String
    var suffix = ""
    var fallback = "Not set"

    private var text: Binding<String> {
        Binding(
            get: { value > 0 ? "\(value)" : "" },
            set: { value = max(0, Int($0.filter(\.isNumber)) ?? 0) }
        )
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                TextField(fallback, text: text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .plType(.heading)
                    .foregroundStyle(Color.ink)
                    .frame(minWidth: 28)
                if value > 0 && !suffix.isEmpty {
                    Text(suffix)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            Text(label)
                .plType(.caption)
                .foregroundStyle(Color.inkSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
