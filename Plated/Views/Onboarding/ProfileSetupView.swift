import SwiftUI
import SwiftData
import PhotosUI

/// "Put a face to your name" — the step between signing in and setting the
/// table.
///
/// Apple does not give an app the Apple ID photo (see `ProfilePhoto` for
/// exactly why, with the API list), so the choice is not between a real
/// photo and a monogram. It is between asking for a photo at the one moment
/// somebody is already introducing themselves, or letting them find a letter
/// in a circle three days later on a screen labelled "head of table" and
/// wonder why the app never asked.
///
/// One tap to the library, one to the camera, and a way past for anyone who
/// does not want to. The name comes prefilled from Apple when Apple gave it,
/// which is only ever on the very first authorization.
///
/// This step also lays the owner's place (docs/household.md §6): the host
/// seat has to exist before the first invitation, and a person joining
/// from a link never reaches the invite screen that used to lay it.
struct ProfileSetupView: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @AppStorage("userFirstName") private var userFirstName = ""
    @State private var name = ""
    @State private var photoData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var cameraShown = false
    @State private var arrived = false
    @FocusState private var namingSelf: Bool

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Put a face to your name")
                    .plType(.hero)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is how your household sees you everywhere in Plated.")
                    .plType(.body, .medium)
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 76)
            .padding(.horizontal, 30)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 20)

            ProfilePhotoWell(photoData: $photoData, initials: initials, diameter: 168)
                .scaleEffect(arrived ? 1 : 0.9)
                .opacity(arrived ? 1 : 0)

            HStack(spacing: 10) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    photoOption("Choose a photo", icon: "photo.on.rectangle")
                }
                .buttonStyle(.pressable)

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        Haptic.tap()
                        cameraShown = true
                    } label: {
                        photoOption("Take a photo", icon: "camera")
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .opacity(arrived ? 1 : 0)

            Button("Use my contact photo") {
                ContactPhotoPicker.choose { selected in
                    guard let selected else { return }
                    withAnimation(.plSnap) { photoData = selected }
                }
            }
            .plType(.footnote, .bold).foregroundStyle(Color.ink).plTapTarget()
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your name")
                TextField("First name", text: $name)
                    .plType(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .onTapGesture { namingSelf = true }
                    .focused($namingSelf)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                TomatoPillButton(title: "Continue") { finish() }
                    .disabled(trimmedName.isEmpty)

                // Was `finish()`, the same call Continue makes: it saved the
                // name and parked the photo, so the two buttons did exactly
                // the same thing while promising opposite outcomes. "Not
                // now" means later.
                Button {
                    Haptic.tap()
                    // "Not now" declines the PHOTO. A name that has been
                    // typed is still their name, and leaving it here left
                    // the row called Nate while `userFirstName` stayed
                    // empty: every invitation then went out as "Join my
                    // household on Plated", with no host in the link and no
                    // host name on the household root.
                    if !trimmedName.isEmpty { userFirstName = trimmedName }
                    layOwnersPlace(photo: nil)
                    onDone()
                } label: {
                    Text("Not now")
                        .plType(.body)
                        .plActionLabel()
                        .foregroundStyle(Color.inkSecondary)
                        .plTapTarget()
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .plFitsOrScrolls()
        .background(Color.canvas.ignoresSafeArea())
        .onAppear {
            name = userFirstName
            withAnimation(.plSettle.delay(0.1)) { arrived = true }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
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
    }

    private var initials: String {
        let parts = trimmedName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map(String.init).joined().uppercased()
        return letters.isEmpty ? "?" : letters
    }

    private func photoOption(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .plType(.footnote, .bold)
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 46)
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
        // A stroked capsule is a ring: without this the 46pt pill was
        // tappable only across its letters. One line, both pills.
        .contentShape(Capsule())
    }

    private func finish() {
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
            role: "owner", roleLine: "Head of table", cookWeekdays: [],
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
                                .font(.gabarito(diameter * 0.32, .semibold))
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

            if photoData != nil {
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
