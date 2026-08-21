import SwiftUI
import Contacts

/// "Set a place" — inviting someone is laying a place setting for them.
/// Contacts are matched on-device; nothing leaves the phone.
struct ContactsView: View {
    let onDone: () -> Void

    /// Names the user seated, newline-separated. Real invites ride on CloudKit
    /// sharing later; until then the choice is kept, not thrown away.
    @AppStorage("pendingSeats") private var pendingSeatsRaw = ""

    struct Candidate: Identifiable {
        let id: String
        let name: String
        var seated: Bool = false
    }

    @State private var candidates: [Candidate] = []
    @State private var accessState: AccessState = .notAsked
    @State private var arrived = false

    enum AccessState { case notAsked, granted, denied }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                // Place settings around the table.
                HStack(spacing: -12) {
                    seatBubble("N", tone: .tomatoPair)
                    seatBubble("S", tone: .basilPair)
                    seatBubble("R", tone: .amberPair)
                    seatBubble("+", tone: .grapePair)
                }
                .padding(.bottom, 8)

                Text("Set your table")
                    .font(.gabarito(32, .extraBold))
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                Text("Plated is invite-only. No one sees your table unless you set a place for them — and you see only the tables that invite you.")
                    .font(.jakarta(15, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.top, 84)
            .padding(.horizontal, 28)
            .opacity(arrived ? 1 : 0)

            if accessState == .granted && !candidates.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach($candidates) { $candidate in
                            candidateRow($candidate)
                            if candidate.id != candidates.last?.id {
                                Divider().overlay(Color.hairlineSoft)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .background(Color.canvas)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.hero))
                    .overlay(RoundedRectangle(cornerRadius: Radius.hero).strokeBorder(Color.hairline))
                    .plCardShadow()
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                Spacer()
            }

            VStack(spacing: 12) {
                if accessState == .granted {
                    TomatoPillButton(title: "To my table") {
                        pendingSeatsRaw = candidates.filter(\.seated).map(\.name).joined(separator: "\n")
                        onDone()
                    }
                } else {
                    TomatoPillButton(title: "Find my people") { requestContacts() }
                    if accessState == .denied {
                        Text("Contacts are off for Plated in Settings — you can set places later.")
                            .font(.jakarta(12, .medium))
                            .foregroundStyle(Color.inkFaint)
                            .multilineTextAlignment(.center)
                    }
                }
                Button {
                    Haptic.tap()
                    onDone()
                } label: {
                    Text("Start with an empty table")
                        .font(.jakarta(14, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.inkFaint)
                    Text("Contacts are matched on your device. Never uploaded, never sold.")
                        .font(.jakarta(12, .medium))
                        .foregroundStyle(Color.inkFaint)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(alignment: .topLeading) {
            RadialGradient(colors: [.mangoTint, .mangoTint.opacity(0)], center: .center, startRadius: 0, endRadius: 220)
                .frame(width: 440, height: 440)
                .offset(x: -120, y: -180)
                .ignoresSafeArea()
        }
        .onAppear { withAnimation(.plSettle.delay(0.1)) { arrived = true } }
        .animation(.plSettle, value: accessState == .granted)
    }

    private func seatBubble(_ letter: String, tone: PersonTone) -> some View {
        Circle()
            .fill(tone.tint)
            .frame(width: 52, height: 52)
            .overlay(Text(letter).font(.jakarta(17, .bold)).foregroundStyle(tone.tone))
            .overlay(Circle().strokeBorder(Color.canvas, lineWidth: 3))
            .shadow(color: Color(rgb: 0x825028).opacity(0.12), radius: 10, y: 8)
    }

    private func candidateRow(_ candidate: Binding<Candidate>) -> some View {
        let person = candidate.wrappedValue
        let tone = PersonTone.from(hex: PersonTone.rotation[abs(person.id.hashValue) % PersonTone.rotation.count])
        return HStack(spacing: 12) {
            AvatarCircle(initials: initials(of: person.name), tone: tone, size: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text(person.name)
                    .font(.jakarta(15, .semibold))
                    .foregroundStyle(Color.ink)
                Text("In your contacts")
                    .font(.jakarta(12, .medium))
                    .foregroundStyle(Color.inkFaint)
            }
            Spacer()
            if person.seated {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .heavy))
                    Text("Seated").font(.jakarta(13, .bold))
                }
                .foregroundStyle(Color.basil)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(Color.basilTint, in: Capsule())
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            } else {
                Button {
                    Haptic.plate()
                    withAnimation(.plPop) { candidate.wrappedValue.seated = true }
                } label: {
                    Text("Set a place")
                        .font(.jakarta(13, .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Color.tomato, in: Capsule())
                        .shadow(color: Color(rgb: 0x3C3228).opacity(0.14), radius: 7, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 12)
    }

    private func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private func requestContacts() {
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async { accessState = .denied }
                return
            }
            let keys = [CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]
            let request = CNContactFetchRequest(keysToFetch: keys)
            var found: [Candidate] = []
            try? store.enumerateContacts(with: request) { contact, stop in
                let name = "\(contact.givenName) \(contact.familyName)".trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    found.append(Candidate(id: contact.identifier, name: name))
                }
                if found.count >= 8 { stop.pointee = true }
            }
            DispatchQueue.main.async {
                candidates = found
                accessState = .granted
            }
        }
    }
}
