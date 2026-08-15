import SwiftUI
import UIKit

/// The "take this book off the phone" action, identical on every book page.
///
/// Two formats because two habits: a PDF to annotate on an iPad (or print),
/// and Markdown to paste into whatever the learner already keeps notes in.
/// Both come out of the same `BookDocument`, so a book can never say one
/// thing on paper and another in a notes app.
///
/// Why this isn't a plain `ShareLink`: it was, and tapping PDF froze the
/// screen for seconds with nothing on it. `ShareLink` resolves the
/// `Transferable` while it prepares the sheet, and rendering a book to A4
/// runs `UIPrintPageRenderer` on the main thread — so the app was busy
/// laying out pages with no way to say so, and the sheet appeared only
/// afterwards. Now the work is started explicitly, the button says what it
/// is doing, and the share sheet opens on a file that already exists.
struct BookExportMenu: View {
    /// Built when the menu opens, not when the page renders.
    let document: () -> BookDocument

    @EnvironmentObject private var appState: AppState

    private enum Format { case pdf, markdown }

    @State private var preparing = false
    @State private var shared: SharedFile?
    @State private var failed = false

    var body: some View {
        Group {
            if preparing {
                // Replaces the button rather than covering it: a toolbar has
                // no room for an overlay, and a spinner where the control was
                // is the clearest "it's working" this space allows.
                ProgressView()
            } else {
                Menu {
                    Button { export(.pdf) } label: {
                        Label("PDF", systemImage: "doc.richtext")
                    }
                    Button { export(.markdown) } label: {
                        Label("Text", systemImage: "doc.plaintext")
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shared) { file in
            ShareSheet(url: file.url)
                .presentationDetents([.medium, .large])
        }
        .alert(Text(explain("Couldn't export")), isPresented: $failed) {
            Button(explain("OK")) { }
        } message: {
            Text(explain("The book couldn't be written to a file. Try again."))
        }
    }

    private func export(_ format: Format) {
        preparing = true
        Task {
            // One turn of the run loop so the spinner actually paints before
            // the render takes the main thread. Without it the state change
            // and the blocking work land in the same frame and the user sees
            // the freeze they saw before.
            await Task.yield()
            var doc = document()
            // The glossary is the one part of a book that isn't already on
            // the phone, so it's fetched here rather than at page render.
            // Bounded by BookGlossary's own budget: a slow dictionary costs
            // the glossary, never the export.
            if let glossary = await BookGlossary.section(
                for: doc,
                native: appState.nativeLanguage,
                target: appState.targetLanguage) {
                doc.sections.append(glossary)
            }
            do {
                let url: URL
                switch format {
                case .pdf:
                    url = try BookExportWriter.write(doc.pdfData(), name: "\(doc.filename).pdf")
                case .markdown:
                    url = try BookExportWriter.write(Data(doc.markdown.utf8),
                                                     name: "\(doc.filename).md")
                }
                preparing = false
                shared = SharedFile(url: url)
            } catch {
                preparing = false
                failed = true
            }
        }
    }

    private struct SharedFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }
}

/// `UIActivityViewController` in SwiftUI clothing. Used instead of
/// `ShareLink` because the file is already on disk by the time this appears —
/// there is nothing left to resolve, so nothing left to block on.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
