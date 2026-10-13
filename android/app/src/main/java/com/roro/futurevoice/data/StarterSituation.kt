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
    /** Prompt-only: the LEARNER's side of the situation, for the "try
     *  saying" coach, which otherwise sees only the title and the role. */
    val learnerSide: String? = null,
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
        /** The starter a scenario was minted from, if any — from every chip's
         *  set, since a purpose chip (`DiscoverChip`) mints the same way. */
        fun of(scenario: Scenario?): StarterSituation? =
            scenario?.starterId?.let { id -> catalog.firstOrNull { it.id == id } }

        /** Every starter on any chip, each once. */
        val catalog: List<StarterSituation> by lazy {
            val seen = mutableSetOf<String>()
            (all + interview + work + life + travel).filter { seen.add(it.id) }
        }

        /**
         * Meeting someone new is the one starter that is NOT open (iOS
         * 43810e21, founder): with only the open note the stranger "followed
         * whatever the learner brought up", nobody brought anything up, and the
         * call drifted into TV shows — a chat between friends. What actually
         * happens when a learner meets a native is getting to know each other,
         * and the stranger has to ASK for it.
         */
        private const val MEETING_NOTE = "You're a native speaker meeting the learner for the first time — at a " +
            "get-together, a class, through a friend. They're from another country " +
            "and learning your language, and you're curious about them. Whatever " +
            "this prompt says about the user, YOU know none of it yet: you find out " +
            "by asking. Spend the call getting to know each other the way two people " +
            "really do at a first meeting: their name, where they're from, whether " +
            "they work or study and what, how long they've been here and what " +
            "brought them, why they're learning the language. One thing at a time, " +
            "follow up on what they answer, and give your own answer too (your name, " +
            "your work, where you're from) so it's an exchange, not an interview. " +
            "Stay on getting to know each other — no TV, films, news or other small " +
            "talk unless they bring it up. One short line at a time, no speech. " +
            "You are two adults who have never met, so address them in the POLITE " +
            "form the whole call (German Sie, French vous, Spanish usted, Korean " +
            "존댓말, Japanese です・ます) and never switch to the informal one on " +
            "your own; only if the learner offers it."

        private const val OPEN_NOTE = "Keep it open and easygoing: one short line the way this person really talks at work (no \"welcome\" speech, no script), then follow whatever the learner brings up. Never push a task, a checklist or specifics they haven't raised."

        val all: List<StarterSituation> = listOf(
            StarterSituation(
                id = "introduce-yourself", icon = "hand.wave.fill",
                title = R.string.meeting_someone_new, role = R.string.someone_you_just_met,
                showsRole = false,
                notes = MEETING_NOTE,
                openers = mapOf(
                    "en" to listOf("Hi! I don't think we've met yet.", "Hello! Nice to meet you."),
                    "ko" to listOf("안녕하세요! 처음 뵙는 것 같네요.", "안녕하세요, 반가워요!"),
                    "ja" to listOf("こんにちは！初めてですよね？", "はじめまして！よろしくお願いします。"),
                    "de" to listOf("Hallo! Ich glaube, wir kennen uns noch nicht.", "Hallo, freut mich, Sie kennenzulernen!"),
                ),
                learnerSide = "The learner is from another country and is learning this language; they have just met a native speaker for the first time. What they're asked is about themselves — their name, where they're from, whether they work or study and what, how long they've been here, why they're learning the language — and a natural answer gives that fact (as a bracketed example). Asking the same thing back is something a speaker does now and then, not on every answer. They have just met, so the learner speaks in the polite form (German Sie, French vous, Spanish usted, Korean 해요체 -요 endings, Japanese です・ます) whatever form the line uses. That is the ending only: honorifics that raise a person (Korean -(으)시-, Japanese 尊敬語) are for the OTHER person and never go on the learner's own actions — Korean 살았어요, not 사셨어요, even when the question asked 사셨어요."),
            StarterSituation(
                id = "order-cafe", icon = "cup.and.saucer.fill",
                title = R.string.at_a_caf, role = R.string.a_barista,
                notes = "You work behind the counter at a café. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! What can I get you?", "Hey! What are you having?"),
                    "ko" to listOf("안녕하세요, 뭐 드릴까요?", "안녕하세요! 주문하시겠어요?"),
                    "ja" to listOf("こんにちは、ご注文はお決まりですか？", "こんにちは！何にしますか？"),
                    "de" to listOf("Hallo! Was darf's sein?", "Hallo, was hätten Sie gern?"),
                )),
            StarterSituation(
                id = "order-restaurant", icon = "fork.knife",
                title = R.string.at_a_restaurant, role = R.string.a_server,
                notes = "You're a server at a restaurant. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Can I get you something to drink to start?", "Hi! Have you decided, or do you need a minute?"),
                    "ko" to listOf("안녕하세요, 주문하시겠어요?", "안녕하세요! 메뉴 보시고 편하게 불러 주세요."),
                    "ja" to listOf("こんにちは、お飲み物はどうされますか？", "こんにちは！ご注文はお決まりですか？"),
                    "de" to listOf("Hallo! Darf ich Ihnen schon etwas zu trinken bringen?", "Hallo! Haben Sie schon gewählt?"),
                )),
            StarterSituation(
                id = "ask-directions", icon = "map.fill",
                title = R.string.on_the_street, role = R.string.a_passerby,
                notes = "You're a friendly local walking down the street. The learner stops you to ask something — you speak only once they have, and help the way a kind stranger would. $OPEN_NOTE",
                learnerFirst = mapOf(
                    "en" to "Excuse me, how do I get to the [station]?",
                    "ko" to "저기요, [역]에 어떻게 가요?",
                    "ja" to "すみません、[駅]はどう行けばいいですか？",
                    "de" to "Entschuldigung, wie komme ich zum [Bahnhof]?",
                ),
                learnerFirstMeaning = R.string.excuse_me_how_do_i_get_to_the_station),
            StarterSituation(
                id = "shopping", icon = "bag.fill",
                title = R.string.at_a_clothing_store, role = R.string.a_shop_assistant,
                notes = "You work at a clothing store. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Looking for anything in particular?", "Hi! Is there anything I can help you find?"),
                    "ko" to listOf("안녕하세요, 찾으시는 거 있으세요?", "안녕하세요! 편하게 보시고 필요하면 불러 주세요."),
                    "ja" to listOf("こんにちは、何かお探しですか？", "こんにちは！気になるものがあったら声をかけてくださいね。"),
                    "de" to listOf("Hallo! Suchen Sie etwas Bestimmtes?", "Hallo! Kann ich Ihnen helfen?"),
                )),
            StarterSituation(
                id = "doctor-appointment", icon = "cross.case.fill",
                title = R.string.calling_a_clinic, role = R.string.a_clinic_receptionist,
                notes = "You answer the phone at a doctor's clinic; the learner is calling. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hello, this is the clinic. How can I help?", "Hi, clinic speaking. What can I do for you?"),
                    "ko" to listOf("네, 병원입니다. 무엇을 도와드릴까요?", "여보세요, 병원입니다. 말씀하세요."),
                    "ja" to listOf("はい、クリニックです。どうされましたか？", "お電話ありがとうございます。クリニックです。"),
                    "de" to listOf("Arztpraxis, guten Tag! Was kann ich für Sie tun?", "Praxis, hallo! Wie kann ich helfen?"),
                )),
            StarterSituation(
                id = "hotel-checkin", icon = "bed.double.fill",
                title = R.string.at_a_hotel, role = R.string.a_front_desk_clerk,
                notes = "You work at a hotel front desk. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Checking in?", "Hello! How can I help you?"),
                    "ko" to listOf("안녕하세요, 체크인하시나요?", "안녕하세요! 무엇을 도와드릴까요?"),
                    "ja" to listOf("こんにちは、チェックインですか？", "こんにちは！どうされましたか？"),
                    "de" to listOf("Hallo! Möchten Sie einchecken?", "Guten Tag! Wie kann ich Ihnen helfen?"),
                )),
            StarterSituation(
                id = "train-ticket", icon = "tram.fill",
                title = R.string.at_the_train_station, role = R.string.a_ticket_agent,
                notes = "You work at the ticket counter of a train station. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Where are you headed?", "Hi, what can I do for you?"),
                    "ko" to listOf("안녕하세요, 어디 가세요?", "안녕하세요! 어떻게 도와드릴까요?"),
                    "ja" to listOf("こんにちは、どちらまでですか？", "こんにちは！どうされましたか？"),
                    "de" to listOf("Hallo! Wohin soll's gehen?", "Hallo, was kann ich für Sie tun?"),
                )),
            StarterSituation(
                id = "make-plans", icon = "person.2.fill",
                title = R.string.with_a_friend, role = R.string.a_friend,
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
                title = R.string.with_a_neighbor, role = R.string.a_neighbor,
                showsRole = false,
                notes = "You're the learner's friendly neighbor, bumping into them near home. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Oh, hi! How are you doing?", "Hey, hello! Haven't seen you in a while."),
                    "ko" to listOf("어, 안녕하세요! 잘 지내셨어요?", "안녕하세요! 오랜만이에요."),
                    "ja" to listOf("あ、こんにちは！お元気ですか？", "どうも、こんにちは！お久しぶりです。"),
                    "de" to listOf("Oh, hallo! Wie geht's Ihnen?", "Hallo! Lange nicht gesehen."),
                )),
        )
        // MARK: - Purpose chips (`LearningPurpose`)

        private const val INTERVIEW_NOTE = "You're interviewing the learner for a job they applied for, in an " +
            "ordinary first-round interview. Ask the way a real interviewer does — " +
            "one question at a time, a short follow-up on what they actually said, " +
            "no lecture and no feedback on their answers. Stay friendly but " +
            "professional, and use the polite form the whole call (German Sie, " +
            "French vous, Spanish usted, Korean 존댓말, Japanese です・ます). " +
            "Never score them or tell them how they did."

        /** The Interview chip: the questions every first interview asks. */
        val interview: List<StarterSituation> by lazy { listOf(
            StarterSituation(
                id = "interview-about-you", icon = "person.crop.square",
                title = R.string.tell_me_about_yourself, role = R.string.an_interviewer,
                notes = "$INTERVIEW_NOTE Open by asking them to introduce themselves, then follow their answer: their background, what they do now, what they're looking for.",
                openers = mapOf(
                    "en" to listOf("Thanks for coming in. So, tell me a little about yourself.", "Nice to meet you. Why don't you start by telling me about yourself?"),
                    "ko" to listOf("와 주셔서 감사합니다. 먼저 간단히 자기소개 부탁드릴게요.", "반갑습니다. 자기소개부터 해 주시겠어요?"),
                )),
            StarterSituation(
                id = "interview-why-job", icon = "questionmark.bubble",
                title = R.string.why_do_you_want_this_job, role = R.string.an_interviewer,
                notes = "$INTERVIEW_NOTE This part of the interview is about motivation: why this role, why this company, why now, and where they see themselves.",
                openers = mapOf(
                    "en" to listOf("So, what made you apply for this position?", "Tell me, why do you want to work here?"),
                    "ko" to listOf("이 자리에 지원하신 이유가 궁금해요.", "왜 저희 회사에서 일하고 싶으세요?"),
                )),
            StarterSituation(
                id = "interview-strengths", icon = "chart.bar",
                title = R.string.strengths_and_weaknesses, role = R.string.an_interviewer,
                notes = "$INTERVIEW_NOTE This part is about their strengths, a weakness and what they do about it, and a concrete example of each.",
                openers = mapOf(
                    "en" to listOf("What would you say is your biggest strength?", "Let's talk about you. What are you really good at?"),
                    "ko" to listOf("본인의 가장 큰 강점은 뭐라고 생각하세요?", "스스로 생각하는 장점부터 들어 볼게요."),
                )),
            StarterSituation(
                id = "interview-experience", icon = "briefcase",
                title = R.string.a_project_you_re_proud_of, role = R.string.an_interviewer,
                notes = "$INTERVIEW_NOTE This part is about their experience: one project or situation from their work or studies, what they did, what went wrong, what they learned.",
                openers = mapOf(
                    "en" to listOf("Can you walk me through a project you're proud of?", "Tell me about a time you solved a difficult problem at work."),
                    "ko" to listOf("자랑스러웠던 프로젝트 하나 소개해 주시겠어요?", "어려운 문제를 해결했던 경험이 있으면 말씀해 주세요."),
                )),
            StarterSituation(
                id = "interview-salary", icon = "banknote",
                title = R.string.talking_about_salary, role = R.string.a_recruiter,
                notes = "$INTERVIEW_NOTE You're the recruiter at the end of the process, talking about salary expectations, start date and benefits. Be realistic and a little firm, the way recruiters are.",
                openers = mapOf(
                    "en" to listOf("Before we wrap up, what are your salary expectations?", "Let's talk about the offer. What range did you have in mind?"),
                    "ko" to listOf("마무리하기 전에, 희망 연봉은 어느 정도 생각하세요?", "처우 얘기를 좀 해 볼까요? 생각하신 범위가 있으세요?"),
                )),
        ) }

        /** The Work chip: speaking moments of an ordinary working week. */
        val work: List<StarterSituation> by lazy { listOf(
            StarterSituation(
                id = "work-meeting", icon = "person.3.fill",
                title = R.string.giving_your_view_in_a_meeting, role = R.string.a_coworker, showsRole = false,
                notes = "You're the learner's coworker in a small team meeting, asking what they think about the plan on the table. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("So, what do you think? Does this plan work for your side?", "Before we decide — any thoughts from you?"),
                    "ko" to listOf("어떻게 생각하세요? 이 계획, 그쪽 입장에선 괜찮을까요?", "결정하기 전에, 의견 있으세요?"),
                )),
            StarterSituation(
                id = "work-update", icon = "chart.line.uptrend.xyaxis",
                title = R.string.your_project_update, role = R.string.your_manager,
                notes = "You're the learner's manager in a weekly one-on-one, asking how their work is going. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hey, how's everything going on your side this week?", "So, where are we with your project?"),
                    "ko" to listOf("이번 주 일은 어떻게 돼 가요?", "맡은 프로젝트는 지금 어디까지 왔어요?"),
                )),
            StarterSituation(
                id = "work-client", icon = "phone.fill",
                title = R.string.a_call_with_a_client, role = R.string.a_client,
                notes = "You're a client calling the learner's company about something you need. Be polite, a bit busy, and expect clear answers. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi, thanks for taking my call. Do you have a minute?", "Hello! I wanted to check in about our order."),
                    "ko" to listOf("안녕하세요, 통화 괜찮으세요?", "안녕하세요! 저희 주문 건 때문에 연락드렸어요."),
                )),
            StarterSituation(
                id = "work-small-talk", icon = "cup.and.saucer",
                title = R.string.small_talk_with_a_coworker, role = R.string.a_coworker, showsRole = false,
                notes = "You're the learner's coworker, chatting by the coffee machine. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Morning! Busy day?", "Hey! How was your weekend?"),
                    "ko" to listOf("좋은 아침이에요! 오늘 바빠요?", "주말 잘 보냈어요?"),
                )),
        ) }

        /** The Life chip: living somewhere, not visiting it. */
        val life: List<StarterSituation> by lazy { listOf(
            StarterSituation(
                id = "life-landlord", icon = "key.fill",
                title = R.string.calling_your_landlord, role = R.string.your_landlord,
                notes = "You're the learner's landlord, answering the phone. Something in the flat probably needs fixing. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hello? Oh, hi. What can I do for you?", "Hi there, is everything all right with the flat?"),
                    "ko" to listOf("여보세요? 아, 네. 무슨 일이세요?", "안녕하세요, 집에 무슨 문제 있으세요?"),
                )),
            StarterSituation(
                id = "life-town-hall", icon = "building.columns.fill",
                title = R.string.at_the_town_hall, role = R.string.a_clerk,
                notes = "You're a clerk at the town hall's registration desk. You're busy but correct, and you ask for the documents you need. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Next, please. How can I help you?", "Good morning. What do you need today?"),
                    "ko" to listOf("다음 분이요. 어떤 일로 오셨어요?", "안녕하세요. 무슨 업무 보러 오셨어요?"),
                )),
            StarterSituation(
                id = "life-teacher", icon = "figure.and.child.holdinghands",
                title = R.string.your_child_s_teacher, role = R.string.a_teacher,
                notes = "You're the teacher of the learner's child, at pick-up time or a short parent meeting. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Oh, hello! Do you have a minute? I wanted to tell you about today.", "Hi! Thanks for coming in."),
                    "ko" to listOf("아, 안녕하세요! 잠깐 시간 괜찮으세요? 오늘 있었던 일 말씀드리려고요.", "안녕하세요! 와 주셔서 감사해요."),
                )),
        ) + all.filter { it.id in listOf("doctor-appointment", "neighbor-small-talk") } }

        /** The Travel chip: being a visitor. */
        val travel: List<StarterSituation> by lazy { listOf(
            StarterSituation(
                id = "travel-airport", icon = "airplane",
                title = R.string.at_the_check_in_desk, role = R.string.an_airline_agent,
                notes = "You're an agent at an airline check-in desk. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi! Where are you flying today?", "Good morning. Passport, please."),
                    "ko" to listOf("안녕하세요! 오늘 어디로 가세요?", "안녕하세요. 여권 부탁드릴게요."),
                )),
            StarterSituation(
                id = "travel-problem", icon = "exclamationmark.bubble",
                title = R.string.when_something_goes_wrong, role = R.string.a_front_desk_clerk,
                notes = "You're at a hotel front desk. The learner comes to you because something went wrong — the room, a booking, lost luggage; let them say what. $OPEN_NOTE",
                openers = mapOf(
                    "en" to listOf("Hi, is everything all right?", "Hello! What can I do for you?"),
                    "ko" to listOf("안녕하세요, 무슨 문제 있으세요?", "안녕하세요! 뭘 도와드릴까요?"),
                )),
        ) + all.filter { it.id in listOf("hotel-checkin", "train-ticket", "ask-directions", "order-restaurant") } }
    }
}
