import Foundation

/// One-shot UI-test launch flags. `consume` returns true exactly once per
/// process, so re-entering a tab can never replay a hook — the grocery sheet
/// used to reopen on every return to the plan when the app was launched
/// with `-plated-open-grocery`.
@MainActor
enum LaunchFlags {
    private static var consumed = Set<String>()

    static func consume(_ flag: String) -> Bool {
        guard ProcessInfo.processInfo.arguments.contains(flag),
              !consumed.contains(flag) else { return false }
        consumed.insert(flag)
        return true
    }
}
