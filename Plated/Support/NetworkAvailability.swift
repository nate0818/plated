import Foundation
import Network
import Observation

/// Device path information, not an Internet or CloudKit reachability promise.
/// A path that requires a connection is still unknown; only an explicit
/// unsatisfied observation supports the user-facing waiting-for-connection copy.
@MainActor
@Observable
final class NetworkAvailability {
    static let shared = NetworkAvailability()

    enum State: Equatable, Sendable {
        case unknown, available, unavailable
    }

    private(set) var state: State = .unknown
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let observation = Self.classify(path.status)
            Task { @MainActor [weak self] in self?.state = observation }
        }
        // One app-lifetime monitor. Views hold the shared object; navigating
        // between tabs does not create or restart network monitors.
        monitor.start(queue: DispatchQueue(label: "com.plated.network-path"))
    }

    nonisolated static func classify(_ status: NWPath.Status) -> State {
        switch status {
        case .satisfied: .available
        case .unsatisfied: .unavailable
        case .requiresConnection: .unknown
        @unknown default: .unknown
        }
    }
}
