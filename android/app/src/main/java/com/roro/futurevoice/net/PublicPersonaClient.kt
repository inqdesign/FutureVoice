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
        /** Set once the learner edits or takes down their intro BY HAND.
         *  After that auto-sync never touches the row again — an explicit
         *  choice always wins over a derived one. */
        const val MANUAL_INTRO_KEY = "futurevoice.publicIntroManaged"

        /** The bar an ACTIVE pool row must clear, enforced in the database
         *  (`public_personas_intro_bounds`). A one-liner can't carry a
         *  conversation, and the same bar keeps thin rows out of the pool. */
        const val MIN_INTRO = 80
    }


    /**
     * Publish the learner's onboarding profile into the pool, so existing
     * users appear without doing anything.
     *
     * Skipped entirely once the learner has managed the row by hand, and for
     * a profile too thin to carry a conversation — the pool's whole value is
     * that a row can be talked to.
     */
    suspend fun autoSyncMyPersona(
        context: android.content.Context,
        persona: com.roro.futurevoice.talk.UserPersona?,
        language: String,
    ) {
        if (context.getSharedPreferences("futurevoice", 0).getBoolean(MANUAL_INTRO_KEY, false)) return
        val p = persona ?: return
        if (!isMinimallyComplete(p)) return
        val intro = composedIntro(p)
        // 80 because the DATABASE says 80: `public_personas_intro_bounds`
        // rejects any active row under it. A lower client bar doesn't publish
        // thinner rows, it just fails the write silently on every launch —
        // and leaves the learner believing they are in the pool.
        if (intro.length < MIN_INTRO) return
        val uid = auth.userId ?: return
        // Stable per-user voice pick so "you" doesn't change voices between
        // launches — hash the user id into the preset catalog.
        val catalog = com.roro.futurevoice.talk.StockPerson.catalog
        val voice = catalog[Math.floorMod(uid.hashCode(), catalog.size)]
        runCatching {
            publishMine(
                displayName = p.displayName,
                intro = intro,
                location = listOf(p.city, p.country).filter { it.isNotBlank() }.joinToString(", "),
                occupation = p.occupation,
                interests = p.interests.joinToString(", "),
                voicePresetId = voice.voiceId,
                language = language,
            )
        }
    }

    /**
     * The onboarding profile, folded into one spoken-style paragraph. The
     * learner wrote these fields in their own words (often their native
     * language) — the conversation prompt's language guard keeps the talk in
     * the target language regardless.
     *
     * It reads ONLY fields the user typed about themselves. What the fluent
     * self learned in a call (`learnedNotes`) is deliberately absent:
     * something said to your own future self was not said to strangers.
     */
    private fun composedIntro(p: com.roro.futurevoice.talk.UserPersona): String {
        val parts = ArrayList<String>()
        if (p.occupation.isNotBlank()) parts.add(p.occupation)
        if (p.household.isNotBlank()) parts.add(p.household)
        if (p.lengthOfStay.isNotBlank() && p.city.isNotBlank()) parts.add("${p.city} · ${p.lengthOfStay}")
        if (p.situations.isNotEmpty()) parts.add(p.situations.joinToString(", "))
        if (p.freeNotes.isNotBlank()) parts.add(p.freeNotes)
        return parts.joinToString("\n")
    }

    private fun isMinimallyComplete(p: com.roro.futurevoice.talk.UserPersona): Boolean {
        val core = p.displayName.isNotBlank() && p.city.isNotBlank()
        val context = p.occupation.isNotBlank() || p.household.isNotBlank() ||
            p.interests.isNotEmpty() || p.situations.isNotEmpty()
        return core && context
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
