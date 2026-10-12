package com.roro.futurevoice.talk

/**
 * The read-aloud script in the learner's NATIVE language — iOS
 * `CloneScriptStore.swift`, copied (2026-10-12). English and Korean are
 * hand-authored there; every other language falls back to the target-side
 * script [VoiceCloneScript], exactly as iOS does.
 *
 * Korean was trimmed 2026-10-12: the clone is made by Cartesia, which learns
 * from at most 60 s of a take. The recording itself is unchanged — the
 * learner keeps talking until they stop.
 */
object CloneScriptStore {

    val english: List<String> = listOf(
        "Hi. I'm recording this so my fluent self can sound like me. I'm curious. I'm patient. I want to sound like me — just a more confident version.",
        "Let me describe a moment from this week. The weather turned cooler than I expected. I was walking and caught myself thinking in two languages at once — one for what I saw, one for what I felt. Funny how that works.",
        "Here's a quick list, just to stretch the sounds: Monday morning, Wednesday afternoon, Friday night. Three, thirteen, thirty-three. A double espresso, a glass of water, and a window seat if you have one, please.",
        "Now a few different shapes: \"Could you actually repeat that?\" \"Wait — that's not quite right.\" \"Honestly, I'm not sure yet, but here's what I think.\" \"Oh, that's brilliant — say more.\"",
        "One more, a little slower this time. When I speak this language a year from now, I want it to feel easy. Not perfect — easy. Like I'm not translating anymore, just talking.",
        "Okay. I think that's enough of my voice for now. If this worked, the next voice you hear should sound a lot like me. Talk to me soon.",
    )

    val korean: List<String> = listOf(
        "안녕하세요. 저와 똑같은 목소리로, 훨씬 더 유창하게 말하는 제가 생긴다니 조금 신기하네요. 저는 궁금한 게 많고, 참을성도 있는 편이에요. 지금보다 조금만 더 당당한 저였으면 좋겠어요.",
        "이번 주에 있었던 일을 하나 이야기해 볼게요. 날씨가 생각보다 쌀쌀해져서 옷깃을 여미고 걸었어요. 걷다가 문득, 눈에 보이는 것과 마음에 떠오르는 생각이 서로 다른 말이라는 걸 느꼈어요.",
        "이번엔 소리를 좀 늘려 볼게요. 월요일 아침, 수요일 오후, 금요일 밤. 셋, 열셋, 서른셋. 따뜻한 커피 한 잔, 시원한 물 한 컵, 그리고 창가 자리 하나 부탁드려요.",
        "말투도 바꿔 볼게요. \"방금 그거 다시 한번 말해 줄래요?\" \"잠깐만요, 그건 좀 아닌 것 같은데요.\" \"우와, 그거 진짜 좋다. 더 얘기해 줘요.\"",
        "일 년 뒤에 이 언어로 말할 때는, 지금보다 훨씬 편했으면 좋겠어요. 완벽하지 않아도 괜찮아요. 번역하지 않고 그냥 말하는 것처럼요.",
        "자, 이 정도면 충분한 것 같아요. 잘 됐다면, 다음에 들리는 목소리는 저와 아주 비슷하게 들릴 거예요. 곧 다시 이야기해요.",
    )

    fun handAuthored(code: String): List<String>? = when (code.take(2)) {
        "en" -> english
        "ko" -> korean
        else -> VoiceCloneScript.handAuthored(code)
    }
}
