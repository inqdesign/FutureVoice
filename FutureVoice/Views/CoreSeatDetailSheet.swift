import SwiftUI

/// One member's cube, opened by tapping their cell on the Core page
/// (2026-10-29, founder). The name is for anyone; the hope only for seated
/// members of the same club and its owner — the server decides
/// (`core_seat_detail`), and a reader who may not see the hope is not told
/// there is one. The owner can change both here.
struct CoreSeatDetailSheet: View {
    let language: String
    let index: Int
    #if DEBUG
    /// `-coreseat 1`: a sample seat, no server.
    var preview: CoreClubService.SeatDetail? = nil
    #endif

    @Environment(\.dismiss) private var dismiss
    @State private var detail: CoreClubService.SeatDetail?
    @State private var loaded = false
    @State private var editing = false
    @State private var name = ""
    @State private var hope = ""
    @State private var saving = false
    @State private var cheers: CoreClubService.Cheers?
    @State private var draft = ""
    @State private var sending = false
    /// Notes rising over the cube right now, and the hearts in flight.
    @State private var flights: [NoteFlight] = []
    @State private var hearts: [HeartFlight] = []
    @State private var bigHeart = false
    @FocusState private var writing: Bool

    var body: some View {
        NavigationStack {
          VStack(spacing: 0) {
            // The member's block stays put at the top; only what is under it
            // scrolls (founder, 2026-10-29).
            if let detail {
                // Name on the front, the hope on the back (only for a reader
                // allowed it), the plaque on one side, the mark on the other.
                // Drag to turn it over.
                CoreCubeView(color: FutureselfTheme(rawValue: detail.theme)?.tint ?? .gray,
                             name: detail.name ?? "",
                             hope: detail.can_read_hope ? (detail.hope ?? "") : "",
                             since: detail.seated_since, days: detail.days_held)
                    .frame(width: CoreCubeView.unit * 2.2, height: CoreCubeView.unit * 2.2)
                    // Double-tap the cube: a heart, Instagram-style.
                    .simultaneousGesture(TapGesture(count: 2).onEnded { heartFromCube() })
                    .overlay { bigHeartView }
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .bottom) { risingNotes.padding(.horizontal, 20) }
                    .overlay(alignment: .bottomTrailing) { risingHearts.padding(.trailing, 28) }
            }
            Form {
                if let detail {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            if let shown = detail.name, !shown.isEmpty {
                                Text(verbatim: shown).font(.headline)
                            } else {
                                Text("No name engraved").font(.headline).foregroundStyle(.secondary)
                            }
                            Text(explain("Seat \(detail.index + 1)"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let days = detail.days_held {
                                Text(explain("Day \(days) in this seat"))
                                    .font(.subheadline).foregroundStyle(Color.coreClub)
                            }
                        }
                    }

                    if editing {
                        Section {
                            TextField(explain("Your name"), text: $name)
                                .onChange(of: name) { _, new in
                                    if new.count > CoreClubService.engravedNameLimit {
                                        name = String(new.prefix(CoreClubService.engravedNameLimit))
                                    }
                                }
                            TextField(explain("Your hope, in one line"), text: $hope, axis: .vertical)
                                .onChange(of: hope) { _, new in
                                    if new.count > CoreClubService.hopeLimit {
                                        hope = String(new.prefix(CoreClubService.hopeLimit))
                                    }
                                }
                        } footer: {
                            Text(explain("Only Core members can see your hope. Anyone can see your name."))
                        }
                    } else if !detail.can_read_hope {
                        // A member's hope is theirs and the club's: anyone
                        // else sees that there is one, under a veil that
                        // never lifts. The server sent no text, so there is
                        // nothing under it to lift.
                        Section {
                            HopeVeil()
                        } header: {
                            Text("Hope")
                        } footer: {
                            Text(explain("Only Core members can see this."))
                        }
                    } else {
                        Section {
                            if let shown = detail.hope, !shown.isEmpty {
                                Text(verbatim: shown)
                            } else {
                                Text("No hope engraved yet").foregroundStyle(.secondary)
                            }
                        } header: {
                            Text("Hope")
                        } footer: {
                            Text(explain("Only Core members can see this."))
                        }
                    }

                    // After the hope: the cheers can run long.
                    cheersSection
                } else if loaded {
                    Text(explain("This seat couldn't be opened. Try again in a moment."))
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            // Rows fade out as they pass under the cube instead of being cut
            // by a hard edge.
            .mask(
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 18)
                    Color.black
                }
            )
          }
          // The sheet takes on the member's colour: strongest at the top,
          // behind their cube, fading to the grouped background below.
          .background(tintBackground)
            .navigationTitle("The Core")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if editing {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { editing = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { await save() } }
                            .disabled(saving)
                    }
                } else {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    if detail?.mine == true {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Edit") {
                                name = detail?.name ?? ""
                                hope = detail?.hope ?? ""
                                editing = true
                            }
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
        .task { await load() }
        .task { await runNotes() }
    }

    // MARK: - Cheers

    private var cheersSection: some View {
        Section {
            HStack(spacing: 12) {
                Button { toggleHeart() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: cheers?.hearted == true ? "heart.fill" : "heart")
                            .foregroundStyle(cheers?.hearted == true ? Color.red : Color.secondary)
                            .contentTransition(.symbolEffect(.replace))
                        Text(verbatim: "\(cheers?.hearts ?? 0)")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .font(.title3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Heart"))

                TextField(explain("Leave a short cheer"), text: $draft)
                    .focused($writing)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .onChange(of: draft) { _, new in
                        if new.count > CoreClubService.cheerLimit {
                            draft = String(new.prefix(CoreClubService.cheerLimit))
                        }
                    }
                Button { send() } label: {
                    Image(systemName: "paperplane.fill")
                }
                .buttonStyle(.borderless)
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || sending)
            }

            ForEach(cheers?.notes.reversed() ?? []) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: note.name ?? explain("Someone"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: note.body)
                }
                .contextMenu {
                    if note.by_me || cheers?.mine == true {
                        Button(role: .destructive) { delete(note) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Cheers")
        }
    }

    /// Notes float up over the cube one after another, like comments on a
    /// live video.
    private var risingNotes: some View {
        ZStack(alignment: .bottomLeading) {
            ForEach(flights) { flight in
                RisingNote(flight: flight) { flights.removeAll { $0.id == flight.id } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: CoreCubeView.unit * 2.2, alignment: .bottomLeading)
        .padding(.leading, 4)
        .padding(.bottom, 8)
        .allowsHitTesting(false)
    }

    private var risingHearts: some View {
        ZStack(alignment: .bottom) {
            ForEach(hearts) { heart in
                RisingHeart(flight: heart) { hearts.removeAll { $0.id == heart.id } }
            }
        }
        .frame(width: 80, height: CoreCubeView.unit * 2.2, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var bigHeartView: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 96))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 10)
            .scaleEffect(bigHeart ? 1 : 0.3)
            .opacity(bigHeart ? 0.95 : 0)
            .allowsHitTesting(false)
    }

    private func heartFromCube() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.55)) { bigHeart = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.25)) { bigHeart = false }
        }
        if cheers?.hearted != true { toggleHeart() } else { burstHearts(); HapticEngine.light() }
    }

    private func toggleHeart() {
        guard var current = cheers else { return }
        let on = !current.hearted
        HapticEngine.medium()
        current.hearted = on
        current.hearts = max(0, current.hearts + (on ? 1 : -1))
        withAnimation { cheers = current }
        if on { burstHearts() }
        #if DEBUG
        if preview != nil { return }
        #endif
        Task {
            if let count = await CoreClubService.setHeart(language: language, index: index, on: on) {
                cheers?.hearts = count
            }
        }
    }

    private func burstHearts() {
        for i in 0..<7 {
            let flight = HeartFlight(drift: CGFloat.random(in: -34...24), delay: Double(i) * 0.08,
                                     size: CGFloat.random(in: 16...26))
            hearts.append(flight)
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true
        HapticEngine.medium()
        Task { @MainActor in
            var id: Int? = Int.random(in: 1_000_000...9_999_999)
            #if DEBUG
            if preview == nil { id = await CoreClubService.leaveNote(language: language, index: index, body: body) }
            #else
            id = await CoreClubService.leaveNote(language: language, index: index, body: body)
            #endif
            sending = false
            guard let id else {
                HapticEngine.error()
                return
            }
            let note = CoreClubService.Cheers.Note(id: id, body: body, name: explain("Me"), by_me: true)
            withAnimation { cheers?.notes.append(note) }
            draft = ""
            writing = false
            // Yours goes up right away, in place of whatever was rising.
            flights = [NoteFlight(note: note, lane: 0)]
        }
    }

    private func delete(_ note: CoreClubService.Cheers.Note) {
        withAnimation { cheers?.notes.removeAll { $0.id == note.id } }
        Task { await CoreClubService.deleteNote(id: note.id) }
    }

    /// Sends the seat's notes up the cube one at a time, and round again,
    /// for as long as the sheet is open.
    private func runNotes() async {
        var i = 0
        while !Task.isCancelled {
            let notes = cheers?.notes ?? []
            if !notes.isEmpty, !writing, flights.isEmpty {
                let note = notes[i % notes.count]
                flights.append(NoteFlight(note: note, lane: i))
                i += 1
            }
            // Strictly one at a time: wait out the one on screen.
            try? await Task.sleep(for: .seconds(RisingNote.lifetime + 0.4))
        }
    }

    private var tintColor: Color {
        detail.flatMap { FutureselfTheme(rawValue: $0.theme)?.tint } ?? .clear
    }

    private var tintBackground: some View {
        ZStack {
            Color(.systemGroupedBackground)
            LinearGradient(colors: [tintColor.opacity(0.45), tintColor.opacity(0.12), .clear],
                           startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.3), value: detail?.theme)
    }

    private func load() async {
        #if DEBUG
        if let preview {
            detail = preview
            cheers = .init(hearts: 23, hearted: false, mine: preview.mine, notes: [
                .init(id: 1, body: "축하해요! 30일 대단해요", name: "Mina", by_me: false),
                .init(id: 2, body: "I'm on day 12, see you soon!", name: "Jonas", by_me: false),
                .init(id: 3, body: "발표 꼭 해내세요 👏", name: "Sora", by_me: false),
                .init(id: 4, body: "You made it 🎉", name: nil, by_me: false),
            ])
            loaded = true
            return
        }
        #endif
        async let d = CoreClubService.fetchSeatDetail(language: language, index: index)
        async let c = CoreClubService.fetchCheers(language: language, index: index)
        (detail, cheers) = await (d, c)
        loaded = true
        if cheers?.mine == true { await CoreClubService.markCheersSeen(language: language) }
    }

    private func save() async {
        saving = true
        HapticEngine.medium()
        await CoreClubService.setEngraving(language: language, name: name, hope: hope)
        await load()
        saving = false
        editing = false
    }
}

/// Telegram/Threads-style spoiler cover over a line that is never revealed:
/// blurred placeholder lettering under drifting, twinkling specks. A tap
/// shivers it and buzzes, and nothing opens.
private struct HopeVeil: View {
    @State private var shake = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            Text(verbatim: "Hidden words under the veil here")
                .font(.body)
                .foregroundStyle(.secondary)
                .blur(radius: 7)
                .opacity(0.55)
                .accessibilityHidden(true)
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    var rng = SeededRandom(seed: 7)
                    for _ in 0..<170 {
                        let x0 = rng.next() * size.width, y0 = rng.next() * size.height
                        let speed = 4 + rng.next() * 8, phase = rng.next() * .pi * 2
                        let x = (x0 + CGFloat(t) * speed).truncatingRemainder(dividingBy: size.width)
                        let y = y0 + sin(CGFloat(t) * 1.3 + phase) * 2.5
                        let alpha = 0.35 + 0.65 * (0.5 + 0.5 * sin(CGFloat(t) * 3 + phase))
                        let r = 0.6 + rng.next() * 0.9
                        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                                 with: .color(.primary.opacity(alpha)))
                    }
                }
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
        .modifier(Shiver(amount: CGFloat(shake)))
        .onTapGesture {
            HapticEngine.light()
            withAnimation(.linear(duration: 0.35)) { shake += 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(Text(explain("Only Core members can see this.")))
    }

    private struct Shiver: GeometryEffect {
        var amount: CGFloat
        var animatableData: CGFloat {
            get { amount }
            set { amount = newValue }
        }
        func effectValue(size: CGSize) -> ProjectionTransform {
            ProjectionTransform(CGAffineTransform(translationX: 5 * sin(amount * .pi * 6), y: 0))
        }
    }

    /// The specks are laid out the same way every frame (and on every
    /// phone); only time moves them.
    private struct SeededRandom {
        var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
        mutating func next() -> CGFloat {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat((state >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
        }
    }
}

struct NoteFlight: Identifiable {
    let id = UUID()
    let note: CoreClubService.Cheers.Note
    /// Which of three horizontal lanes it rises in, so two in a row don't
    /// stack on top of each other.
    let lane: Int
}

struct HeartFlight: Identifiable {
    let id = UUID()
    let drift: CGFloat
    let delay: Double
    let size: CGFloat
}

/// One note on its way up, alone on screen: it fades in as it rises from
/// the bottom, drifts a little, then fades out as it rises on. The next one
/// starts only once this one is gone (`RisingNote.lifetime`).
private struct RisingNote: View {
    let flight: NoteFlight
    var onDone: () -> Void
    @State private var phase = 0

    static let lifetime: TimeInterval = 4.4

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: flight.note.name ?? explain("Someone"))
                .font(.caption2.weight(.bold))
            Text(verbatim: flight.note.body)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .offset(y: [8, -6, -30, -46][phase])
        .opacity(phase == 0 || phase == 3 ? 0 : 1)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) { phase = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                withAnimation(.linear(duration: 2.6)) { phase = 2 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.4) {
                withAnimation(.easeIn(duration: 0.9)) { phase = 3 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.lifetime) { onDone() }
        }
    }
}

private struct RisingHeart: View {
    let flight: HeartFlight
    var onDone: () -> Void
    @State private var up = false

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: flight.size))
            .foregroundStyle(.red)
            .offset(x: up ? flight.drift : 0, y: up ? -CoreCubeView.unit * 1.6 : 0)
            .scaleEffect(up ? 1.15 : 0.4)
            .opacity(up ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6).delay(flight.delay)) { up = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.7 + flight.delay) { onDone() }
            }
    }
}
