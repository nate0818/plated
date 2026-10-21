import SwiftUI
import SwiftData

/// The consistent account door. A face opens the person's actual profile as
/// a pushed page, the same way tapping any other face does. Only the full-
/// screen cooking session uses a cover because it has no navigation stack.
struct AccountButton: View {
    enum Presentation { case push, cover }

    var presentation: Presentation = .push
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var showing = false

    private var me: HouseholdMember? { members.readable.me }

    @ViewBuilder
    var body: some View {
        if presentation == .push {
            NavigationLink {
                profile
            } label: {
                avatar
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptic.tap() })
            .accessibilityLabel("Your profile")
            .accessibilityHint("Opens your profile, household and settings.")
        } else {
            Button {
                Haptic.tap()
                showing = true
            } label: {
                avatar
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Your profile")
            .accessibilityHint("Opens your profile, household and settings.")
            .fullScreenCover(isPresented: $showing) {
                NavigationStack { profile }
            }
        }
    }

    private var avatar: some View {
        AvatarCircle(
            initials: me?.initials ?? "Me",
            tone: .neutralPair,
            size: 36,
            photo: me?.photoData
        )
        .plTapTarget()
    }

    private var profile: some View {
        Group {
            if let me {
                PersonProfileView(
                    personName: me.name,
                    colorHex: me.colorHex,
                    memberID: me.persistentModelID
                )
            } else {
                PersonProfileView(personName: "Me", colorHex: "", memberID: nil)
            }
        }
    }
}
