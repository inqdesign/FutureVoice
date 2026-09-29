import SwiftUI
import PhotosUI

/// The one control for picking a person's photo — a menu over whatever label
/// the host draws (the big circle on the intake's first card, the avatar row
/// on the form). Three sources: the photo library, the camera, and the Files
/// app; a file is read where it lives and never copied. The picked image is
/// handed back raw — the host decides whether it is saved now
/// (`CounterpartPhotoStore`) or held until the person exists.
struct PersonPhotoButton<Label: View>: View {
    var onImage: (UIImage) -> Void
    /// When set, the menu also offers "Remove photo".
    var onRemove: (() -> Void)? = nil
    @ViewBuilder var label: () -> Label

    @State private var pickingPhoto = false
    @State private var photoPick: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var importingFile = false
    @State private var error: String?

    var body: some View {
        Menu {
            Button { pickingPhoto = true } label: { SwiftUI.Label("Photo library", systemImage: "photo.on.rectangle") }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button { showingCamera = true } label: { SwiftUI.Label("Take a photo", systemImage: "camera") }
            }
            Button { importingFile = true } label: { SwiftUI.Label("Pick a file", systemImage: "folder") }
            if let onRemove {
                Divider()
                Button(role: .destructive) { onRemove() } label: {
                    SwiftUI.Label("Remove photo", systemImage: "trash")
                }
            }
        } label: {
            label()
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoPick, matching: .images)
        .onChange(of: photoPick) { _, item in
            guard let item else { return }
            photoPick = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    onImage(img)
                } else {
                    error = explain("Couldn't read that photo.")
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker { onImage($0) }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
            switch result {
            case .success(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                    onImage(img)
                } else {
                    error = explain("Couldn't read that file as a photo.")
                }
            case .failure(let e):
                error = e.localizedDescription
            }
        }
        .alert("Photo", isPresented: Binding(get: { error != nil },
                                             set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }
}

/// The big round photo control the intake and the form share: the photo
/// when there is one, else a neutral placeholder, with a camera badge.
struct PersonPhotoCircle: View {
    var image: UIImage?
    var name: String = ""
    var size: CGFloat = 96

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else if !name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(Books.initials(name))
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.accentColor.opacity(0.15))
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            Image(systemName: "camera.circle.fill")
                .font(.system(size: size * 0.3))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .offset(x: 2, y: 2)
        }
    }
}
