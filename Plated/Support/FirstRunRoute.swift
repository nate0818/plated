import Foundation

/// Legacy completion remains authoritative; installing the shorter flow must
/// never put an existing household through setup again.
enum FirstRunRoute: Equatable {
    case loading
    case welcome
    case invitation
    case app(AppTab)

    static func resolve(ready: Bool, signedIn: Bool, completedSetup: Bool, hasInvitation: Bool) -> Self {
        guard ready else { return .loading }
        guard signedIn else { return .welcome }
        if hasInvitation && !completedSetup { return .invitation }
        return .app(completedSetup ? .week : .cookbook)
    }
}
