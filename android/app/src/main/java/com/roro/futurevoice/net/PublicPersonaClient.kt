package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.JsonObject
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.Request

/**
 * The shared persona pool (`public_personas`) — read anonymously, written
 * only by its owner (RLS). A row is either CURATED (`owner_user_id` null,
 * seeded by migration) or a real user's self-introduction; same pool, same
 * shape, and it self-mixes as users join.
 *
 * Intros are MATERIAL, so a row serves one `language` and the pool is
 * fetched per target language.
 */
class PublicPersonaClient(private val auth: AuthRepository) {

    @Serializable
    data class PublicPersona(
        val id: String,
        val owner_user_id: String? = null,
        val display_name: String = "",
        val intro: String = "",
        val location: String = "",
        val occupation: String = "",
        val interests: String = "",
        val conversation_style: String = "",
        val language: String = "en",
        val voice_preset_id: String = "",
        val kind: String? = null,
    ) {
        /** A published learner is a USER whatever `kind` says — ownership is the fact. */
        val isRealUser: Boolean get() = owner_user_id != null
    }

    private val columns =
        "id,owner_user_id,display_name,intro,location,occupation,interests," +
            "conversation_style,language,voice_preset_id,kind"

    // MARK: - My own row

    companion object {
        /** Set once the learner has taken control of their public intro by
         *  hand — published, edited or taken it down, or said "not now" to the
         *  preview. After that auto-sync never touches the row again. */
        const val MANUAL_INTRO_KEY = "futurevoice.publicIntroManaged"

        /** Set when the learner looked at the mirrored intro
         *  ([com.roro.futurevoice.ui.PublicIntroPreviewSheet]) and said yes.
         *  Until then NOTHING is published on their behalf: the onboarding
         *  profile was written for their own fluent self, not for strangers.
         *  Once set, the mirror keeps following profile edits. */
        const val AUTO_APPROVED_KEY = "futurevoice.publicIntroAutoApproved"

        /** The bar an ACTIVE pool row must clear, enforced in the database
         *  (`public_personas_intro_bounds`). A one-liner can't carry a
         *  conversation, and the same bar keeps thin rows out of the pool. */
        const val MIN_INTRO = 80

        fun prefs(context: android.content.Context): android.content.SharedPreferences =
            context.getSharedPreferences("futurevoice", 0)

        /**
         * Whether the mirrored intro still needs the learner's yes or no —
         * the trigger for the preview sheet. False once they decided either
         * way, and false while the profile is too thin to publish (there is
         * nothing to show them yet).
         */
        fun needsIntroDecision(
            prefs: android.content.SharedPreferences,
            persona: com.roro.futurevoice.talk.UserPersona?,
        ): Boolean {
            if (prefs.getBoolean(MANUAL_INTRO_KEY, false) || prefs.getBoolean(AUTO_APPROVED_KEY, false)) return false
            val p = persona ?: return false
            if (!p.isMinimallyComplete) return false
            return composedIntro(p).length >= MIN_INTRO
        }

        /**
         * The onboarding profile, folded into one spoken-style paragraph —
         * what a stranger's phone will speak as "you". Only what a person
         * would say on the first day at a language school: work, town, what
         * they need the language for, and the remembered lines at the rung
         * the learner set (`strangerLines`: the line, its gist, or nothing).
         *
         * `household` and `freeNotes` are deliberately NOT here — they were
         * written for the fluent self, and on iOS until 2026-09-15 "wife and
         * 4yo daughter at Kita" went out to every learner in the pool without
         * the author ever seeing the paragraph it was in.
         */
        fun composedIntro(p: com.roro.futurevoice.talk.UserPersona): String {
            val parts = ArrayList<String>()
            if (p.occupation.isNotEmpty()) parts.add(p.occupation)
            if (p.lengthOfStay.isNotEmpty() && p.city.isNotEmpty()) parts.add("${p.city} · ${p.lengthOfStay}")
            if (p.situations.isNotEmpty()) parts.add(p.situations.joinToString(", "))
            parts.addAll(p.strangerLines)
            return parts.joinToString("\n")
        }
    }

    /**
     * Mirror the onboarding profile into the pool so existing learners show
     * up in Find people without doing more than saying yes once. Runs at app
     * start and on every profile save; skips when the learner manages the
     * intro by hand, for a profile too thin to carry a conversation, or when
     * signed out.
     *
     * Before the learner has approved the mirror it publishes NOTHING — but a
     * row an earlier build published unasked is rewritten to the current
     * composition ([trimUnapprovedRow]), so the family and free-note lines
     * that build copied out stop being spoken by strangers' phones today.
     */
    suspend fun autoSyncMyPersona(
        context: android.content.Context,
        persona: com.roro.futurevoice.talk.UserPersona?,
        language: String,
    ) {
        val prefs = prefs(context)
        if (prefs.getBoolean(MANUAL_INTRO_KEY, false)) return
        val p = persona ?: return
        if (!p.isMinimallyComplete) return
        if (!prefs.getBoolean(AUTO_APPROVED_KEY, false)) {
            trimUnapprovedRow(p, language)
            return
        }
        publishMirror(p, language)
    }

    /**
     * Publish the composed profile as the learner's row. The voice is a
     * stable per-user pick so "you" doesn't change voices between launches.
     * True when the row is up.
     */
    suspend fun publishMirror(p: com.roro.futurevoice.talk.UserPersona, language: String): Boolean {
        val intro = composedIntro(p)
        // 80 because the DATABASE says 80: a lower client bar doesn't publish
        // thinner rows, it just fails the write on every launch.
        if (intro.length < MIN_INTRO) return false
        val uid = auth.userId ?: return false
        val catalog = com.roro.futurevoice.talk.StockPerson.catalog
        val voice = catalog[Math.floorMod(uid.hashCode(), catalog.size)]
        return runCatching {
            publishMine(
                displayName = p.displayName,
                intro = intro,
                location = listOf(p.city, p.country).filter { it.isNotBlank() }.joinToString(", "),
                occupation = p.occupation,
                interests = p.interests.joinToString(", "),
                voicePresetId = voice.voiceId,
                language = language,
            )
        }.isSuccess
    }

    /**
     * A row an older build put up without asking: rewrite its intro to what
     * the current composition allows, or take it down when that is too thin
     * to stand. NEVER inserts — a learner with no row yet gets one only
     * through the preview's yes.
     */
    private suspend fun trimUnapprovedRow(p: com.roro.futurevoice.talk.UserPersona, language: String) {
        val existing = runCatching { fetchMine(language) }.getOrNull() ?: return
        val intro = composedIntro(p)
        if (intro == existing.intro) return
        if (intro.length >= MIN_INTRO) {
            runCatching { patchIntro(existing.id, intro) }
        } else {
            runCatching { withdrawMine(language) }
        }
    }

    /** Rewrite ONE column of an existing row — never an insert. */
    private suspend fun patchIntro(rowId: String, intro: String) = withContext(Dispatchers.IO) {
        val body = Edge.json.encodeToString(JsonObject.serializer(), buildJsonObject { put("intro", intro) })
            .toRequestBody("application/json".toMediaType())
        val req = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas?id=eq.$rowId")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .header("Prefer", "return=minimal")
            .patch(body)
            .build()
        Edge.client.newCall(req).execute().use { resp ->
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, resp.body.string().take(512))
        }
    }

    /** Upsert by hand: the table has no unique key on (owner, language), so a
     *  blind insert would give one learner two rows in the same pool. */
    suspend fun publishMine(
        displayName: String, intro: String, location: String, occupation: String,
        interests: String, voicePresetId: String, language: String,
    ) = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext
        val row = buildJsonObject {
            put("owner_user_id", uid)
            put("display_name", displayName)
            put("intro", intro)
            put("location", location)
            put("occupation", occupation)
            put("interests", interests)
            put("language", language)
            put("voice_preset_id", voicePresetId)
            put("is_active", true)
        }
        val existing = fetchMine(language)
        val base = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas"
        val url = if (existing != null) "$base?id=eq.${existing.id}" else base
        val body = Edge.json.encodeToString(JsonObject.serializer(), row)
            .toRequestBody("application/json".toMediaType())
        val req = Request.Builder().url(url)
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .header("Prefer", "return=minimal")
            .let { if (existing != null) it.patch(body) else it.post(body) }
            .build()
        Edge.client.newCall(req).execute().use { resp ->
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, resp.body.string().take(512))
        }
    }

    /**
     * Take the learner's row out of the pool for this language.
     *
     * Learners who already met the persona keep their own past talks — those
     * are ordinary sessions on their own device, and nothing here reaches
     * them.
     */
    suspend fun withdrawMine(language: String) = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext
        val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas" +
            "?owner_user_id=eq.$uid&language=eq.$language"
        val req = Request.Builder().url(url)
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .header("Prefer", "return=minimal")
            .delete()
            .build()
        Edge.client.newCall(req).execute().use { resp ->
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, resp.body.string().take(512))
        }
    }

    /** The learner's own row for one language, if they have one. */
    suspend fun fetchMine(language: String): PublicPersona? = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext null
        val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas" +
            "?select=$columns&language=eq.$language&owner_user_id=eq.$uid"
        val req = Request.Builder().url(url)
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .build()
        Edge.client.newCall(req).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) return@use null
            Edge.json.decodeFromString(ListSerializer(PublicPersona.serializer()), raw).firstOrNull()
        }
    }

    /**
     * The whole active pool for one language — curated-catalog sized (tens,
     * not thousands), so one fetch beats server-side pagination. Your own
     * published row is filtered out: you don't meet yourself.
     */
    suspend fun fetchPool(language: String): List<PublicPersona> = withContext(Dispatchers.IO) {
        val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas" +
            "?select=$columns&language=eq.$language&is_active=eq.true"
        val request = Request.Builder().url(url)
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .build()
        Edge.client.newCall(request).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) throw EdgeError.Http(resp.code, raw.take(512))
            val mine = auth.userId?.lowercase()
            Edge.json.decodeFromString(ListSerializer(PublicPersona.serializer()), raw)
                .filterNot { it.owner_user_id?.lowercase() == mine }
        }
    }

    /**
     * Local substring search. A real learner's intro is NOT shown on their
     * card, so it must not be searchable either — a field that is queryable
     * while unreadable is a worse kind of exposed.
     */
    fun search(query: String, pool: List<PublicPersona>): List<PublicPersona> {
        val q = query.trim().lowercase()
        if (q.isEmpty()) return emptyList()
        return pool.filter { p ->
            val searchable = listOf(p.display_name, p.interests, p.occupation, p.location) +
                if (!p.isRealUser) listOf(p.intro) else emptyList()
            searchable.any { it.lowercase().contains(q) }
        }
    }
}
