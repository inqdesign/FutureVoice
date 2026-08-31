import SwiftUI
import PhotosUI
import UIKit

/// Make a day's card and share it — the running app's "your run is saved,
/// here's the card", for the day.
///
/// Offered on the book page the moment a talk's book is made (the wait was
/// already there, and "take a photo of where you are" fills it), and from
/// the Activity page's day summary for any day — the summary already says
/// what the day was, and the card is that summary as a picture. The photo is saved as the day's the moment it's
/// picked; there is no separate save, so closing the sheet loses nothing.
/// Sharing renders the card at 3× (1080 wide) to a temporary file the share
/// sheet copies from.
struct DayCardSheet: View {
    let day: Date
    /// Fixed data for the capture harness; nil reads the day's logs.
    var preview: DayCardData? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var data: DayCardData?
    @State private var photo: UIImage?
    @State private var format: DayCardFormat = .feed
    @State private var pick: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var exported: URL?
    @State private var thumb: UIImage?
    @State private var photoStamp = 0

    private var store: DayCardStore { DayCardStore.shared }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var hasCamera: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let data {
                        cardPreview(data)
                            .frame(maxWidth: .infinity)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    Picker("Format", selection: $format) {
                        Text("Feed 4:5").tag(DayCardFormat.feed)
                        Text("Square").tag(DayCardFormat.square)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    if hasCamera {
                        Button { showingCamera = true } label: {
                            Label("Take a photo", systemImage: "camera")
                        }
                    }
                    PhotosPicker(selection: $pick, matching: .images) {
                        Label("Choose a photo", systemImage: "photo.on.rectangle")
                    }
                    if photo != nil {
                        Button(role: .destructive) { setPhoto(nil) } label: {
                            Label("Remove photo", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Photo")
                } footer: {
                    Text(explain("Where you studied that day — the photo is the place. Nothing else about the location is saved."))
                }
            }
            .navigationTitle(isToday ? chrome("Today's card")
                             : day.formatted(.dateTime.month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    if let exported {
                        ShareLink(item: exported,
                                  preview: SharePreview(day.formatted(date: .abbreviated, time: .omitted),
                                                        image: Image(uiImage: thumb ?? UIImage()))) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: pick) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    setPhoto(img)
                }
                pick = nil
            }
        }
        .task(id: renderKey) { await renderForShare() }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { setPhoto($0) }
                .ignoresSafeArea()
        }
    }

    /// The card at the sheet's width. The view is fixed-size, so it's scaled
    /// rather than re-laid-out — what's shared is exactly what's shown.
    private func cardPreview(_ data: DayCardData) -> some View {
        let scale = min(1, (UIScreen.main.bounds.width - 40) / format.size.width)
        return DayCardView(data: data, photo: photo, format: format)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: format.size.width * scale, height: format.size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private struct RenderKey: Equatable { var format: DayCardFormat; var photoStamp: Int; var ready: Bool }
    private var renderKey: RenderKey { RenderKey(format: format, photoStamp: photoStamp, ready: data != nil) }

    private func load() {
        data = preview ?? DayCardData.resolve(day: day)
        photo = store.photo(for: day)
    }

    private func setPhoto(_ image: UIImage?) {
        store.setPhoto(image, for: day)
        photo = store.photo(for: day)
        photoStamp += 1
        // Taking the photo is making the card — freeze the day with it.
        if preview == nil, let data { store.freeze(data) }
    }

    @MainActor
    private func renderForShare() async {
        exported = nil
        guard let data else { return }
        // Let a burst of edits settle — a render is a 1080-wide bitmap.
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let card = DayCardView(data: data, photo: photo, format: format)
        guard let image = card.render(), let png = image.pngData() else { return }
        thumb = card.render(scale: 1)
        let name = "nawana-\(AppUsageLog.dayKey(data.date))-\(format.rawValue).png"
        exported = try? BookExportWriter.write(png, name: name)
        // A card that reached the share sheet is a card that was made.
        if preview == nil { store.freeze(data) }
    }
}

/// The system camera, for the photo the card is about. The one UIKit wrap
/// here: `PhotosPicker` has no camera, and "take it now, where you are" is the
/// whole point of asking at the end of a talk.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
