import SwiftUI
import SwiftData

/// A cooking session owns a frozen method and yield. Browsing or editing the
/// recipe cannot move the instruction under a cook's finger halfway through.
struct CookingFocusView: View {
    let recipe: Recipe
    var meal: PlannedMeal?
    var servings: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var phase
    @State private var ledger = CookLedger.shared
    @State private var ingredientsShown = false
    @State private var finished = false
    private var note: Binding<String> { Binding(get: { session?.noteDraft ?? "" }, set: { ledger.setNote($0, in: recipe) }) }
    @State private var error: String?
    @State private var timerHint: String?
    private var session: CookLedger.Session? { ledger.session(for: recipe) }
    private var steps: [String] { ledger.steps(for: recipe) }
    private var index: Int { min(max(0, session?.step ?? 0), max(0, steps.count - 1)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                DesignIconButton(symbol: "chevron.down", label: "Minimize cooking") { dismiss() }
                VStack(alignment: .leading, spacing: 3) {
                    Text(finished ? "Nicely done." : "Cooking together").plType(.heading, .semibold)
                    Text(session?.titleSnapshot ?? recipe.title).plType(.caption).foregroundStyle(Color.inkSecondary).lineLimit(2)
                }.frame(maxWidth: .infinity, alignment: .leading)
                AccountButton()
            }.padding(.horizontal, 24).padding(.vertical, 14)
            if finished {
                Spacer()
                Image(systemName: "checkmark.circle.fill").font(.system(size: 62, weight: .light)).foregroundStyle(Color.completion)
                Text("Dinner, made.").plType(.hero, .medium).padding(.top, 20)
                Text("Saved to your cooking history.").plType(.body).foregroundStyle(Color.inkSecondary).padding(.top, 4)
                Spacer()
                TomatoPillButton(title: "Done") { dismiss() }.padding(24)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        HStack {
                            MicroLabel(steps.isEmpty ? "Your recipe" : "Step \(index + 1) of \(steps.count)")
                            Spacer()
                            Text("Serves \(session?.servings ?? servings)").plType(.footnote).foregroundStyle(Color.inkSecondary)
                        }
                        ProgressView(value: steps.isEmpty ? 0 : Double(index + 1), total: Double(max(1, steps.count))).tint(Color.tomato)
                        Text(steps.isEmpty ? "This recipe has no written steps. Keep the ingredients close as you cook." : steps[index])
                            .plType(.display, .medium).foregroundStyle(Color.ink)
                            .fixedSize(horizontal: false, vertical: true).id(index)
                        HStack(spacing: 12) {
                            DesignChip(title: "Ingredients", symbol: "list.bullet") { ingredientsShown = true }
                            Menu {
                                ForEach([1, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                                    Button("\(minutes) min") { startTimer(minutes) }
                                }
                            } label: {
                                Label("Set timer", systemImage: "timer").plType(.footnote).foregroundStyle(Color.ink)
                                    .padding(.horizontal, 16).frame(minHeight: 44).background(Color.fill, in: Capsule())
                            }
                        }
                        if let timer = ledger.timer(for: recipe) {
                            TimelineView(.periodic(from: .now, by: 1)) { tick in
                                HStack {
                                    Image(systemName: "timer")
                                    if timer.endsAt > tick.date { Text(timer.endsAt, style: .timer).monospacedDigit() }
                                    else { Text("0:00").monospacedDigit() }
                                    if timer.endsAt <= tick.date { Text("Timer finished").plType(.footnote) }
                                    Spacer()
                                    Button("Clear") { ledger.clearTimer(in: recipe); NotificationScheduler.cancelCookTimer() }.plType(.footnote, .semibold).plTapTarget()
                                }.plType(.title).foregroundStyle(Color.ink).padding(16).background(Color.tomatoTint, in: Radius.shape(Radius.chip))
                            }
                        }
                        if let timerHint { Text(timerHint).plType(.caption).foregroundStyle(Color.inkSecondary) }
                        if index == steps.count - 1 || steps.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("A note for next time").plType(.heading, .medium)
                                TextField("What would you make your own?", text: note, axis: .vertical)
                                    .plType(.body).lineLimit(3...6).padding(16)
                                    .background(Color.fill, in: Radius.shape(Radius.chip))
                            }
                        }
                    }.padding(24)
                }
                HStack(spacing: 12) {
                    if index > 0 {
                        DesignIconButton(symbol: "arrow.left", label: "Previous step") { move(-1) }
                    }
                    TomatoPillButton(title: index < steps.count - 1 ? "Next step" : "Finish cooking", systemImage: index < steps.count - 1 ? "arrow.right" : "checkmark") {
                        if index < steps.count - 1 { move(1) } else { finish() }
                    }
                }.padding(24).background(.ultraThinMaterial)
            }
        }
        .background(Color.canvas).foregroundStyle(Color.ink)
        .onAppear { ledger.begin(recipe, servings: servings, mealID: meal?.shoppingID); UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .onChange(of: phase) { _, value in UIApplication.shared.isIdleTimerDisabled = value == .active && !finished }
        .sheet(isPresented: $ingredientsShown) {
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
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { ingredientsShown = false } } }
            }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).plTapOutsideToDismiss()
        }
        .alert("Couldn't save dinner", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "Try again.") }
    }
    private func move(_ delta: Int) {
        Haptic.select()
        withAnimation(.plSnap) { ledger.setStep(index + delta, in: recipe) }
    }
    private func startTimer(_ minutes: Int) {
        let seconds = Double(minutes * 60)
        ledger.startTimer(endingAt: .now.addingTimeInterval(seconds), step: index, in: recipe)
        Task {
            let authorized = await NotificationScheduler.askOnceAfterFirstPlan()
            await NotificationScheduler.scheduleCookTimer(in: seconds, title: "Plated timer", body: "\(recipe.title): your \(minutes) minute timer is ready.")
            timerHint = authorized ? "The timer can alert you while Plated is in the background." : "Notifications are off. The timer stays visible here."
        }
    }
    private func finish() {
        let previousDate = meal?.cookedAt
        let previousNotes = recipe.cookNotes
        var inserted: PlannedMeal?
        if let meal { meal.cookedAt = .now }
        else {
            let cooked = PlannedMeal(date: .now, slot: .dinner, recipe: recipe, servings: session?.servings ?? servings)
            cooked.cookedAt = .now; context.insert(cooked); inserted = cooked
        }
        if !note.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recipe.cookNotes = [recipe.cookNotes, note.wrappedValue].filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        do {
            try context.save()
            ledger.forget(recipe); NotificationScheduler.cancelCookTimer()
            UIApplication.shared.isIdleTimerDisabled = false
            Haptic.kiss(); withAnimation(.plSettle) { finished = true }
        } catch {
            meal?.cookedAt = previousDate; recipe.cookNotes = previousNotes
            if let inserted { context.delete(inserted) }
            self.error = "Your session is still here. Please try saving again."
        }
    }
}
