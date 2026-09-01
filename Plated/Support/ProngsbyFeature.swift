import Foundation

/// Prongsby is parked.
///
/// The fork's whole mind stays in the tree — `ProngsbyBrain`, `ProngsbyMind`,
/// `ProngsbyView`, the perch and the Siri intent are all still compiled and
/// still tested. This is the single switch that decides whether any of it
/// reaches a finger. Flip it to `true` and he comes back exactly as he was:
/// the perch floats above the bar again, the sheet opens off it, and "Ask
/// Prongsby" answers Siri.
///
/// Parked rather than deleted because the decision was "for now" — and a
/// deletion that has to be recovered from git history is a decision that
/// costs more to reverse than it did to make.
enum ProngsbyFeature {
    /// The one place. Nothing else may branch on Prongsby's absence.
    static let isEnabled = false
}
