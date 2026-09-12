import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Make a day's card and share it — the running app's "your run is saved,
/// here's the card", for the day.
///
/// Offered on the book page the moment a talk's book is made (the wait was
/// already there, and "take a photo of where you are" fills it), and from
/// the Activity page's day summary for any day — the summary already says
/// what the day was, and the card is that summary as a picture. The photo is saved as the day's the moment it's
/// picked; there is no separate save, so closing the sheet loses nothing.
/// Today's numbers are read LIVE every time the sheet opens — the day is
/// still being lived, and an earlier build froze them the first time anyone
/// looked, so the card sat at whatever the morning had been.
/// Sharing renders the card at 3× (1080 wide) and hands the share sheet PNG
/// DATA, not a file URL — Threads/Instagram share extensions accept
/// `public.png` items but not `file-url`, so a URL item left their composer
/// with no attachment.
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
    @State private var exported: SharedCard?
    @State private var thumb: UIImage?
    @State private var photoStamp = 0
    /// The headline field — the learner's OWN words only. A picked talk
    /// title shows as a checkmark on its row, never in here. Edits show on
    /// the card as they're typed; the store is written when the field is
    /// left, so the page underneath isn't asked to redraw its thumbnails on
    /// every keystroke.
    @State private var headlineText = ""
    @FocusState private var editingHeadline: Bool
    /// Set while `pick` empties the field, so the field's change handler
    /// doesn't read that emptying as "back to automatic".
    @State private var clearingField = false

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
                    // The day's talks, to pick from. The card's automatic
                    // choice is the first; a tap makes it the day's for good.
                    if let data {
                        ForEach(data.topics, id: \.self) { topic in
                            Button { pick(topic) } label: {
                                HStack {
                                    Text(topic).lineLimit(2)
                                    Spacer()
                                    if topic == data.title {
                                        Image(systemName: "checkmark").foregroundStyle(.tint)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    TextField("Or write your own", text: $headlineText)
                        .focused($editingHeadline)
                        .submitLabel(.done)
                        .onSubmit { editingHeadline = false }
                } header: {
                    Text("Headline")
                } footer: {
                    // Material, so the language being learned — like the talk
                    // titles it stands in for.
                    Text("Write it in \(LanguageCatalog.learnerName(LanguageScope.active)).")
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
        .onChange(of: headlineText) { _, text in
            if clearingField { clearingField = false; return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            // Typing takes the headline; clearing the field hands it back
            // to the automatic pick, not to whatever was chosen before.
            data?.headline = trimmed.isEmpty ? nil : trimmed
        }
        .onChange(of: editingHeadline) { _, editing in
            if !editing { commitHeadline() }
        }
        .onDisappear(perform: commitHeadline)
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
            // Same corner as the grouped sections below it — a 6 pt corner
            // beside iOS 26's large container radius read as a mismatch.
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private struct RenderKey: Equatable {
        var format: DayCardFormat; var photoStamp: Int; var ready: Bool; var headline: String?
    }
    private var renderKey: RenderKey {
        RenderKey(format: format, photoStamp: photoStamp, ready: data != nil, headline: data?.headline)
    }

    private func load() {
        data = preview ?? DayCardData.resolve(day: day)
        photo = store.photo(for: day)
        // Only a headline the learner WROTE belongs in the field; one that
        // matches a talk shows on that talk's row instead.
        if let h = data?.headline, !(data?.topics.contains(h) ?? false) { headlineText = h }
    }

    /// A talk's title as the day's headline. The field empties — its text is
    /// the learner's own words, and this isn't one of them.
    private func pick(_ topic: String) {
        editingHeadline = false
        if !headlineText.isEmpty { clearingField = true; headlineText = "" }
        data?.headline = topic
        commitHeadline()
    }

    /// Settle the typed headline as the day's. Empty goes back to automatic.
    private func commitHeadline() {
        guard preview == nil, let data else { return }
        store.setHeadline(data.headline, for: day)
        store.freeze(data)
    }

    private func setPhoto(_ image: UIImage?) {
        store.setPhoto(image, for: day)
        photo = store.photo(for: day)
        photoStamp += 1
        // Taking the photo is making the card, so settle the day with it —
        // the numbers only for today (the store refuses to freeze a running
        // day), but the HEADLINE always: the card is about to be shared, and
        // a later talk that outruns this one must not change its face.
        guard preview == nil, let data else { return }
        if data.headline == nil, let auto = data.topics.first {
            self.data?.headline = auto
            store.setHeadline(auto, for: day)
        }
        store.freeze(self.data ?? data)
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
        exported = SharedCard(png: png, filename: name)
    }
}

/// The card as the share sheet receives it: PNG data typed `public.png`, with
/// the filename riding along for "Save to Files". A file URL was tried first
/// and is why this exists — image-only share extensions ignore it.
private struct SharedCard: Transferable {
    let png: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.png }
            .suggestedFileName { $0.filename }
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
