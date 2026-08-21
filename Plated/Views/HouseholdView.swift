import SwiftUI
import SwiftData

/// Who Plated is cooking for. Dietary notes and avoided ingredients entered here
/// drive the warnings shown when a recipe hits the plan.
struct HouseholdView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HouseholdMember.createdAt) private var members: [HouseholdMember]

    var body: some View {
        NavigationStack {
            List {
                ForEach(members) { member in
                    NavigationLink {
                        MemberEditorView(member: member)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: member.colorHex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Text(member.initials)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.white)
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name.isEmpty ? "New member" : member.name)
                                if !member.dietaryNotes.isEmpty {
                                    Text(member.dietaryNotes)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                if !member.avoidedIngredients.isEmpty {
                                    Label(member.avoidedIngredients.joined(separator: ", "),
                                          systemImage: "hand.raised")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            if member.isPrimaryCook {
                                Image(systemName: "frying.pan")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(members[index]) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.canvas)
            .tint(.tomato)
            .navigationTitle("Household")
            .navigationBarTitleDisplayMode(.inline)
            .overlay {
                if members.isEmpty {
                    ContentUnavailableView(
                        "No one added yet",
                        systemImage: "person.2",
                        description: Text("Add everyone you cook for, along with what they can't or won't eat.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add member", systemImage: "plus", action: addMember)
                }
            }
        }
    }

    private func addMember() {
        let index = members.count % Color.memberPalette.count
        let member = HouseholdMember(colorHex: Color.memberPalette[index])
        context.insert(member)
    }
}

struct MemberEditorView: View {
    @Bindable var member: HouseholdMember
    @State private var avoidText = ""

    var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $member.name)
                Toggle("Primary cook", isOn: $member.isPrimaryCook)
            }

            Section {
                TextField("Vegetarian, low sodium, no shellfish…", text: $member.dietaryNotes, axis: .vertical)
                    .lineLimit(2...6)
            } header: {
                Text("Dietary notes")
            } footer: {
                Text("Free text for context. Use the list below for ingredients Plated should actively flag.")
            }

            Section {
                TextField("Comma separated", text: $avoidText)
                    .onAppear { avoidText = member.avoidedIngredients.joined(separator: ", ") }
                    .onChange(of: avoidText) { _, newValue in
                        member.avoidedIngredients = newValue
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
            } header: {
                Text("Avoid these ingredients")
            } footer: {
                Text("Any recipe containing one of these gets a warning on the plan and is skipped by suggestions.")
            }

            Section("Color") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                    ForEach(Color.memberPalette, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 36, height: 36)
                            .overlay {
                                if member.colorHex == hex {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.white)
                                        .font(.caption.weight(.bold))
                                }
                            }
                            .onTapGesture { member.colorHex = hex }
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.canvas)
        .tint(.tomato)
        .navigationTitle(member.name.isEmpty ? "Member" : member.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
