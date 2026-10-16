import Foundation

/// Hard empty-night copy for Plan (Slice 2).
/// Source: EDIT-PROFILE-AND-PLAN-EMPTY-COPY-STAMP-2026-09-12 §B.
/// Soft ambient / "Nothing plated" / "Something good starts here." are killed.
enum PlanEmptyCopy {
    /// Empty list-row title (dense, like a filled meal row).
    static let rowTitle = "No meal planned yet"

    /// Past empty list-row / detail title.
    static let pastRowTitle = "No meal planned"

    /// Narrow chip on the row. VoiceOver uses `planNightA11y`.
    static let rowAction = "Plan"

    /// Full-width primary CTA.
    static let planNight = "Plan the night"

    static let planNightA11y = "Plan the night"

    static let noOneAssigned = "No one assigned"

    static let eatingOut = "Eating out"

    static let eatOutAction = "Eat out"

    /// Featured / hero subcopy when the night is open (future).
    static let heroSubcopy = "Add a meal, or mark eating out."

    /// Day-detail body (future + past).
    static let detailBody = "No cook yet. Plan a meal, eat out, or assign someone."

    /// Optional ambient — complete useful line only; omit when density is better.
    static let ambientChoices = [
        "Tonight's still open.",
        "This night's free.",
        "Dinner's not set.",
    ]

    static func rowTitle(past: Bool) -> String {
        past ? pastRowTitle : rowTitle
    }

    static func heroTitle(past: Bool) -> String {
        past ? pastRowTitle : rowTitle
    }

    // MARK: Slice 3 — long-press (past + future), continuum

    /// Long-press / detail: plan a meal.
    static let planMealAction = "Plan a meal"

    /// Long-press / detail: assign another cook.
    static let assignSomeoneAction = "Assign someone"

    /// Long-press / detail: self as cook.
    static let illCookAction = "I'll cook"

    /// Long-press clear.
    static let clearNightAction = "Clear night"

    /// Continuum eyebrow after this week.
    static let nextWeekEyebrow = "Next week"

}
