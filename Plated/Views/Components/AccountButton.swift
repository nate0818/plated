import SwiftUI
import SwiftData

/// A consistent account door on detail screens, without changing their stack.
struct AccountButton: View {
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]
    @State private var showing = false
    var body: some View {
        Button { showing = true } label: {
            AvatarCircle(initials: members.first(where: \.isOwner)?.initials ?? "Me", tone: .neutralPair, size: 32, photo: members.first(where: \.isOwner)?.photoData)
                .plTapTarget()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Your profile and settings")
        .sheet(isPresented: $showing) {
            NavigationStack {
                if let owner = members.first(where: \.isOwner) {
                    PersonProfileView(personName: owner.name, colorHex: owner.colorHex, memberID: owner.persistentModelID)
                } else {
                    SettingsSheet()
                }
            }.presentationDragIndicator(.visible).plTapOutsideToDismiss()
        }
    }
}
