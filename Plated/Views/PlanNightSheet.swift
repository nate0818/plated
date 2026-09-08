import SwiftUI
import SwiftData

/// The planning page for one night — every way to fill (or free) a plate
/// in one place: pick for me, your recipes, a brand-new recipe, eating
/// out, asking the table (with a poll), or a full gathering. Opened from
/// any open night, any planned night, and any month-view day.
///
/// **Two sources of truth, one set of controls.** The night this page
/// changes is either this phone's own `PlannedMeal` or, when there is none
/// and the household ledger holds one, that household night. Every control
/// below acts on whichever is there. A household night is changed by writing
/// its `PlatedHouseholdPlan` record through `PlanShare.write`, and never by
/// making a `PlannedMeal` out of it: a household fact in a store configured
/// `cloudKitDatabase: .automatic` has two writers by construction, the zone
/// and this phone's own mirror carrying it to its other devices while they
/// merge the same record (docs/plan-share.md, "Two-way editing").
struct PlanNightSheet: View {
    let date: Date
    /// Which eating occasion is being filled. Dinner is the week's spine and
    /// stays the default, so every existing caller is unchanged; the day
    /// view passes breakfast, lunch, dessert and snack through the same page.
    var slot: MealSlot = .dinner
    /// The household night the person tapped, when they tapped one. A day
    /// can hold this phone's dinner and somebody else's at once, and then
    /// nothing but the tap says which one is being changed.
    var editingPlan: String? = nil
    var askTheTable: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var meals: [PlannedMeal]
    @Query private var recipes: [Recipe]
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @AppStorage("showCalendarEvents") private var showCalendarEvents = false
    /// One destination, not four flags.
    ///
    /// These were four `.sheet` modifiers stacked on one view, which CLAUDE.md
    /// records as undefined behaviour, and the picker's own empty state calls
    /// `dismiss()` and then asks this view to raise the editor — a dismissal
    /// and a presentation landing in the same update on the same presenting
    /// view. That path is not an edge case: "Choose a recipe" is offered
    /// whether or not the cookbook has anything in it, so every first-run
    /// user reaches the empty picker, where "Add a recipe" is the only
    /// control on the screen. Same shape as MainShellView's CreateFlowSheet.
    enum Route: String, Identifiable {
        case picker, newRecipe, ask, gathering
        var id: String { rawValue }
    }
    @State private var route: Route?
    /// The masthead and the scroll content, measured separately and added.
    /// See the detent at the bottom of this view.
    @State private var mastheadHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var events = DayEventsProvider.shared
    @State private var forecast = ForecastProvider.shared

    /// What the last write answered, in the words this page says out loud.
    @State private var notice: String?
    /// The kind of write on the wire, or nil. The sheet stays up until it
    /// answers.
    ///
    /// Sending and dismissing in the same breath threw away three of the
    /// four answers `PlanShare.write` can give: queued, theirs and refused
    /// were being set on a page nobody was looking at, and a delete leaves
    /// no row behind to carry them either. So the outcome decides the
    /// dismissal, and while it is deciding the control that started it
    /// reads as working and cannot be fired again.
    ///
    /// The kind and not a bare flag, because the trash says what IT is
    /// doing: dressed off a plain "a write is happening" it would read
    /// "Taking this night off the plan" while the person was changing the
    /// cook, which is the interface claiming something that is not so.
    @State private var inFlight: PlanShare.Edit.Kind?
    private var sending: Bool { inFlight != nil }
    /// A stepper held down is one intention, not eight: the row moves on
    /// every tap and the zone hears the number they stopped on.
    @State private var servingsWrite: Task<Void, Never>?

    private var meal: PlannedMeal? {
        // A named household night is the one being changed, even on a slot
        // this phone has also planned.
        guard editingPlan == nil else { return nil }
        return meals.first { Calendar.current.isSameDay($0.date, date) && $0.slotValue == slot }
    }

    /// The household night this page changes: the one that was tapped, or
    /// the one on this slot when this phone has planned nothing here.
    ///
    /// A night that is going is never picked up implicitly. It is still in
    /// the ledger, and taking it as the night this page changes would put
    /// the dish, the servings and the cook on a record whose delete is
    /// already queued: the queue folds the change back into the delete, so
    /// the person would watch the sheet accept an edit that can never
    /// happen. The slot is free as far as this page is concerned, and what
    /// they plan there is this phone's own night. A night they tapped by
    /// name stays, because that is where the delete's own answer is said.
    private var remote: PlanLedger.Entry? {
        if let editingPlan { return PlanLedger.shared.entry(editingPlan) }
        guard meal == nil else { return nil }
        return PlanLedger.shared.plans(on: date, slot: slot).first { !$0.isGoing }
    }

    /// The night this page is changing is on its way off the plan, so the
    /// page is its answer and not its editor.
    private var going: Bool { remote?.isGoing ?? false }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                MicroLabel(meal == nil && remote == nil ? planLabel : "Planned")
                Text(dayTitle)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
                if let context = contextLine {
                    Text(context)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
                // Somebody else already filled this one. Said once, so a
                // night planned here on top of theirs is planned knowingly;
                // the sheet itself is unchanged, because their night is
                // theirs and this page only ever writes this phone's.
                if let remote = remotePlanLine {
                    Text(remote)
                        .plType(.footnote)
                        .foregroundStyle(Color.inkSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                }
            }
            .padding(.top, 22)
            .padding(.bottom, 14)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { mastheadHeight = $0 }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    if let meal {
                        currentMealCard(meal)
                            .padding(.bottom, contestLine(for: meal) == nil ? 6 : 2)
                        // The household changed a night this phone planned,
                        // and this phone's copy is the one on screen. Nothing
                        // reconciles the two: the publisher stood down rather
                        // than overwrite their change, and the ledger drops
                        // records this phone authored, so without this line
                        // the person edits on top of a night that no longer
                        // says what they think it says. It states both facts
                        // and stops, because the app does not know which of
                        // them is meant to win.
                        if let line = contestLine(for: meal) {
                            Text(line)
                                .plType(.footnote)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.bottom, 6)
                        }
                        Stepper(value: Binding(get: { meal.servings }, set: { meal.servings = $0; Persist.save(context) }), in: 1...99) {
                            Text("\(meal.servings) servings").plType(.body, .semibold)
                                .contentTransition(.numericText())
                        }
                        .padding(.vertical, 6)
                        Menu {
                            Button("Unassigned") { meal.cook = nil; Persist.save(context) }
                            ForEach(members.assignableCooks) { member in
                                Button(member.isMe ? "You" : member.name) { meal.cook = member; Persist.save(context) }
                            }
                        } label: {
                            HStack {
                                Text("Cook").plType(.body)
                                Spacer()
                                Text(meal.cook.map { $0.isMe ? "You" : $0.name } ?? "Unassigned").plType(.body, .semibold)
                                Image(systemName: "slider.horizontal.3").font(.footnote)
                            }.foregroundStyle(Color.ink).frame(minHeight: 44)
                        }
                        MicroLabel("Something else")
                    } else if let remote {
                        // The same card and the same two controls, writing
                        // the household record instead of a row in this
                        // phone's store.
                        remoteNightCard(remote)
                            .padding(.bottom, notice == nil ? 6 : 2)
                        noticeRow
                        // Nothing to change on a night that is going. The
                        // page stays up to say what the delete answered, and
                        // a servings stepper over that sentence would be an
                        // edit the queue folds straight back into the
                        // delete: a control that looks alive and cannot act.
                        if !going {
                            Stepper(value: Binding(get: { remote.servings }, set: { changeServings($0, on: remote) }), in: 1...99) {
                                Text("\(remote.servings) servings").plType(.body, .semibold)
                                    .contentTransition(.numericText())
                            }
                            .padding(.vertical, 6)
                            Menu {
                                Button("Unassigned") { changeCook(nil, on: remote) }
                                ForEach(members.assignableCooks) { member in
                                    Button(member.isMe ? "You" : member.name) { changeCook(member, on: remote) }
                                }
                            } label: {
                                HStack {
                                    Text("Cook").plType(.body)
                                    Spacer()
                                    Text(remoteCookName(remote)).plType(.body, .semibold)
                                    Image(systemName: "slider.horizontal.3").font(.footnote)
                                }.foregroundStyle(Color.ink).frame(minHeight: 44)
                            }
                            MicroLabel("Something else")
                        }
                    } else if notice != nil {
                        // The night this page was changing is gone: somebody
                        // else took it off the plan while this edit was on
                        // the wire, and `write` answers that with a refusal
                        // and drops the entry. The card goes with it, so
                        // without this the one sentence explaining where the
                        // night went would have nowhere to be drawn, and the
                        // page would silently become an empty night.
                        noticeRow
                    }

                    // Every one of these writes the night this page is
                    // changing, so none of them is offered on a night that
                    // is already on its way off the plan. The page is the
                    // delete's answer now; planning something here is a tap
                    // away once the household has it, and this phone's own
                    // night on the same slot was never blocked at all.
                    if !going {
                        if !recipes.isEmpty {
                            OptionRow(
                                icon: "wand.and.stars",
                                title: "Pick for me",
                                detail: "Matched to the weather and what your household eats."
                            ) { pickForMe() }
                        }

                        OptionRow(
                            icon: "book.closed",
                            title: "Choose a recipe",
                            detail: "\(recipes.count) \(recipes.count == 1 ? "dish" : "dishes") your household already knows."
                        ) { route = .picker }

                        OptionRow(
                            icon: "plus.circle",
                            title: "Add a recipe",
                            detail: "Save it and plan it in one go."
                        ) { route = .newRecipe }

                        OptionRow(
                            icon: "fork.knife.circle",
                            title: "Eating out",
                            detail: "Counts as a planned night."
                        ) { markEatingOut() }

                        OptionRow(
                            icon: "bubble.and.pencil",
                            title: "Ask the Table",
                            detail: "Ask what everyone wants, or put up a poll."
                        ) { route = .ask }

                        // The one row here that cannot write the night this
                        // page is about. A gathering carries guests, a time
                        // and a calendar event, and the household record
                        // carries none of the three, so there is nothing to
                        // write it into.
                        //
                        // Offered on a household night it took GatheringSheet's
                        // else branch, because `meal` is nil on that path, and
                        // inserted a fresh PlannedMeal on a slot the household
                        // had already filled. The day then drew two dinners,
                        // the week hero swapped to the private one, and nobody
                        // else in the household ever saw the gathering. Every
                        // other row on this page writes the household record,
                        // so nothing on screen said which one went elsewhere.
                        if remote == nil {
                            OptionRow(
                                icon: "party.popper",
                                title: "Plan a gathering",
                                detail: "Guests, a time, and an event in your calendar."
                            ) { route = .gathering }
                        } else {
                            Text("A gathering has guests, a time and a calendar event, so it goes on a night of your own.")
                                .plType(.footnote)
                                .foregroundStyle(Color.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                // The scroll content, not a sibling of the ScrollView: a
                // ScrollView takes whatever height the detent gives it, so
                // measuring beside it feeds the detent its own answer and the
                // sheet walks itself taller every pass.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
        }
        // Six rows, two of them conditional, under a masthead whose caption
        // is conditional too. `.large` left roughly a third of the screen
        // empty below the last option. Measured instead, with `.large` still
        // available for the type sizes that need it.
        .presentationDetents([.height(mastheadHeight + contentHeight), .large])
        .presentationDragIndicator(.visible)
        .plTapOutsideToDismiss()
        .sheet(item: $route) { destination in
            switch destination {
            case .picker:
                // Switches the route rather than dismissing itself first.
                RecipePickerSheet(date: date, onWriteNew: { route = .newRecipe }) { recipe in
                    // `plate` closes the sheet: at once for this phone's own
                    // night, and on the zone's answer for a household one.
                    plate(recipe, tagline: "")
                }
            case .newRecipe:
                RecipeEditorView(hidePlateShortcut: true) { recipe in
                    plate(recipe, tagline: "")
                }
            case .ask:
                AskComposerSheet(date: date) {
                    dismiss()
                    askTheTable()
                }
            case .gathering:
                GatheringSheet(date: date, attachedMeal: meal, slot: slot) {
                    dismiss()
                }
            }
        }
    }

    // MARK: Pieces

    /// What the last write answered. Not a problem colour: queued is not a
    /// failure, and `ink` is what the page reads its own sentences in.
    @ViewBuilder
    private var noticeRow: some View {
        if let notice {
            Text(notice)
                .plType(.footnote)
                .foregroundStyle(Color.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 6)
        }
    }

    private func currentMealCard(_ meal: PlannedMeal) -> some View {
        HStack(spacing: 12) {
            Group {
                if let data = meal.recipe?.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                } else if let recipe = meal.recipe {
                    DishView(recipe: recipe, diameter: 52)
                } else {
                    Circle()
                        .strokeBorder(Color.hairline, lineWidth: 2)
                        .frame(width: 52, height: 52)
                        .overlay {
                            Image(systemName: "fork.knife.circle")
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(Color.inkSecondary)
                        }
                }
            }
            .plDishShadow()
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.title)
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                if let cook = meal.cook {
                    Text(cook.isMe ? "You cook" : "\(cook.name) cooks")
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
            }
            Spacer()
            Button {
                Haptic.plate()
                withAnimation(.plSnap) { context.delete(meal) }
            } label: {
                Image(systemName: "trash")
                    .accessibilityLabel("Remove this meal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.inkSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Color.navHairline))
    }


    /// A household night, in the local card's geometry because peers look
    /// like peers: the same 52pt dish, the same title, the cook line under
    /// it, and the same one control on the right, which takes the night off
    /// the plan for everybody rather than only here.
    private func remoteNightCard(_ entry: PlanLedger.Entry) -> some View {
        HStack(spacing: 12) {
            // A 26pt radius on a 52pt square is the local card's circle,
            // drawn by the component that already knows what to do when a
            // night has no photograph. Peers look like peers, and these two
            // cards are peers on one page.
            RecipeArtwork(
                data: PlanLedger.shared.photo(for: entry.recordName),
                title: entry.title, ratio: 1, radius: 26
            )
            .frame(width: 52, height: 52)
            .plDishShadow()
            // Title, then who cooks, then whose night it is: the order
            // `RemotePlanRow` uses, because the row and this card are the
            // same night on two screens.
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .plType(.body, .bold)
                    .foregroundStyle(Color.ink)
                if let cook = PlanLedger.shared.cookLine(for: entry) {
                    Text(cook)
                        .plType(.caption, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                }
                Text(remoteCaption(entry))
                    .plType(.caption, .semibold)
                    .foregroundStyle(Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                Haptic.plate()
                send(PlanShare.Edit(deleting: entry), closing: true)
            } label: {
                // Working, in `TomatoPillButton`'s shape: the spinner takes
                // the glyph's place inside the same 44pt target, so the card
                // does not move while the zone answers and the trash cannot
                // be pressed a second time on a night already going.
                //
                // Once the delete is queued the control is genuinely off,
                // and an off control's icon is what `inkFaint` is for: the
                // night is already coming off the plan and pressing this
                // again would queue nothing new.
                Group {
                    if inFlight == .delete {
                        ProgressView()
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(entry.isGoing ? Color.inkFaint : Color.inkSecondary)
                    }
                }
                .accessibilityLabel(deleteLabel(entry))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .disabled(sending || entry.isGoing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.canvas, in: RoundedRectangle(cornerRadius: Radius.row, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(Color.navHairline))
    }

    /// Whose night it is, and whether the last change has reached the
    /// household. A change that is still on this phone says so: the card
    /// already shows the new dish, and this is what keeps that from being a
    /// claim that everybody can see it.
    /// What to say on a night this phone planned that the household has
    /// since changed. Nil when nothing is contested, which is almost always.
    ///
    /// Two facts and no advice. "Riley changed this night on their phone"
    /// is a recorded action by a named person, which is what the
    /// notification law asks of every sentence about somebody else. "Your
    /// plan still says Tacos" is what is under the reader's thumb. The app
    /// does not say which should win, because it does not know.
    ///
    /// A record written before `editorID` names nobody, and this may not
    /// invent a "Someone": the digest's own ladder refuses to name the
    /// author for another person's edit and this makes the same call. It
    /// loses the name and keeps both facts.
    ///
    /// The second clause is dropped rather than left dangling when this
    /// phone's night has no title to quote.
    private func contestLine(for meal: PlannedMeal) -> String? {
        guard let id = meal.shoppingID,
              let contest = PlanShare.contest(for: "plan-\(id)") else { return nil }
        let who = contest.by.trimmingCharacters(in: .whitespaces)
        let opening = who.isEmpty
            ? "This night was changed on another phone."
            : "\(PlanLedger.Entry.firstName(who)) changed this night on their phone."
        let mine = contest.mineTitle.trimmingCharacters(in: .whitespaces)
        guard !mine.isEmpty else { return opening }
        return "\(opening) Your plan still says \(mine)."
    }

    private func remoteCaption(_ entry: PlanLedger.Entry) -> String {
        // The row's own words, from the row: the card and the row are the
        // same night on two screens, and a second copy of the sentence is a
        // second sentence waiting to drift.
        RemotePlanRow.caption(for: entry)
    }

    /// What the trash is doing, in the three states it can be in. A control
    /// that is off has to say why it is off, or VoiceOver reads a button
    /// that answers nothing.
    private func deleteLabel(_ entry: PlanLedger.Entry) -> String {
        Self.deleteLabel(going: entry.isGoing, deleting: inFlight == .delete)
    }

    static func deleteLabel(going: Bool, deleting: Bool) -> String {
        if going { return "This night is coming off the plan" }
        return deleting ? "Taking this night off the plan" : "Take this night off the plan"
    }

    /// Which answers close the page. Only the one that happened: a night
    /// kept on this phone, a night somebody else changed first and a night
    /// the zone refused all have something to say, and the page is the only
    /// thing left to say it on once a delete has taken the row away.
    static func closes(_ outcome: PlanShare.WriteOutcome) -> Bool {
        if case .landed = outcome { return true }
        return false
    }

    /// The cook as the menu shows it. By identity, never by name.
    private func remoteCookName(_ entry: PlanLedger.Entry) -> String {
        if PlanLedger.shared.isMine(cook: entry) { return "You" }
        return entry.hasCook ? entry.cookName : "Unassigned"
    }

    /// "Plan the night" is dinner's line and stays dinner's line; the other
    /// slots say what they are.
    private var planLabel: String {
        slot == .dinner ? "Plan the night" : "Plan \(slot.title.lowercased())"
    }

    private var dayTitle: String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    /// "Nate planned Tacos for this night." Dinner's line; another slot
    /// names itself, so breakfast never claims the night.
    private var remotePlanLine: String? {
        // Not when this page is changing that very night: the card below
        // says whose it is, and the sentence would be about the thing the
        // person is already looking at. Nor about a night that is going:
        // "Nate planned Tacos for this night" would be warning somebody off
        // a slot they have just taken off the plan themselves.
        guard remote == nil,
              let entry = PlanLedger.shared.plans(on: date, slot: slot).first(where: { !$0.isGoing })
        else { return nil }
        let occasion = slot == .dinner ? "this night" : slot.title.lowercased()
        return "\(entry.authorFirstName) planned \(entry.title) for \(occasion)."
    }

    private var contextLine: String? {
        var parts: [String] = []
        if let day = forecast.forecast(for: date) {
            parts.append("\(day.conditionDescription), high \(Int(day.highF.rounded()))°")
        }
        // How full the day is, not the name of one thing on it. A day with
        // six entries was being described by whichever one came back first.
        if showCalendarEvents, let load = events.load(on: date) {
            parts.append(load)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func pickForMe() {
        let engine = SuggestionEngine(recipes: recipes, members: members)
        let thisWeek = Set(
            meals.filter {
                let delta = Calendar.current.dateComponents([.day], from: .now.startOfDay, to: $0.date).day ?? 99
                return (0..<7).contains(delta)
            }.compactMap { $0.recipe?.persistentModelID }
        )
        // The row promises "something that suits the weather" and the header
        // right above shows the forecast — passing nil here made the engine's
        // biggest weight dead code and the promise a coin toss.
        let day = forecast.forecast(for: date)
        let ranked = engine.suggestions(for: date, forecast: day, limit: recipes.count)
        guard let pick = ranked.first(where: { !thisWeek.contains($0.recipe.persistentModelID) }) ?? ranked.first
        else {
            // The row is hidden when there is nothing to pick, so reaching
            // here means something else went wrong. Say so with a buzz
            // rather than looking like a dead button.
            Haptic.warn()
            return
        }
        let recipe = pick.recipe
        let minutes = recipe.totalMinutes
        // The magic move earns the plate-weight thump, not a chrome tick.
        Haptic.plate()
        // Say why — "Picked for you · grill weather" proves the engine
        // looked out the window.
        let why = pick.reason.components(separatedBy: ", ").first ?? ""
        let tagline = !why.isEmpty ? "Picked for you · \(why)"
            : (minutes > 0 ? "Picked for you · \(Recipe.durationText(minutes))" : "Picked for you")
        plate(recipe, tagline: tagline)
    }

    /// One edit on its way to the household, and the sentence it earns.
    ///
    /// Optimism belongs in the ledger, not in the copy: `PlanShare.write`
    /// moves the row under the finger and marks it as not landed, and this
    /// only says what the zone answered.
    ///
    /// `closing` is the actions that used to dismiss the sheet the instant
    /// they sent: the dish, Eating out, and taking the night off. They now
    /// close on `.landed` only. The other three answers keep the sheet up
    /// and put the sentence in the row under the card, because a page that
    /// is gone cannot tell anybody anything and a deleted night has no row
    /// left to tell them with.
    private func send(_ edit: PlanShare.Edit, photo: Data? = nil, closing: Bool = false) {
        // One write at a time on one night. Two in flight are two
        // fetch-and-saves racing on one record, and the second would read a
        // `seenAt` the first is about to move, so the person would be told
        // somebody got there first about their own tap.
        guard !sending else { return }
        notice = nil
        inFlight = edit.kind
        Task { @MainActor in
            let outcome = await PlanShare.write(edit, photo: photo)
            inFlight = nil
            notice = Self.sentence(for: outcome)
            // A refusal and a version somebody else got in first are both
            // the app saying no. Queued is not: the change is kept and it
            // will go, so it earns a sentence and no buzz.
            switch outcome {
            case .landed, .queued: break
            case .theirs, .refused: Haptic.warn()
            }
            if closing, Self.closes(outcome) { dismiss() }
        }
    }

    /// What each answer says out loud, in one place so a test can read it.
    /// Nil is the only answer that needs no sentence: the night is in the
    /// zone, and the page that would have carried the words is closing.
    static func sentence(for outcome: PlanShare.WriteOutcome) -> String? {
        switch outcome {
        case .landed: nil
        // The queue's own words. "It goes out when this phone is back
        // online" was being said about an account that is fine and a zone
        // that would not read, so the write names its cause and this only
        // repeats it.
        case .queued(let why): why
        case .theirs: "This night changed on another phone first. That version is showing."
        case .refused(let why): why
        }
    }

    /// The servings on a household night. The row moves now; the zone hears
    /// the number they stopped on, because a stepper held down is one
    /// intention and each write is a fetch and a save.
    private func changeServings(_ count: Int, on entry: PlanLedger.Entry) {
        var edit = PlanShare.Edit(changing: entry)
        edit.servings = count
        PlanLedger.shared.applyLocally(edit)
        // Parked before the debounce, not after it. Everywhere else on this
        // path the edit is on disk before the row moves, so a kill loses
        // nothing; here the row moved and then waited 700ms, and a kill in
        // that window left a ledger showing six servings, the stray sweep
        // clearing the one mark that said so, and nothing anywhere ever
        // sending it. `enqueue` folds, so a stepper held down is still one
        // entry, and a pass that drains it early is a save of the number the
        // person is looking at.
        PlanShare.enqueue(edit)
        servingsWrite?.cancel()
        servingsWrite = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            // Wait for whatever is already on the wire rather than being
            // turned away by it. The row is showing this number and nothing
            // else will ever send it: a dropped write here leaves a night
            // saying six servings on this phone and four on every other,
            // with the stray sweep quietly clearing the "Not sent yet" that
            // was the only sign.
            while sending {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
            }
            guard let latest = PlanLedger.shared.entry(entry.recordName) else { return }
            var settled = PlanShare.Edit(changing: latest)
            settled.servings = latest.servings
            send(settled)
        }
    }

    /// Who cooks a household night. By identity, never by name: the wire
    /// carries the cook's participant id, this phone's own id when the cook
    /// is the person holding it, and "" so a reader never guesses. A seat
    /// that was only invited travels without a name, because a name typed
    /// five seconds ago is not a cook.
    private func changeCook(_ member: HouseholdMember?, on entry: PlanLedger.Entry) {
        Haptic.select()
        var edit = PlanShare.Edit(changing: entry)
        guard let member else {
            edit.cookID = ""
            edit.cookName = ""
            edit.cookColorHex = ""
            edit.cookSeat = ""
            send(edit)
            return
        }
        var id = member.participantID ?? ""
        if id.isEmpty, let record = member.userRecordName, !record.isEmpty { id = record }
        if id.isEmpty, member.isMe { id = TableIdentity.cached }
        edit.cookID = id
        edit.cookName = member.seat == .invited ? "" : member.name
        edit.cookColorHex = member.colorHex
        edit.cookSeat = member.seat.rawValue
        send(edit)
    }

    private func markEatingOut() {
        if let remote {
            Haptic.plate()
            var edit = PlanShare.Edit(changing: remote)
            edit.title = "Eating out"
            edit.tagline = "Night off the stove"
            edit.cookID = ""
            edit.cookName = ""
            edit.cookColorHex = ""
            edit.cookSeat = ""
            edit.hasRecipe = false
            edit.recipeMinutes = 0
            edit.recipeOriginKey = ""
            // A night nobody is cooking may not keep the last dish's
            // photograph.
            edit.photo = .clear
            // The sheet closes when the zone says it took it, and stays to
            // say so when it did not.
            send(edit, closing: true)
            return
        }
        Haptic.plate()
        withAnimation(.plPop) {
            if let meal {
                meal.recipe = nil
                meal.customTitle = "Eating out"
                meal.tagline = "Night off the stove"
                meal.cook = nil
            } else {
                let meal = PlannedMeal(date: date, slot: slot, customTitle: "Eating out")
                meal.tagline = "Night off the stove"
                context.insert(meal)
            }
        }
        dismiss()
    }

    private func plate(_ recipe: Recipe, tagline: String) {
        if let remote {
            // The household night becomes this dish. The cook is left
            // alone: changing what is for dinner is not a claim about who
            // is at the stove, and the rota's answer is about this phone's
            // own week.
            Haptic.plate()
            var edit = PlanShare.Edit(changing: remote)
            edit.title = recipe.title
            edit.tagline = tagline
            edit.servings = recipe.servings
            edit.hasRecipe = true
            edit.recipeMinutes = recipe.totalMinutes
            edit.recipeOriginKey = recipe.originID
            edit.photo = recipe.photoData == nil ? .clear : .send
            // No bell row here. A local plate posts one about the night this
            // phone planned; this is the reader's own action on somebody
            // else's night, and a notice about your own action is the rule
            // docs/notifications.md breaks for nothing.
            //
            // The dismissal belongs to the answer, not to the tap: every
            // caller below reaches this through `plate`, so none of them
            // closes the sheet on its own any more.
            send(edit, photo: recipe.photoData, closing: true)
            return
        }
        Haptic.plate()
        let cook = CookRotation.cook(for: date, members: members, meals: meals)
        withAnimation(.plPop) {
            if let meal {
                meal.recipe = recipe
                meal.customTitle = ""
                meal.servings = recipe.servings
                meal.cook = cook
                meal.tagline = tagline
            } else {
                context.insert(PlannedMeal(
                    date: date, slot: slot, recipe: recipe,
                    servings: recipe.servings, cook: cook, tagline: tagline
                ))
            }
        }
        let cookName = (cook?.isMe ?? true) ? "you" : (cook?.name ?? "someone")
        Notifier.post(
            .mealPlanned, actor: cook?.name ?? "",
            body: "\(dayTitle): \(recipe.title). \(cookName.capitalized) cook\(cookName == "you" ? "" : "s").",
            into: context
        )
        // The moment to ask, and the only one. They have just said they
        // intend to cook on a given night, so "shall I remind you" continues
        // their own thought instead of interrupting it. iOS grants exactly
        // one prompt, and one spent at launch is one spent before the app
        // has done anything worth being reminded about.
        Task {
            await NotificationScheduler.askOnce()
            await NotificationScheduler.rebuild(meals: meals)
        }
        // This phone's own store answered before the line above ran, so the
        // local night closes the sheet here rather than at each caller: one
        // place decides, and a household night's dismissal can wait for the
        // zone without every caller learning the difference.
        dismiss()
    }
}

/// An open ask for the table, optionally with a poll — give the household
/// choices and let the votes cook.
struct AskComposerSheet: View {
    let date: Date
    var onPosted: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    @State private var caption = ""
    @State private var options: [String] = []
    @State private var optionEntry = ""
    @State private var tagged: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Ask the Table")
                Text(dayName)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField(defaultCaption, text: $caption, axis: .vertical)
                        .plType(.body, .medium)
                        .lineLimit(2...4)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    VStack(alignment: .leading, spacing: 8) {
                        MicroLabel("Poll · optional")
                        ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                            HStack {
                                Image(systemName: "circle")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.inkFaint)
                                Text(option)
                                    .plType(.body)
                                    .foregroundStyle(Color.ink)
                                Spacer()
                                Button {
                                    Haptic.tap()
                                    withAnimation(.plSnap) { options.remove(at: index) }
                                } label: {
                                    Image(systemName: "xmark")
                                        .accessibilityLabel("Remove option")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(Color.inkSecondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.pressable)
                            }
                            .padding(.horizontal, 4)
                        }
                        if options.count < 4 {
                            HStack(spacing: 8) {
                                TextField("Add an option", text: $optionEntry)
                                    .plType(.body, .medium)
                                    .padding(.horizontal, 14)
                                    .frame(minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                                    .onSubmit(addOption)
                                    .plTappableField()
                                Button {
                                    addOption()
                                } label: {
                                    Circle()
                                        .strokeBorder(Color.hairline, lineWidth: 1.5)
                                        .frame(width: 40, height: 40)
                                        .overlay {
                                            Image(systemName: "plus")
                                                .accessibilityLabel("Add option")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(Color.ink)
                                        }
                                        .plTapTarget()
                                }
                                .buttonStyle(.pressable)
                                .disabled(optionEntry.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    if members.count > 1 {
                        VStack(alignment: .leading, spacing: 8) {
                            MicroLabel("Tag someone")
                            HStack(spacing: 8) {
                                ForEach(members.filter { !$0.isMe }, id: \.persistentModelID) { member in
                                    let active = tagged.contains(member.name)
                                    Button {
                                        Haptic.tap()
                                        withAnimation(.plSnap) {
                                            if active { tagged.remove(member.name) } else { tagged.insert(member.name) }
                                        }
                                    } label: {
                                        HStack(spacing: 5) {
                                            AvatarCircle(member: member, size: 22)
                                            Text("@\(member.name)")
                                                .plType(.micro)
                                                .plActionLabel()
                                        }
                                        .foregroundStyle(active ? Color.canvas : Color.ink)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 36)
                                        .background {
                                            if active {
                                                Capsule().fill(Color.ink)
                                            } else {
                                                Capsule().strokeBorder(Color.hairline)
                                            }
                                        }
                                    }
                                    .buttonStyle(.pressable)
                                    .accessibilityAddTraits(active ? .isSelected : [])
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(title: options.isEmpty ? "Post" : "Post with poll") {
                post()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    /// The night is only baked into the caption text, so the words have to
    /// carry the date — a bare "friday" three weeks of scrollback later
    /// means the wrong Friday to every voter.
    private var dayName: String {
        if Calendar.current.isDateInToday(date) { return "Tonight" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private var defaultCaption: String {
        if Calendar.current.isDateInToday(date) { return "What should we make tonight?" }
        if Calendar.current.isDateInTomorrow(date) { return "What should we make tomorrow?" }
        return "What should we make on \(dayName)?"
    }

    private func addOption() {
        let entry = optionEntry.trimmingCharacters(in: .whitespaces)
        guard !entry.isEmpty, options.count < 4 else { return }
        Haptic.tap()
        withAnimation(.plSnap) { options.append(entry) }
        optionEntry = ""
    }

    private func post() {
        Haptic.plate()
        let owner = members.me
        let post = TablePost(
            authorName: owner?.name ?? "Me",
            authorColorHex: owner?.colorHex ?? "FF5A3C",
            caption: caption.isEmpty ? defaultCaption : caption,
            kind: "ask"
        )
        post.pollOptions = options
        post.pollCounts = Array(repeating: 0, count: options.count)
        post.taggedNames = Array(tagged)
        context.insert(post)
        // The household hears about it — that's the point of asking.
        Notifier.post(
            .askPosted, actor: owner?.name ?? "Me",
            body: options.isEmpty
                ? "\(owner?.name ?? "Someone") asked the Table about \(dayName)."
                : "\(owner?.name ?? "Someone") started a poll for \(dayName).",
            into: context
        )
        dismiss()
        onPosted()
    }
}

/// A gathering — dinner party, holiday, friends over. Lands in the plan
/// and mirrors into Apple Calendar so the rest of life can see it.
struct GatheringSheet: View {
    let date: Date
    var attachedMeal: PlannedMeal?
    var slot: MealSlot = .dinner
    var onDone: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var location = ""
    @State private var guests = 4
    @State private var startTime: Date
    @State private var syncToCalendar = true
    @State private var syncResult: String?
    /// Set once the gathering lands in the store. A calendar failure used to
    /// leave "Save gathering" live over a save the user believed failed —
    /// tapping again threw a second party and rang the bell twice.
    @State private var savedGathering: Gathering?

    init(date: Date, attachedMeal: PlannedMeal? = nil, slot: MealSlot = .dinner, onDone: @escaping () -> Void = {}) {
        self.date = date
        self.attachedMeal = attachedMeal
        self.slot = slot
        self.onDone = onDone
        let evening = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: date) ?? date
        _startTime = State(initialValue: evening)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                MicroLabel("Plan a gathering")
                Text(dayLabel)
                    .plType(.title)
                    .foregroundStyle(Color.ink)
            }
            .padding(.top, 22)
            .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Sunday dinner party", text: $title)
                        .plType(.body)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    TextField("Our place", text: $location)
                        .plType(.body, .medium)
                        .padding(14)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .plTappableField()

                    HStack {
                        Text("Guests")
                            .plType(.body, .bold)
                            .foregroundStyle(Color.ink)
                        Spacer()
                        HStack(spacing: 14) {
                            stepperButton("minus", "One fewer guest") { if guests > 1 { guests -= 1 } }
                            Text("\(guests)")
                                .plType(.heading, .bold)
                                .foregroundStyle(Color.ink)
                                .frame(minWidth: 30)
                                .contentTransition(.numericText())
                            stepperButton("plus", "One more guest") { guests += 1 }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    DatePicker("Starts at", selection: $startTime, displayedComponents: .hourAndMinute)
                        .plType(.body, .bold)
                        .tint(Color.tomato)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color.fill)
                            .frame(width: 40, height: 40)
                            .overlay {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Color.ink)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Add to Apple Calendar")
                                .plType(.body, .bold)
                                .foregroundStyle(Color.ink)
                            Text("Adds an event you can invite guests from.")
                                .plType(.caption)
                                .foregroundStyle(Color.inkSecondary)
                        }
                        Spacer()
                        Toggle("", isOn: $syncToCalendar)
                            .labelsHidden()
                            .sensoryFeedback(.selection, trigger: syncToCalendar)
                            .tint(Color.basil)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairline))

                    if let syncResult {
                        Text(syncResult)
                            .plType(.caption, .semibold)
                            .foregroundStyle(Color.inkSecondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            TomatoPillButton(
                title: savedGathering == nil ? "Save gathering" : "Add to calendar",
                systemImage: savedGathering == nil ? "party.popper" : "calendar.badge.plus"
            ) {
                save()
            }
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 14)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func stepperButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptic.tap()
            withAnimation(.plSnap) { action() }
        } label: {
            Circle()
                .strokeBorder(Color.hairline, lineWidth: 1.5)
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: symbol)
                        .accessibilityLabel(label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.ink)
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private var dayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: date)
    }

    private func save() {
        Haptic.plate()
        let gathering: Gathering
        if let existing = savedGathering {
            // Second pass only ever means "the calendar didn't take" — the
            // party itself is already saved and on the plan.
            gathering = existing
        } else {
            gathering = Gathering(
                title: title.trimmingCharacters(in: .whitespaces),
                startDate: startTime,
                guestCount: guests,
                location: location.trimmingCharacters(in: .whitespaces)
            )
            context.insert(gathering)
            if let attachedMeal {
                attachedMeal.gathering = gathering
            } else {
                // A gathering planned on an open night used to save into a
                // record no screen shows — the plate haptic fired, the bell
                // rang, and the night still read "Nothing plated" everywhere.
                // The party occupies the night it's on.
                let meal = PlannedMeal(date: date, slot: slot, customTitle: gathering.title)
                meal.gathering = gathering
                meal.tagline = "Cooking for \(guests)"
                context.insert(meal)
            }
            Notifier.post(
                .mealPlanned, actor: "",
                body: "\(gathering.title), \(dayLabel). Cooking for \(guests).",
                into: context
            )
            savedGathering = gathering
        }
        if syncToCalendar {
            Task {
                do {
                    try await CalendarSync.shared.sync(gathering)
                    syncResult = "Added to your calendar"
                    try? await Task.sleep(for: .seconds(1))
                    dismiss()
                    onDone()
                } catch {
                    // The raw EventKit error read like the save failed.
                    // It didn't — say what's true, in our voice.
                    syncResult = "The gathering is saved. Your calendar wasn't updated."
                }
            }
        } else {
            dismiss()
            onDone()
        }
    }
}
