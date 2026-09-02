import SwiftUI
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
struct ProfileSetupView: View {
    let onDone: () -> Void

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
                    .font(.gabarito(32, .extraBold))
                    .tracking(-0.8)
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text("This is how your household sees you on the plans you make and the dishes you post.")
                    .font(.jakarta(15, .medium))
                    .foregroundStyle(Color.inkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
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
                        photoOption("Take one", icon: "camera")
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .opacity(arrived ? 1 : 0)

            VStack(alignment: .leading, spacing: 8) {
                MicroLabel("Your name")
                TextField("What should we call you?", text: $name)
                    .font(.jakarta(15, .semibold))
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: Radius.chip).strokeBorder(Color.hairline))
                    .contentShape(RoundedRectangle(cornerRadius: Radius.chip))
                    .onTapGesture { namingSelf = true }
                    .focused($namingSelf)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .opacity(arrived ? 1 : 0)

            Spacer(minLength: 16)

            VStack(spacing: 12) {
                TomatoPillButton(title: "That's me") { finish() }
                    .disabled(trimmedName.isEmpty)
                    .opacity(trimmedName.isEmpty ? 0.5 : 1)

                Button {
                    Haptic.tap()
                    finish()
                } label: {
                    Text("Do this later")
                        .font(.jakarta(14, .semibold))
                        .foregroundStyle(Color.inkSecondary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
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
                .font(.jakarta(13, .bold))
        }
        .foregroundStyle(Color.ink)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 46)
        .overlay(Capsule().strokeBorder(Color.hairline, lineWidth: 1.5))
    }

    private func finish() {
        if !trimmedName.isEmpty { userFirstName = trimmedName }
        // Parked rather than written: the head of the table does not exist
        // yet. See ProfilePhoto for why that ordering is deliberate.
        ProfilePhoto.park(photoData)
        onDone()
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
                                .foregroundStyle(Color.inkFaint)
                        }
                        .overlay(
                            Circle().strokeBorder(
                                Color.hairlineDashed,
                                style: StrokeStyle(lineWidth: 2, dash: [7, 6])
                            )
                        )
                }
            }
            .shadow(color: Color.shadowWarm.opacity(0.14), radius: 18, y: 10)

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

/// The system camera, for the selfie.
struct CameraCapture: UIViewControllerRepresentable {
    var onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
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
