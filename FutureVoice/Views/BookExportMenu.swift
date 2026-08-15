import SwiftUI
import UIKit

/// "Take this book off the phone", split into the two halves SwiftUI needs it
/// split into.
///
/// The buttons live inside a `Menu` — and menu content is not an ordinary view
/// hierarchy. A `.sheet` or `.alert` attached in there never presents, which
/// is exactly what happened: tapping PDF ran the work and then dropped the
/// share sheet on the floor, with no indicator, because the presenter was
/// inside a menu that had already closed. So the rows stay here and every
/// piece of presentation moves to the page that owns the toolbar, via
/// `.bookExport(_:)`.
///
/// Two formats because two habits: a PDF to annotate on an iPad (or print),
/// and Markdown to paste into whatever the learner already keeps notes in.
/// Both come out of the same `BookDocument`, so a book can never say one
/// thing on paper and another in a notes app.
@MainActor
final class BookExportController: ObservableObject {
    enum Format { case pdf, markdown }

    struct SharedFile: Identifiable {
        let url: URL
        var id: String { url.path }
    }

    @Published var preparing = false
    @Published var shared: SharedFile?
    @Published var failed = false

    func export(_ format: Format,
                document: @escaping () -> BookDocument,
                native: String,
                target: String) {
        guard !preparing else { return }
        preparing = true
        Task {
            // Let the menu finish dismissing before the overlay appears and
            // before the render takes the main thread — a sheet presented
            // into a closing menu is dropped.
            try? await Task.sleep(for: .milliseconds(350))
            var doc = document()
            // The glossary is the one part of a book that isn't already on
            // the phone. Bounded inside BookGlossary: a slow dictionary costs
            // the glossary, never the export.
            if let glossary = await BookGlossary.section(for: doc, native: native, target: target) {
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
}

/// The menu rows. Content only — no state, no presentation.
struct BookExportMenu: View {
    @ObservedObject var controller: BookExportController
    /// Built when a format is chosen, not when the page renders.
    let document: () -> BookDocument

    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            controller.export(.pdf, document: document,
                              native: appState.nativeLanguage,
                              target: appState.targetLanguage)
        } label: {
            Label("PDF", systemImage: "doc.richtext")
        }
        Button {
            controller.export(.markdown, document: document,
                              native: appState.nativeLanguage,
                              target: appState.targetLanguage)
        } label: {
            Label("Text", systemImage: "doc.plaintext")
        }
    }
}

extension View {
    /// Attach on the PAGE, not in the toolbar: this is what actually shows
    /// progress and presents the share sheet.
    func bookExport(_ controller: BookExportController) -> some View {
        modifier(BookExportPresentation(controller: controller))
    }
}

private struct BookExportPresentation: ViewModifier {
    @ObservedObject var controller: BookExportController

    func body(content: Content) -> some View {
        content
            .overlay {
                if controller.preparing {
                    // Covers the page on purpose: rendering a book holds the
                    // main thread, so taps would queue up anyway. Better to
                    // say so than to look broken.
                    ZStack {
                        Color(.systemBackground).opacity(0.6).ignoresSafeArea()
                        ProgressView(explain("Preparing the file…"))
                            .controlSize(.large)
                    }
                }
            }
            .animation(.default, value: controller.preparing)
            .sheet(item: $controller.shared) { file in
                ShareSheet(url: file.url)
            }
            .alert(Text(explain("Couldn't export")), isPresented: $controller.failed) {
                Button(explain("OK")) { }
            } message: {
                Text(explain("The book couldn't be written to a file. Try again."))
            }
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
