import Foundation

/// How fast the fluent self speaks, chosen by the learner in Me → Voice.
///
/// ElevenLabs takes `voice_settings.speed` (0.7–1.2) and nothing here sent it
/// until 2026-09-23. It is a SYNTHESIS setting, not playback: the words are
/// spoken more slowly rather than a recording being played slow, so the voice
/// keeps its pitch and still sounds like the learner.
///
/// **Three rungs — 1.0 · 0.9 · 0.8 — and the DEFAULT is the middle one.**
/// 0.9 was picked by ear in the ElevenLabs playground against the production
/// settings (turbo v2.5, stability 55, similarity 90, style 0, speaker boost
/// on) as the most natural reading in English AND Korean, so that is what
/// everyone gets. 1.0 is upstream's own speed — the clone as recorded — kept
/// on the ladder because the learner asked for it, and labelled **Normal**,
/// never "fast": nothing on this control speeds the voice up. The middle rung
/// is **Relaxed** (여유있게 — user's word, 2026-09-23), not "slower": it is the
/// default, and a default called slower reads as a handicap. Each step is
/// ~12% by `scripts/tts-speed-probe.sh` (0.9 = +13% over 1.0, 0.8 = +27%),
/// well clear of the synthesizer's own take-to-take variance (0.95 measured
/// +3.3% and two of five lines came back SHORTER). Don't add a 0.95 or an
/// 0.85: a rung the learner cannot hear teaches them the control is fake.
/// Below 0.8 nothing has been listened to; ElevenLabs' floor is 0.7.
///
/// The same probe retired the one objection on file. `CoachingLanguage.breathPunctuation`
/// records that `speed: 0.9` "slowed the words while REDUCING the pauses" —
/// measured on one Korean line in 2026-09-15. Across five lines the pauses hold
/// or grow (0.69 s → 0.98 s of silence per 10 s of audio at 0.9), so slowing the
/// voice does not cost it its breath. The punctuation rule is what buys the
/// breaths and is untouched by this.
enum SpeechSpeed: String, CaseIterable, Sendable {
    /// Ladder order, top to bottom. `rawValue` is what defaults store.
    case normal   // 1.0 — the clone at the speed it was recorded
    case slow     // 0.9 — the default
    case slower   // 0.8

    static let key = "futurevoice.speechSpeed"
    static let `default`: SpeechSpeed = .slow

    var multiplier: Double {
        switch self {
        case .normal: return 1.00
        case .slow:   return 0.90
        case .slower: return 0.80
        }
    }

    /// Part of every cache key and idempotency key: the same line at two speeds
    /// is two different recordings, with different word timings, and one key
    /// for both would play yesterday's take under today's karaoke.
    ///
    /// **The DEFAULT rung's tag is EMPTY, so the cache from before this setting
    /// existed stays reachable** (user decision, 2026-09-23: audio already
    /// produced is left alone — the same rule `PhraseAudioStore` has always
    /// had for a re-cloned voice). Those files were made with no speed at all,
    /// so a learner who never touches the setting hears them as they were and
    /// every NEW line at 0.9; that gap was judged the right price against
    /// re-billing a whole library. A rung the learner deliberately picks —
    /// including Normal, although its audio would match those old files — is a
    /// request for different audio and gets its own key; the empty tag can't
    /// tell an old 1.0 line from a new 0.9 one, so it belongs to the default
    /// alone.
    var cacheTag: String {
        self == Self.default ? "" : String(format: "s%.2f", multiplier)
    }

    var label: String {
        switch self {
        case .normal: return explain("Normal")
        case .slow:   return explain("Relaxed")
        case .slower: return explain("Slow")
        }
    }

    /// Read from defaults rather than taken as a parameter: the voice is
    /// synthesized from a dozen surfaces (call, scenes, shadow, drills,
    /// library, the daily call's voicemail) and every one of them speaks to
    /// the same learner. Threading a speed through all of them would mean a
    /// surface that forgot it, which is a voice that changes pace mid-app.
    static var current: SpeechSpeed {
        UserDefaults.standard.string(forKey: key).flatMap(SpeechSpeed.init(rawValue:)) ?? .default
    }
}
