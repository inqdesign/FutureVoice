import Foundation

/// How fast the fluent self speaks, chosen by the learner in Me → Voice.
///
/// ElevenLabs takes `voice_settings.speed` (0.7–1.2) and nothing here sent it
/// until 2026-09-23. It is a SYNTHESIS setting, not playback: the words are
/// spoken more slowly rather than a recording being played slow, so the voice
/// keeps its pitch and still sounds like the learner.
///
/// **Normal is 0.9, not "send nothing"** — picked by ear in the ElevenLabs
/// playground against the production settings (turbo v2.5, stability 55,
/// similarity 90, style 0, speaker boost on), as the most natural reading in
/// English AND Korean. That is a real change to the shipped voice, and a
/// measurable one: `scripts/tts-speed-probe.sh` puts 0.9 at +13% length over
/// sending nothing (0.95 was +3.3%, inside the synthesizer's own take-to-take
/// variance, and was set aside for this after a second listen).
///
/// **There is one slow rung, 0.8**, ~12% below Normal and heard as clearly
/// slower. 0.85 is not offered: from 0.9 it is a 6% step, near enough to the
/// variance above that a learner cannot reliably hear it, and a rung nobody
/// can hear teaches them the control is fake. A third rung below 0.8 waits on
/// an ear — nothing under it has been listened to, and ElevenLabs' own floor
/// is 0.7.
///
/// The same probe retired the one objection on file. `CoachingLanguage.breathPunctuation`
/// records that `speed: 0.9` "slowed the words while REDUCING the pauses" —
/// measured on one Korean line in 2026-09-15. Across five lines the pauses hold
/// or grow (0.69 s → 0.98 s of silence per 10 s of audio at 0.9), so slowing the
/// voice does not cost it its breath. The punctuation rule is what buys the
/// breaths and is untouched by this.
enum SpeechSpeed: String, CaseIterable, Sendable {
    case normal
    case slow

    static let key = "futurevoice.speechSpeed"

    var multiplier: Double {
        switch self {
        case .normal: return 0.90
        case .slow:   return 0.80
        }
    }

    /// Part of every cache key and idempotency key: the same line at two speeds
    /// is two different recordings, with different word timings, and one key
    /// for both would play yesterday's take under today's karaoke.
    ///
    /// **Normal's tag is EMPTY, so the cache from before this setting existed
    /// stays reachable** (user decision, 2026-09-23: audio already produced is
    /// left alone — the same rule `PhraseAudioStore` has always had for a
    /// re-cloned voice). Those files were made with no speed at all, so a
    /// learner on Normal hears them at 1.0 and every NEW line at 0.9; that gap
    /// was judged the right price against re-billing a whole library. Only the
    /// slow rung, which is meant to sound different, gets its own key.
    var cacheTag: String {
        self == .normal ? "" : String(format: "s%.2f", multiplier)
    }

    var label: String {
        switch self {
        case .normal: return explain("Normal")
        case .slow:   return explain("Slower")
        }
    }

    /// Read from defaults rather than taken as a parameter: the voice is
    /// synthesized from a dozen surfaces (call, scenes, shadow, drills,
    /// library, the daily call's voicemail) and every one of them speaks to
    /// the same learner. Threading a speed through all of them would mean a
    /// surface that forgot it, which is a voice that changes pace mid-app.
    static var current: SpeechSpeed {
        UserDefaults.standard.string(forKey: key).flatMap(SpeechSpeed.init(rawValue:)) ?? .normal
    }
}
