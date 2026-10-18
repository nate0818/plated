import SwiftUI

/// A place remains part of the existing eating-out title on the shared plan.
/// No separate restaurant record or invented location is required.
struct DiningPlaceSheet: View {
    let save: @MainActor (String) async -> String?
    @State private var place: String
    @State private var saving = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(title: String, save: @escaping @MainActor (String) async -> String?) {
        let prefix = "Eating out at "
        _place = State(initialValue: title.hasPrefix(prefix) ? String(title.dropFirst(prefix.count)) : "")
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Restaurant or place", text: $place)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("dining-place")
                } footer: {
                    Text("Optional. Leave this blank to keep the plan as Eating out.")
                }
                if let problem { Text(problem).foregroundStyle(Color.dangerText) }
            }
            .navigationTitle("Where are you eating?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") {
                        saving = true
                        Task {
                            problem = await save(place)
                            saving = false
                            if problem == nil { dismiss() }
                        }
                    }.disabled(saving)
                }
            }
        }
        .tint(Color.accentText)
        .interactiveDismissDisabled(saving)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
