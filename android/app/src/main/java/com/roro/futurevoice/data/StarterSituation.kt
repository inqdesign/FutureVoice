package com.roro.futurevoice.data

import androidx.annotation.StringRes
import com.roro.futurevoice.R
import com.roro.futurevoice.talk.Scenario

/**
 * The ready-made situations on Talk's Everyday chip (iOS `StarterSituation`,
 * `5b0587a`) — a place and a person (a café, a clothing store, a neighbor),
 * startable with one tap and no writing. Until these existed the Scenarios
 * list held only situations the learner had built, so a beginner who
 * couldn't think of one had nothing to start.
 *
 * **Open on purpose.** A row is only where you are and who you are talking
 * to — never a task. The first cut carried one ("buy a shirt: size, color")
 * and the clothing store opened on "What size are you looking for?".
 *
 * **The greetings are written here, not generated**, per target language,
 * and stored on the minted scenario (`Scenario.openers`) — the call starts
 * instantly and asks Gemini for nothing. They are reused on every talk, so
 * nothing in them is tied to a time of day.
 *
 * A starter is not a second kind of scenario. The first tap that gets past
 * the billing gate mints an ordinary [Scenario] stamped with `starterId`;
 * every later tap refreshes that row from this catalog and keeps its talks,
 * curriculum and Practice book.
 */
data class StarterSituation(
    val id: String,
    /** iOS SF Symbol name — resolved through `Symbols.icon`. */
    val icon: String,
    /** Row title, which is also the scene — "At a clothing store". */
    @StringRes val title: Int,
    /** Who the counterpart is — `Scenario.role`. */
    @StringRes val role: Int,
    /** False where the title already names the person ("With a friend"). */
    val showsRole: Boolean = true,
    /** Prompt-only: what the counterpart is like. Never a task. */
    val notes: String,
    /** Greeting lines per target-language code (en · ko · ja · de). */
    val openers: Map<String, List<String>> = emptyMap(),
    /** The LEARNER opens (asking a stranger the way): the counterpart says
     *  nothing until spoken to, and the call shows this line as a way in. */
    val learnerFirst: Map<String, String>? = null,
    /** That line in the APP language, for the coach's meaning row. */
    @StringRes val learnerFirstMeaning: Int? = null,
) {
    /** The example first line, when the learner opens this one. */
    fun learnerFirstLine(language: String): String? =
        learnerFirst?.let { it[language.substringBefore('-').lowercase()] ?: it["en"] ?: "" }

    /**
     * The scenario to launch: the one this starter already minted, brought up
     * to date with this catalog, else a fresh unsaved one. [title] and [role]
     * are the resolved strings. The launcher saves it once the tap passes the
     * billing gate, so a paywalled tap leaves nothing behind.
     */
    fun scenario(scenarios: List<Scenario>, language: String, title: String, role: String): Scenario {
        val base = scenarios.firstOrNull { it.starterId == id }
            ?: Scenario(environment = title, role = role, notes = notes)
        // A language without written lines falls back to the generated
        // opener (null openers); a learner-first starter has none at all.
        val pool = if (learnerFirst == null) openers[language.substringBefore('-').lowercase()] else null
        val samePool = base.openers == pool
        return base.copy(
            environment = title, role = role, notes = notes,
            summary = title, category = title, categoryIcon = icon, starterId = id,
            openers = if (samePool) base.openers else pool,
            openerCursor = if (samePool) base.openerCursor else 0,
        )
    }

    companion object {
        /** The starter a scenario was minted from, if any. */
        fun of(scenario: Scenario?): StarterSituation? =
            scenario?.starterId?.let { id -> all.firstOrNull { it.id == id } }

        private const val OPEN_NOTE = "Keep it open and easygoing: one short line the way this person really talks at work (no \"welcome\" speech, no script), then follow whatever the learner brings up. Never push a task, a checklist or specifics they haven't raised."

        val all: List<StarterSituation> = listOf(
            StarterSituation(
                id = "introduce-yourself", icon = "hand.wave.fill",
                title = R.string.starter_meeting_title, role = R.string.starter_meeting_role,
                showsRole = false,
                notes = "You've just met the learner for the first time. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! I don't think we've met yet.", "Hello! Nice to meet you."),
                    "ko" to listOf("안녕하세요! 처음 뵙는 것 같네요.", "안녕하세요, 반가워요!"),
                    "ja" to listOf("こんにちは！初めてですよね？", "はじめまして！よろしくお願いします。"),
                    "de" to listOf("Hallo! Wir kennen uns noch nicht, oder?", "Hi, freut mich! Wie geht's?"),
                )),
            StarterSituation(
                id = "order-cafe", icon = "cup.and.saucer.fill",
                title = R.string.starter_cafe_title, role = R.string.starter_cafe_role,
                notes = "You work behind the counter at a café. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! What can I get you?", "Hey! What are you having?"),
                    "ko" to listOf("안녕하세요, 뭐 드릴까요?", "안녕하세요! 주문하시겠어요?"),
                    "ja" to listOf("こんにちは、ご注文はお決まりですか？", "こんにちは！何にしますか？"),
                    "de" to listOf("Hallo! Was darf's sein?", "Hallo, was hätten Sie gern?"),
                )),
            StarterSituation(
                id = "order-restaurant", icon = "fork.knife",
                title = R.string.starter_restaurant_title, role = R.string.starter_restaurant_role,
                notes = "You're a server at a restaurant. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Can I get you something to drink to start?", "Hi! Have you decided, or do you need a minute?"),
                    "ko" to listOf("안녕하세요, 주문하시겠어요?", "안녕하세요! 메뉴 보시고 편하게 불러 주세요."),
                    "ja" to listOf("こんにちは、お飲み物はどうされますか？", "こんにちは！ご注文はお決まりですか？"),
                    "de" to listOf("Hallo! Darf ich Ihnen schon etwas zu trinken bringen?", "Hallo! Haben Sie schon gewählt?"),
                )),
            StarterSituation(
                id = "ask-directions", icon = "map.fill",
                title = R.string.starter_street_title, role = R.string.starter_street_role,
                notes = "You're a friendly local walking down the street. The learner stops you to ask something — you speak only once they have, and help the way a kind stranger would. $OPEN_NOTE",
                learnerFirst = mapOf(
                    "en" to "Excuse me, how do I get to the [station]?",
                    "ko" to "저기요, [역]에 어떻게 가요?",
                    "ja" to "すみません、[駅]はどう行けばいいですか？",
                    "de" to "Entschuldigung, wie komme ich zum [Bahnhof]?",
                ),
                learnerFirstMeaning = R.string.starter_street_first_meaning),
            StarterSituation(
                id = "shopping", icon = "bag.fill",
                title = R.string.starter_shop_title, role = R.string.starter_shop_role,
                notes = "You work at a clothing store. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Looking for anything in particular?", "Hi! Is there anything I can help you find?"),
                    "ko" to listOf("안녕하세요, 찾으시는 거 있으세요?", "안녕하세요! 편하게 보시고 필요하면 불러 주세요."),
                    "ja" to listOf("こんにちは、何かお探しですか？", "こんにちは！気になるものがあったら声をかけてくださいね。"),
                    "de" to listOf("Hallo! Suchen Sie etwas Bestimmtes?", "Hallo! Kann ich Ihnen helfen?"),
                )),
            StarterSituation(
                id = "doctor-appointment", icon = "cross.case.fill",
                title = R.string.starter_clinic_title, role = R.string.starter_clinic_role,
                notes = "You answer the phone at a doctor's clinic; the learner is calling. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hello, this is the clinic. How can I help?", "Hi, clinic speaking. What can I do for you?"),
                    "ko" to listOf("네, 병원입니다. 무엇을 도와드릴까요?", "여보세요, 병원입니다. 말씀하세요."),
                    "ja" to listOf("はい、クリニックです。どうされましたか？", "お電話ありがとうございます。クリニックです。"),
                    "de" to listOf("Arztpraxis, guten Tag! Was kann ich für Sie tun?", "Praxis, hallo! Wie kann ich helfen?"),
                )),
            StarterSituation(
                id = "hotel-checkin", icon = "bed.double.fill",
                title = R.string.starter_hotel_title, role = R.string.starter_hotel_role,
                notes = "You work at a hotel front desk. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Checking in?", "Hello! How can I help you?"),
                    "ko" to listOf("안녕하세요, 체크인하시나요?", "안녕하세요! 무엇을 도와드릴까요?"),
                    "ja" to listOf("こんにちは、チェックインですか？", "こんにちは！どうされましたか？"),
                    "de" to listOf("Hallo! Möchten Sie einchecken?", "Guten Tag! Wie kann ich Ihnen helfen?"),
                )),
            StarterSituation(
                id = "train-ticket", icon = "tram.fill",
                title = R.string.starter_station_title, role = R.string.starter_station_role,
                notes = "You work at the ticket counter of a train station. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Where are you headed?", "Hi, what can I do for you?"),
                    "ko" to listOf("안녕하세요, 어디 가세요?", "안녕하세요! 어떻게 도와드릴까요?"),
                    "ja" to listOf("こんにちは、どちらまでですか？", "こんにちは！どうされましたか？"),
                    "de" to listOf("Hallo! Wohin soll's gehen?", "Hallo, was kann ich für Sie tun?"),
                )),
            StarterSituation(
                id = "make-plans", icon = "person.2.fill",
                title = R.string.starter_friend_title, role = R.string.starter_friend_role,
                showsRole = false,
                notes = "You're the learner's friend, catching up casually. Speak like a friend. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hey! How's it going?", "Hey, there you are! What's new?"),
                    "ko" to listOf("오, 안녕! 요즘 어때?", "야, 왔어? 잘 지냈어?"),
                    "ja" to listOf("おー、元気？", "あ、来た来た！最近どう？"),
                    "de" to listOf("Hey! Na, wie geht's?", "Hey, da bist du ja! Was gibt's Neues?"),
                )),
            StarterSituation(
                id = "neighbor-small-talk", icon = "house.fill",
                title = R.string.starter_neighbor_title, role = R.string.starter_neighbor_role,
                showsRole = false,
                notes = "You're the learner's friendly neighbor, bumping into them near home. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Oh, hi! How are you doing?", "Hey, hello! Haven't seen you in a while."),
                    "ko" to listOf("어, 안녕하세요! 잘 지내셨어요?", "안녕하세요! 오랜만이에요."),
                    "ja" to listOf("あ、こんにちは！お元気ですか？", "どうも、こんにちは！お久しぶりです。"),
                    "de" to listOf("Oh, hallo! Wie geht's Ihnen?", "Hallo! Lange nicht gesehen."),
                )),
        )
    }
}
