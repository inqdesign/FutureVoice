import Foundation

/// A selectable output accent for the cloned voice, applied AFTER cloning via
/// ElevenLabs voice remixing (`elevenlabs-voice-remix`).
///
/// Exists because a clone recorded in the learner's NATIVE language carries no
/// target-language accent information at all — the TTS model fills that gap
/// with its own default (US English for `en`), which is wrong for, say, a
/// learner living in London. Remixing keeps the person and changes only the
/// accent; the learner auditions a few takes and keeps one.
struct VoiceAccent: Identifiable, Equatable {
    /// Stable id, reported to analytics ("en-GB").
    let id: String
    /// Row label — chrome, so target-language like all chrome.
    let label: String
    /// The remix instruction sent upstream as `voice_description`.
    let prompt: String
}

enum VoiceAccentCatalog {

    /// Accent choices for a target language. Empty = the picker never shows
    /// for that language; v1 ships English only. Adding a language means
    /// adding options AND a sample text below.
    static func options(for language: String) -> [VoiceAccent] {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return byLanguage[code] ?? []
    }

    /// The line the remix previews speak (ElevenLabs wants 100–1000 chars).
    /// Written to surface accent-revealing sounds — for English: t-flapping
    /// ("water", "better"), the bath/trap split ("can't", "half past"),
    /// rhoticity ("park", "there"), and a tag question's intonation.
    static func sampleText(for language: String) -> String {
        let code = LanguageCatalog.language(language)?.code ?? "en"
        return samples[code] ?? samples["en"]!
    }

    /// How far the remix may drift from the reference audio (upstream
    /// `prompt_strength`: 0 keeps almost everything of the recording, 1 keeps
    /// almost nothing). The prompt below ASKS for the same person, but this
    /// is the parameter that decides it — the first version sent nothing and
    /// let upstream choose, and every accent picked before 2026-09-18 came
    /// back recognisably less like the speaker. Low on purpose: an accent
    /// that sounds like someone else is worse than no accent. Chosen by ear
    /// with `scripts/voice-remix-probe.sh`; retune there, not by feel.
    static let promptStrength: Double = 0.3

    /// One shared shape so every option pulls equally hard toward "same
    /// person, different accent" — the remix must never drift into a new
    /// character, because speaker similarity is the product.
    private static func prompt(_ accent: String) -> String {
        "Keep this exact same voice: the same person, timbre, pitch, age and "
        + "character. Change ONLY the accent — the speaker now has a natural, "
        + "consistent \(accent). Do not change anything else about how the "
        + "voice sounds."
    }

    private static let byLanguage: [String: [VoiceAccent]] = [
        "en": [
            VoiceAccent(id: "en-US", label: "American",
                        prompt: prompt("General American English accent")),
            VoiceAccent(id: "en-GB", label: "British",
                        prompt: prompt("British English accent with standard Southern British pronunciation")),
            VoiceAccent(id: "en-AU", label: "Australian",
                        prompt: prompt("Australian English accent")),
        ],
    ]

    private static let samples: [String: String] = [
        "en": "Right — let me think about tomorrow. I'll grab a bottle of water "
            + "and a cup of coffee on the way, probably around half past eight. "
            + "I can't be late again; the last bus leaves at twenty to nine. "
            + "Honestly, the weather's been better lately, hasn't it? Maybe "
            + "I'll walk through the park instead, and I'll call you when I "
            + "get there.",
    ]
}
