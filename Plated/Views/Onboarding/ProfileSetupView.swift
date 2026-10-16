import SwiftUI
import SwiftData
import PhotosUI

/// Photo and name, between signing in and setting the table.
///
/// Apple does not give an app the Apple ID photo (see `ProfilePhoto` for
/// exactly why, with the API list), so the choice is not between a real
/// photo and a monogram. It is between asking for a photo at the one moment
/// somebody is already introducing themselves, or letting them find a letter
/// in a circle later and wonder why the app never asked. The copy says that
/// plainly rather than implying Apple already handed a picture over.
///
/// The photo control offers the camera/library picker, with a separate
/// single-contact picker for somebody who keeps their own portrait there.
/// The name is prefilled from Apple when Apple gave it, which is only ever
/// on the very first authorization, and remains editable as a household
/// display name or nickname.
///
/// This step also lays the owner's place (docs/household.md §6): the host
/// seat has to exist before the first invitation, and a person joining
/// from a link never reaches the invite screen that used to lay it.
struct ProfileSetupView: View {
    /// A screenshot/review surface. It looks and responds like onboarding,
    /// but never opens a picker or writes identity, profile or household data.
    let reviewOnly: Bool
    let onDone: () -> Void

    init(reviewOnly: Bool = false, onDone: @escaping () -> Void) {
        self.reviewOnly = reviewOnly
        self.onDone = onDone
    }

    @Environment(\.modelContext) private var context
    @AppStorage("userFirstName") private var userFirstName = ""
    @State private var name = ""
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraShown = false
    @State private var sourceAsked = false
    @State private var libraryShown = false
    @State private var arrived = false
    @State private var appleNameWasAvailable = false
    @State private var editingName = false
    @State private var reviewPhotoSelected = false
    @FocusState private var namingSelf: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Make yourself at home")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Add a photo so people recognize you at your table.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 76)
            .padding(.horizontal, 30)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 20)

            Button {
                Haptic.tap()
                if reviewOnly {
                    withAnimation(.plPop) { reviewPhotoSelected.toggle() }
                    return
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    sourceAsked = true
                } else {
                    libraryShown = true
                }
            } label: {
                Group {
                    if reviewOnly, reviewPhotoSelected {
                        AvatarCircle(initials: initials, tone: .tomatoPair, size: 168)
                            .plCardShadow()
                    } else {
                        ProfilePhotoWell(
                            photoData: $photoData,
                            initials: initials,
                            diameter: 168,
                            showsRemoveControl: false
                        )
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    Label(hasVisiblePhoto ? "Change" : "Add photo", systemImage: "camera")
                        .plType(.micro, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 11)
                        .frame(minHeight: 32)
                        .background(.regularMaterial, in: Radius.shape(Radius.chip))
                        .overlay(Radius.shape(Radius.chip).strokeBorder(Color.hairline))
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(hasVisiblePhoto ? "Change profile photo" : "Add a profile photo")
            .scaleEffect(arrived ? 1 : 0.9)
            .opacity(arrived ? 1 : 0)

            if !reviewOnly {
                Button {
                    ContactPhotoPicker.choose { selectedPhoto in
                        guard let selectedPhoto else { return }
                        Haptic.plate()
                        withAnimation(.plPop) { photoData = selectedPhoto }
                    }
                } label: {
                    Label("Choose from a contact", systemImage: "person.crop.circle")
                        .plType(.footnote, .semibold)
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Choose a photo from one contact. Plated receives only the photo you select.")
                .opacity(arrived ? 1 : 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                if appleNameWasAvailable, !editingName {
                    MicroLabel("You’ll appear as")
                    HStack(spacing: 12) {
                        Text(trimmedName)
                            .plType(.heading, .semibold)
                            .foregroundStyle(Color.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Change") {
                            Haptic.tap()
                            editingName = true
                            namingSelf = true
                        }
                        .plType(.footnote, .bold)
                        .plActionLabel()
                        .foregroundStyle(Color.accentText)
                        .frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                    .frame(minHeight: 58)
                    .background(Color.fill, in: Radius.shape(Radius.chip))
                } else {
                    MicroLabel("What should we call you?")
                    TextField("Name or nickname", text: $name)
                        .plType(.body)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 52)
                        .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                        .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                        .onTapGesture { namingSelf = true }
                        .focused($namingSelf)
                        .submitLabel(.done)
                    Text(appleNameWasAvailable
                         ? "Use the name or nickname your household knows."
                         : "This is the name your household will see.")
                        .plType(.caption)
                        .foregroundStyle(Color.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                PrimaryActionButton(title: "Continue") { finish() }
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .plFitsOrScrolls()
        .background { OnboardingAtmosphere().ignoresSafeArea() }
        .onAppear {
            if reviewOnly {
                name = "Alex"
                appleNameWasAvailable = true
                withAnimation(.plSettle.delay(0.1)) { arrived = true }
                return
            }
            appleNameWasAvailable = !userFirstName.trimmingCharacters(in: .whitespaces).isEmpty
            name = userFirstName
            withAnimation(.plSettle.delay(0.1)) { arrived = true }
        }
        .onChange(of: pickerItem) { _, item in
            guard !reviewOnly, let item else { return }
            Task {
                if let raw = try? await item.loadTransferable(type: Data.self),
                   let square = ProfilePhoto.square(raw) {
                    Haptic.plate()
                    withAnimation(.plPop) { photoData = square }
                }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $cameraShown) {
            CameraCapture { image in
                cameraShown = false
                guard let image, let raw = image.jpegData(compressionQuality: 0.9),
                      let square = ProfilePhoto.square(raw) else { return }
                Haptic.plate()
                withAnimation(.plPop) { photoData = square }
            }
            .ignoresSafeArea()
        }
        .confirmationDialog("Add a profile photo", isPresented: $sourceAsked, titleVisibility: .visible) {
            Button("Take a photo") { cameraShown = true }
            Button("Choose from library") { libraryShown = true }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $libraryShown, selection: $pickerItem, matching: .images)
    }

    private var initials: String {
        let parts = trimmedName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    private var hasVisiblePhoto: Bool {
        photoData != nil || (reviewOnly && reviewPhotoSelected)
    }

    private func finish() {
        guard !reviewOnly else {
            onDone()
            return
        }
        if !trimmedName.isEmpty { userFirstName = trimmedName }
        // Parked as well as hung: on a simulator the head of the table is
        // the sample seed's to lay, and the shell hangs the parked bytes on
        // it the first time there is a row. See ProfilePhoto.
        ProfilePhoto.park(photoData)
        layOwnersPlace(photo: photoData)
        onDone()
    }

    /// Every household has a head, and it is the person who just gave their
    /// name. Laid here, on both ways out, so the seat exists before the
    /// first invitation and before a link-joiner's claim moves it.
    ///
    /// Not on a simulator: the sample seed checks for an empty roster, and
    /// a head laid here would defeat it (see `ContactsView.finish`, which
    /// keeps the same guard as a safety net). A fetch FAILURE aborts rather
    /// than inserting: only a confirmed zero earns a new row.
    private func layOwnersPlace(photo: Data?) {
        #if !targetEnvironment(simulator)
        let owners = try? context.fetchCount(
            FetchDescriptor<HouseholdMember>(predicate: #Predicate { $0.role == "owner" })
        )
        guard owners == 0 else { return }
        let me = HouseholdMember(
            name: trimmedName.isEmpty ? (userFirstName.isEmpty ? "Me" : userFirstName) : trimmedName,
            colorHex: "FF5A3C", isPrimaryCook: true,
            role: "owner", roleLine: "Organizer", cookWeekdays: [],
            seat: .head
        )
        // Identity once CloudKit has confirmed one; a placeholder is never
        // written onto a seat, because a seat's identity is set once and
        // never replaced (docs/household.md §3.1).
        if !TableIdentity.isPlaceholder { me.userRecordName = TableIdentity.cached }
        me.authorID = TableIdentity.cached
        if let photo {
            me.photoData = photo
            ProfilePhoto.clearParked()
        }
        context.insert(me)
        Persist.save(context, "owner's place")
        print("PLATED HOUSEHOLD: laid the owner's place for \(me.name)")
        #endif
    }
}

/// The circular photo target, shared by onboarding and the profile editor so
/// changing your picture looks the same wherever you do it.
struct ProfilePhotoWell: View {
    @Binding var photoData: Data?
    var initials: String
    var diameter: CGFloat = 120
    var showsRemoveControl = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let photoData, let image = UIImage(data: photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: diameter, height: diameter)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(Color.fill)
                        .frame(width: diameter, height: diameter)
                        .overlay {
                            Text(initials)
                                .font(.editorial(diameter * 0.32, .semibold))
                                .foregroundStyle(Color.inkSecondary)
                        }
                        .overlay(
                            Circle().strokeBorder(
                                Color.hairlineDashed,
                                style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                            )
                        )
                }
            }
            .plCardShadow()

            if photoData != nil, showsRemoveControl {
                Button {
                    Haptic.tap()
                    withAnimation(.plSnap) { photoData = nil }
                } label: {
                    Circle()
                        .fill(Color.canvas)
                        .frame(width: 34, height: 34)
                        .overlay {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.ink)
                        }
                        .overlay(Circle().strokeBorder(Color.hairline))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Remove photo")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(photoData == nil ? "No photo yet" : "Your photo")
    }
}

/// The system camera. Front-facing for a selfie, rear for a plate of food,
/// which is the only thing that differs between the two places the app opens
/// a camera.
struct CameraCapture: UIViewControllerRepresentable {
    var device: UIImagePickerController.CameraDevice = .front
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = device
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            onCapture(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCapture(nil)
        }
    }
}
