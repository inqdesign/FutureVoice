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

    /// The accent every new clone is remixed into — the FIRST option of the
    /// language (2026-10-08, founder decision; German learners had the same
    /// invented accent). A clone straight off the recording has no accent of its
    /// own in the target language — from a Korean take the model invents one
    /// per line, and ~75% of English lines came out Indian (measured
    /// 2026-09-30); a remix fixed it 30/30. So nobody gets the un-remixed
    /// voice by default: American, with the catalog's others to pick from.
    /// The plain clone is still reachable ("Remove accent" in Me → Voice),
    /// just no longer on the onboarding pills. Nil = no remix for this
    /// language.
    static func defaultAccent(for language: String) -> VoiceAccent? {
        options(for: language).first
    }

    /// The line the remix previews speak (ElevenLabs wants 100–1000 chars).
    /// Written to surface accent-revealing sounds — for English: t-flapping
    /// ("water"), the bath/trap split ("can't", "half past"), rhoticity
    /// ("water"), and a tag question's intonation.
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
        // One option: the default remix, nothing to pick — the pills only
        // show where there is a choice (`options.count > 1`).
        "de": [
            VoiceAccent(id: "de-DE", label: "Standard German",
                        prompt: prompt("Standard German accent (Hochdeutsch) as spoken in Germany")),
        ],
    ]

    private static let samples: [String: String] = [
        // Kept just over upstream's 100-character floor (2026-10-08): the
        // line is only what the takes say, and 330 characters spent ~3x the
        // preview audio for no better judgement of the accent.
        "en": "I'll grab a bottle of water and a coffee around half past eight. "
            + "I can't be late again, the bus leaves at nine, doesn't it?",
        // Accent tells: ich/ach, the vocalised r ("aber", "später"), ü/ö,
        // final devoicing ("Tag", "Hund"), and the glottal stop before
        // vowel onsets.
        "de": "Morgen früh hole ich zwei Brötchen beim Bäcker, danach fahre ich "
            + "mit dem Zug nach München. Ich rufe dich später an, okay?",
    ]
}
