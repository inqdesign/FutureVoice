package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
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
