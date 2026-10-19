// The four preset voices (the other person in a scene, a Find-people
// stranger's slot) — what a stored preset id SPEAKS as, per language.
//
// A preset id is a SLOT (VoicePreset in Models.swift): what is stored on a
// person, a scenario or a persona row is one of four ids from the earlier
// provider, and the app swaps in the language's own Cartesia voice at the
// network edge (`VoicePreset.speaking`). The server does the same swap for
// whatever still arrives as a slot: an older build, and the four Korean
// stand-ins builds from 2026-09-28 sent for Korean and Japanese learners. Mirror of `voicedBySlot` in Models.swift and
// gateway/src/presets.ts — keep the three in step.

const SLOTS = ["NDTYOmYEjbDIVCKB35i3", "UgBBYS2sOqTuMpoF3BR0",
               "FF59babHL8N8gfTgtBMT", "L0Dsvb3SLTyegXwtm47J"] as const

/** The Korean voices that once stood in for the slots, in slot
 *  order (Sian, KO-Calm, Han, Joon). */
const LEGACY_KOREAN = ["5n5gqmaQi9Ewevrz7bOS", "L4az9Gb378GIycFl2nAB",
                       "8jHHF8rMqMlg8if2mOUe", "AKF7f2y1L8ktV5vxXILw"]

/** Cartesia voice per language, in slot order. */
const VOICED: Record<string, string[]> = {
  en: ["999df508-4de5-40a7-8bd3-8c12f678c284", "c961b81c-a935-4c17-bfb3-ba2239de8c2f",
       "e5d4c33a-d8f6-46e8-a10f-b5afecc35648", "3d5ce2fb-e56c-42f0-9ed9-4662484063b4"],
  de: ["1ade29fc-6b82-4607-9e70-361720139b12", "dff81230-ff75-49a4-af44-f6b2f43500d8",
       "3f4ade23-6eb4-4279-ab05-6a144947c4d5", "afa425cf-5489-4a09-8a3f-d3cb1f82150d"],
  ko: ["cac92886-4b7c-4bc1-a524-e0f79c0381be", "537a82ae-4926-4bfb-9aec-aff0b80a12a5",
       "cd6c48a9-774b-4397-98b4-9948c0a790f0", "f7755efb-1848-4321-aa22-5e5be5d32486"],
  ja: ["c7eafe22-8b71-40cd-850b-c5a3bbd8f8d2", "b8e1169c-f16a-4064-a6e0-95054169e553",
       "7be83d14-4707-43ad-9774-e24eb38320f0", "6b92f628-be90-497c-8f4c-3b035002df71"],
  es: ["3797b3c0-ab71-40dc-bfa0-a8c6ff9c1e8b", "7b001dff-b8b2-4da7-92e4-5c794798effa",
       "727f663b-0e90-4031-90f2-558b7334425b", "e9f0368b-3662-4a01-b037-e13ca5203c74"],
}

function slotIndex(voiceId: string): number {
  const i = SLOTS.indexOf(voiceId as typeof SLOTS[number])
  return i >= 0 ? i : LEGACY_KOREAN.indexOf(voiceId)
}

/** Whether `voiceId` is a preset slot (or a legacy stand-in for one). */
export function isPresetSlot(voiceId: string): boolean {
  return slotIndex(voiceId) >= 0
}

/** The Cartesia voice a slot speaks in `language`; a language without its
 *  own four speaks English's. Null when `voiceId` is not a slot. */
export function presetVoice(voiceId: string, language: string): string | null {
  const i = slotIndex(voiceId)
  if (i < 0) return null
  const lang = language.toLowerCase().split("-")[0]
  return (VOICED[lang] ?? VOICED.en)[i]
}
