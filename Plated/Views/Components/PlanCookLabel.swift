import SwiftUI

/// The dinner's cook is a role of its own, not the recipe author or the person
/// who added the plan. Used by both local assignment and shared-plan editing.
struct PlanCookLabel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let heading: String
    let name: String
    var member: HouseholdMember?
    var fallbackName: String?

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        layout {
            if let member {
                AvatarCircle(member: member, size: 32).accessibilityHidden(true)
            } else if let fallbackName {
                AvatarCircle(initials: PlanRowVoice.initials(fallbackName), tone: .neutralPair, size: 32).accessibilityHidden(true)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .plType(.heading).foregroundStyle(Color.olive).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                MicroLabel(heading)
                Text(name).plType(.body, .semibold).foregroundStyle(Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            Text("Change").plType(.footnote, .semibold).foregroundStyle(Color.accentText)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
