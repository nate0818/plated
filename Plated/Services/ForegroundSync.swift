import Foundation

/// A single app-lifetime reader. Pushes are hints; a visible conversation
/// must keep moving even when iOS coalesces or withholds a silent push.
@MainActor
final class ForegroundSync {
    static let shared = ForegroundSync(
        pull: {
            await TablePull.pull(reason: "automatic")
            SocialPush.requestSync()
        },
        succeeded: { TablePull.lastReadSucceeded },
        engaged: {
            let screen = Presence.shared
            return screen.openPost != nil || screen.feedVisible
                || screen.activityVisible || screen.householdVisible
        }
    )

    private let pull: () async -> Void
    private let succeeded: () -> Bool
    private let engaged: () -> Bool
    private let sleep: (TimeInterval) async throws -> Void
    private var worker: Task<Void, Never>?

    init(
        pull: @escaping () async -> Void,
        succeeded: @escaping () -> Bool,
        engaged: @escaping () -> Bool,
        sleep: @escaping (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        }
    ) {
        self.pull = pull
        self.succeeded = succeeded
        self.engaged = engaged
        self.sleep = sleep
    }

    func setActive(_ active: Bool) {
        guard active else {
            worker?.cancel()
            worker = nil
            return
        }
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            guard let self else { return }
            var failures = 0
            while !Task.isCancelled {
                await self.pull()
                guard !Task.isCancelled else { return }
                failures = self.succeeded() ? 0 : min(failures + 1, 4)
                do {
                    try await self.sleep(Self.delay(engaged: self.engaged(), failures: failures))
                } catch { return }
            }
        }
    }

    static func delay(engaged: Bool, failures: Int) -> TimeInterval {
        let base: TimeInterval = engaged ? 5 : 15
        return min(60, base * pow(2, Double(max(0, min(failures, 4)))))
    }
}

/// A structured task-group race still waits for its cancelled children.
/// CloudKit awaits need not observe cancellation, so the OS callback needs
/// its own one-shot deadline while the shared reader finishes independently.
@MainActor
final class BackgroundFetchCompletion {
    private var completion: ((Bool) -> Void)?
    private var deadline: Task<Void, Never>?

    init(seconds: TimeInterval = 24, completion: @escaping (Bool) -> Void) {
        self.completion = completion
        deadline = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) }
            catch { return }
            self?.finish(false)
        }
    }

    func finish(_ succeeded: Bool) {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        deadline = nil
        completion(succeeded)
    }
}
