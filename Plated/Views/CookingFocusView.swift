import SwiftUI
import SwiftData

/// A cooking session owns a frozen method and yield. Browsing or editing the
/// recipe cannot move the instruction under a cook's finger halfway through.
struct CookingFocusView: View {
    let recipe: Recipe
    var meal: PlannedMeal?
    var servings: Int
    var remotePlanID: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var ledger = CookLedger.shared
    private enum SessionSheet: String, Identifiable {
        case ingredients, post
        var id: String { rawValue }
    }
    @State private var sessionSheet: SessionSheet?
    @State private var finished = false
    @State private var completionNote = ""
    @State private var finishing = false
    @State private var finishMessage = "Saved to your cooking history."
    @State private var endAsked = false
    private var note: Binding<String> { Binding(get: { session?.noteDraft ?? "" }, set: { ledger.setNote($0, in: recipe) }) }
    @State private var error: String?
    @State private var timerHint: String?
    private var session: CookLedger.Session? { ledger.session(for: recipe) }
    private var steps: [String] { ledger.steps(for: recipe) }
    private var index: Int { min(max(0, session?.step ?? 0), max(0, steps.count - 1)) }

    /// Only show an ingredient beside a step when the written method names
    /// it. Guessing that "season" means salt and pepper is exactly how a
    /// cooking guide becomes confidently wrong; the editor now prompts the
    /// author to write those specifics instead.
    private var stepIngredientLines: [String] {
        guard !steps.isEmpty else { return [] }
        let words = Self.meaningfulWords(in: steps[index])
        guard !words.isEmpty else { return [] }
        return (session?.ingredientsSnapshot ?? []).filter { line in
            !words.isDisjoint(with: Self.meaningfulWords(in: line))
        }
    }

    /// A duration already written in the method is safe to turn into a
    /// shortcut. The generic timer remains available when the recipe gives
    /// no duration; Plated never manufactures one.
    private var suggestedTimerMinutes: Int? {
        guard !steps.isEmpty else { return nil }
        let words = steps[index]
            .lowercased()
            .replacingOccurrences(of: "\u{2013}", with: "-")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" }
            .map(String.init)
        var candidates: [Int] = []
        for position in words.indices where position + 1 < words.count {
            let number = words[position]
            guard let amount = Int(number), amount > 0 else {
                // "10-15 minutes" is a range, not one honest default.
                if number.contains("-") && number.contains(where: \.isNumber) { return nil }
                continue
            }
            if position >= 2,
               ["to", "or"].contains(words[position - 1]),
               Int(words[position - 2]) != nil {
                return nil
            }
            if position >= 2,
               words[position - 1] == "-",
               Int(words[position - 2]) != nil {
                return nil
            }
            let unit = words[position + 1]
            if unit.hasPrefix("min") { candidates.append(min(amount, 480)) }
            if unit.hasPrefix("hour") || unit == "hr" || unit == "hrs" {
                candidates.append(min(amount * 60, 480))
            }
        }
        // Compound or multi-stage durations need author intent. Keep the
        // ordinary timer menu available instead of choosing one silently.
        return candidates.count == 1 ? candidates[0] : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DesignIconButton(symbol: "chevron.down", label: finished ? "Close cooking" : "Minimize cooking") { // design-ok(generic-chevron): approved downward control minimizes the cooking session.
                    if finished { finishDone() } else { dismiss() }
                }
                Text(finished ? "Finished" : "Cooking")
                    .plType(.body, .semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !finished {
                    Menu {
                        Button("End cooking", systemImage: "xmark", role: .destructive) { endAsked = true }
                    } label: {
                        Image(systemName: "ellipsis").foregroundStyle(Color.ink).plTapTarget()
                    }
                    .accessibilityLabel("Cooking options")
                }
            }.disabled(finishing).plChrome().padding(.horizontal, 24).padding(.vertical, 8)
            if finished {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44, weight: .light)).foregroundStyle(Color.completion)
                            .accessibilityHidden(true)
                        Text("Dinner, made.").plType(.title)
                        Text(finishMessage).plType(.footnote).foregroundStyle(Color.inkSecondary)
                        Text("A note for next time").plType(.heading)
                        TextField("Anything you’d do differently? · optional", text: $completionNote, axis: .vertical)
                            .plType(.body).lineLimit(3...6).padding(16)
                            .background(Color.fill, in: Radius.shape(Radius.chip))
                            .accessibilityLabel("Cooking note, optional")
                        Button {
                            guard saveCompletionNote() else { return }
                            sessionSheet = .post
                        } label: {
                            Label("Share at the Table", systemImage: "square.and.arrow.up")
                                .plType(.footnote, .semibold).frame(minHeight: 44)
                        }.buttonStyle(.pressable)
                    }.padding(24)
                }
                PrimaryActionButton(title: completionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Done" : "Save note & done") {
                    finishDone()
                }.padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(session?.titleSnapshot ?? recipe.title)
                            .plType(.heading).fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        let controls = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
                        controls {
                            MicroLabel(steps.isEmpty ? "Your recipe" : "Step \(index + 1) of \(steps.count)")
                            if !typeSize.isAccessibilitySize { Spacer() }
                            Text("Serves \(session?.servings ?? servings)").plType(.footnote).foregroundStyle(Color.inkSecondary)
                        }
                        if steps.isEmpty {
                            Text("Ingredients").plType(.heading).accessibilityAddTraits(.isHeader)
                            if (session?.ingredientsSnapshot ?? []).isEmpty {
                                Text("No ingredients or directions have been added to this recipe.")
                                    .plType(.body).foregroundStyle(Color.inkSecondary)
                            }
                            ForEach(Array((session?.ingredientsSnapshot ?? []).enumerated()), id: \.offset) { _, line in
                                Text(line).plType(.body).frame(maxWidth: .infinity, alignment: .leading)
                                Divider()
                            }
                        } else {
                            ProgressView(value: Double(index + 1), total: Double(steps.count)).tint(Color.olive)
                            Text(steps[index]).plType(.body, .medium).foregroundStyle(Color.ink)
                                .fixedSize(horizontal: false, vertical: true).id(index)
                        }
                        if !stepIngredientLines.isEmpty || suggestedTimerMinutes != nil {
                            VStack(alignment: .leading, spacing: 10) {
                                MicroLabel("For this step")
                                ForEach(Array(stepIngredientLines.enumerated()), id: \.offset) { _, line in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Circle().fill(Color.basil).frame(width: 5, height: 5)
                                        Text(line)
                                            .plType(.callout, .medium)
                                            .foregroundStyle(Color.ink)
                                    }
                                }
                                if let minutes = suggestedTimerMinutes {
                                    Button {
                                        startTimer(minutes)
                                    } label: {
                                        Label("Start the \(minutes)-minute timer", systemImage: "timer")
                                            .plType(.footnote, .bold)
                                            .plActionLabel(0.72)
                                            .foregroundStyle(Color.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .frame(minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.pressable)
                                }
                            }
                            .padding(16)
                            .background(Color.fill, in: Radius.shape(Radius.card))
                        }
                        controls {
                            if !steps.isEmpty {
                                DesignChip(title: "Ingredients", symbol: "list.bullet") { sessionSheet = .ingredients }
                            }
                            Menu {
                                ForEach([1, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                                    Button("\(minutes) min") { startTimer(minutes) }
                                }
                            } label: {
                                Label("Set timer", systemImage: "timer")
                                    .plType(.footnote)
                                    .plActionLabel()
                                    .foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16).frame(minHeight: 44).background(Color.fill, in: Radius.shape(Radius.chip))
                            }
                        }
                        if let timer = ledger.timer(for: recipe) {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                HStack(spacing: 12) {
                                    Image(systemName: ledger.isTimerMuted(for: recipe) ? "bell.slash" : "timer")
                                        .accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 2) {
                                        if timer.endsAt > tick.date {
                                            Text(timer.endsAt, style: .timer).monospacedDigit().plType(.heading)
                                        } else { Text("0:00").monospacedDigit().plType(.heading) }
                                        Text(timer.endsAt <= tick.date ? "Timer finished" : ledger.isTimerMuted(for: recipe) ? "Alert muted" : "Timer running")
                                            .plType(.caption).foregroundStyle(Color.inkSecondary)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                    Menu {
                                        Button {
                                            let muted = !ledger.isTimerMuted(for: recipe)
                                            ledger.setTimerMuted(muted, in: recipe)
                                            if muted { NotificationScheduler.cancelCookTimer() }
                                            else { scheduleTimerAlert(until: timer.endsAt) }
                                        } label: {
                                            Label(ledger.isTimerMuted(for: recipe) ? "Unmute alert" : "Mute alert",
                                                  systemImage: ledger.isTimerMuted(for: recipe) ? "bell.slash" : "bell")
                                        }
                                        if let duration = ledger.timerDuration(for: recipe), duration > 0 {
                                            Button("Restart timer", systemImage: "arrow.counterclockwise") { restartTimer(duration) }
                                        }
                                        Button("Clear timer", systemImage: "xmark", role: .destructive) {
                                            ledger.clearTimer(in: recipe)
                                            NotificationScheduler.cancelCookTimer()
                                            CookTimerLive.end()
                                        }
                                    } label: {
                                        Image(systemName: "ellipsis").plTapTarget()
                                    }.accessibilityLabel("Timer options")
                                }
                                .foregroundStyle(Color.ink)
                                .padding(16).background(Color.oliveTint, in: Radius.shape(Radius.chip))
                            }
                        }
                        if let timerHint { Text(timerHint).plType(.caption).foregroundStyle(Color.inkSecondary) }

                    }.padding(24)
                }
                HStack(spacing: 12) {
                    if index > 0 {
                        DesignIconButton(symbol: "arrow.left", label: "Previous step") { move(-1) }
                    }
                    PrimaryActionButton(title: index < steps.count - 1 ? "Next step" : "Finish cooking", systemImage: index < steps.count - 1 ? "arrow.right" : "checkmark") {
                        if index < steps.count - 1 { move(1) } else { finish() }
                    }
                }.disabled(finishing).plChrome().padding(.horizontal, 24).padding(.vertical, 12).background(Color.canvas)
            }
        }
        .background(Color.canvas).foregroundStyle(Color.ink)
        .onAppear {
            ledger.begin(recipe, servings: servings, mealID: meal?.shoppingID, remotePlanID: remotePlanID)
            UIApplication.shared.isIdleTimerDisabled = true
            // A finished or cleared timer's activity comes down here; the
            // system cannot be told to end one at the moment it rings.
            CookTimerLive.reconcile(endsAt: ledger.timer(for: recipe)?.0)
        }
        .interactiveDismissDisabled(finishing || (finished && !completionNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: phase) { _, value in UIApplication.shared.isIdleTimerDisabled = value == .active && !finished }
        .sheet(item: $sessionSheet) { sheet in
            switch sheet {
            case .post:
                TableComposerSheet(prefillRecipe: recipe)
            case .ingredients:
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("For \(session?.servings ?? servings) servings").plType(.footnote).foregroundStyle(Color.inkSecondary)
                        ForEach(Array((session?.ingredientsSnapshot ?? []).enumerated()), id: \.offset) { _, line in
                            Text(line).plType(.callout).frame(maxWidth: .infinity, alignment: .leading)
                            Divider()
                        }
                    }.padding(24)
                }.background(Color.canvas).navigationTitle("Ingredients").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { sessionSheet = nil } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
            }
        }
        .alert(finished ? "Couldn't save your note" : "Couldn't save dinner", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Try again.") }
        .confirmationDialog("End cooking?", isPresented: $endAsked, titleVisibility: .visible) {
            Button("End cooking", role: .destructive) { endCooking() }
            Button("Keep cooking", role: .cancel) {}
        } message: {
            Text("Your place in the recipe, note draft and cook timer will be cleared. The meal stays planned.")
        }
    }

    private static func meaningfulWords(in text: String) -> Set<String> {
        let ignored: Set<String> = [
            "and", "the", "with", "into", "from", "over", "until", "then", "for",
            "cup", "cups", "tbsp", "tsp", "tablespoon", "tablespoons", "teaspoon",
            "teaspoons", "ounce", "ounces", "gram", "grams", "pound", "pounds",
            "fresh", "large", "small", "medium", "optional", "divided", "taste"
        ]
        return Set(text.lowercased().split { !$0.isLetter }.map(String.init).filter {
            $0.count > 2 && !ignored.contains($0)
        })
    }

    private func move(_ delta: Int) {
        let next = min(max(index + delta, 0), max(steps.count - 1, 0))
        Haptic.select()
        withAnimation(.plSnap) { ledger.setStep(next, in: recipe) }
        if steps.indices.contains(next) {
            AccessibilityNotification.Announcement(
                "Step \(next + 1) of \(steps.count). \(steps[next])"
            ).post()
        }
    }
    private func startTimer(_ minutes: Int) {
        let seconds = Double(minutes * 60)
        let endsAt = Date.now.addingTimeInterval(seconds)
        ledger.startTimer(endingAt: endsAt, step: index, in: recipe)
        // A recipe with no written steps has no step to name.
        CookTimerLive.start(dish: recipe.title, step: steps.isEmpty ? 0 : index + 1, endsAt: endsAt)
        Task {
            let authorized = await NotificationScheduler.askOnce()
            await NotificationScheduler.scheduleCookTimer(in: seconds, title: "Plated timer", body: "\(recipe.title): your \(minutes) minute timer is ready.", soundEnabled: !ledger.isTimerMuted(for: recipe))
            timerHint = authorized ? "The timer can alert you while Plated is in the background." : "Notifications are off. The timer stays visible here."
        }
    }

    private func restartTimer(_ duration: TimeInterval) {
        let endsAt = Date.now.addingTimeInterval(duration)
        ledger.startTimer(endingAt: endsAt, step: index, in: recipe)
        CookTimerLive.start(dish: recipe.title, step: steps.isEmpty ? 0 : index + 1, endsAt: endsAt)
        scheduleTimerAlert(until: endsAt)
    }

    private func scheduleTimerAlert(until date: Date) {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return }
        Task {
            let muted = ledger.isTimerMuted(for: recipe)
            await NotificationScheduler.scheduleCookTimer(
                in: seconds,
                title: "Plated timer",
                body: "\(recipe.title): your timer is ready.",
                soundEnabled: !muted
            )
        }
    }
    private func endCooking() {
        ledger.forget(recipe)
        CookTimerLive.end()
        NotificationScheduler.cancelCookTimer()
        UIApplication.shared.isIdleTimerDisabled = false
        Haptic.select()
        dismiss()
    }
    private func finishDone() {
        if saveCompletionNote() { dismiss() }
    }

    private func saveCompletionNote() -> Bool {
        let text = completionNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        let previous = recipe.cookNotes
        recipe.cookNotes = [previous, text].filter { !$0.isEmpty }.joined(separator: "\n\n")
        guard Persist.save(context, "cooking note saved") else {
            recipe.cookNotes = previous
            error = "Your note is still here. Please try saving it again."
            return false
        }
        completionNote = ""
        return true
    }

    private func finish() {
        guard !finishing else { return }
        if let record = session?.remotePlanID {
            finishShared(record)
            return
        }
        finishLocally()
    }

    private func finishShared(_ record: String) {
        guard let entry = PlanLedger.shared.entry(record), !entry.isGoing else {
            error = "This household night is no longer available. Your session is still here."
            return
        }
        guard entry.recipeOriginKey == recipe.planningKey else {
            error = "The household changed this night’s recipe. Your original cooking session is still here. Check the plan before finishing."
            return
        }
        finishing = true
        var edit = PlanShare.Edit(changing: entry)
        edit.cooked = true; edit.cookedAt = .now
        Task {
            let outcome = await PlanShare.write(edit)
            finishing = false
            switch outcome {
            case .landed:
                finishMessage = "Marked cooked on your household plan."
            case .queued(let message):
                finishMessage = "Cooking completed on this phone. \(message)"
            case .theirs:
                error = "Your household changed this night. Check the plan, then try finishing again."
                return
            case .refused(let reason):
                error = reason
                return
            }
            finishLocally(shared: true)
        }
    }

    private func finishLocally(shared: Bool = false) {
        // Resume uses the frozen session's night, even if the same recipe is
        // opened from a different date while it is already cooking.
        let meal = session?.mealID.flatMap { id in
            (try? context.fetch(FetchDescriptor<PlannedMeal>()))?.first { $0.shoppingID == id }
        }
        if let meal, meal.recipe?.persistentModelID != recipe.persistentModelID {
            error = "This night’s recipe has changed. Your original session is still here. Check the plan before finishing."
            return
        }
        let previousDate = meal?.cookedAt
        let previousNotes = recipe.cookNotes
        var inserted: PlannedMeal?
        if let meal { meal.cookedAt = .now }
        else if !shared {
            let cooked = PlannedMeal(date: .now, slot: .dinner, recipe: recipe, servings: session?.servings ?? servings)
            cooked.cookedAt = .now; context.insert(cooked); inserted = cooked
        }
        let draftNote = note.wrappedValue
        do {
            try context.save()
            completionNote = draftNote
            ledger.forget(recipe)
            CookTimerLive.end()
            NotificationScheduler.cancelCookTimer()
            UIApplication.shared.isIdleTimerDisabled = false
            Haptic.kiss(); withAnimation(.plSettle) { finished = true }
            AccessibilityNotification.Announcement(
                "Dinner made. " + finishMessage
            ).post()
        } catch {
            meal?.cookedAt = previousDate; recipe.cookNotes = previousNotes
            if let inserted { context.delete(inserted) }
            self.error = "Your session is still here. Please try saving again."
        }
    }
}
