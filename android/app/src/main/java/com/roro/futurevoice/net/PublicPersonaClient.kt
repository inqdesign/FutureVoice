package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.AvatarStore
import com.roro.futurevoice.data.CounterpartPhotoStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
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
        /** What they say when a learner comes across them on the map — written
         *  at publish (by the author, or for them). Empty on rows from before. */
        val greeting: String? = null,
    ) {
        /** A published learner is a USER whatever `kind` says — ownership is the fact. */
        val isRealUser: Boolean get() = owner_user_id != null
    }

    private val columns =
        "id,owner_user_id,display_name,intro,location,occupation,interests," +
            "conversation_style,language,voice_preset_id,kind,greeting"

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

        /** The voice the learner picked for their public profile
         *  ([com.roro.futurevoice.ui.ProfileVoiceRows]) — iOS `chosenVoiceKey`. */
        const val CHOSEN_VOICE_KEY = "futurevoice.publicIntro.voice"

        /** The application context the photo reads and writes need — set
         *  once from `FutureVoiceApplication`, like [PublicIntroComposer]. */
        @Volatile private var appContext: android.content.Context? = null
        fun init(context: android.content.Context) { appContext = context.applicationContext }

        /**
         * Fire-and-forget [pushMyPhoto] for a store that has no scope of its
         * own (an avatar change): a published profile wears this face too;
         * no row, no write.
         */
        fun pushMyPhotoLater() {
            photoScope.launch { runCatching { PublicPersonaClient(AuthRepository()).pushMyPhoto() } }
        }
        private val photoScope = kotlinx.coroutines.CoroutineScope(
            kotlinx.coroutines.SupervisorJob() + Dispatchers.IO)

        /** Which people's photos came from the pool — iOS `adoptedPhotosKey`. */
        const val POOL_PHOTOS_KEY = "futurevoice.poolPhotos"

        /**
         * ~96 px, re-encoded through a fresh bitmap so nothing of the original
         * file survives; base64 in the row, never Supabase Storage.
         */
        fun publicPhoto(img: android.graphics.Bitmap): String? {
            val side = minOf(img.width, img.height)
            if (side <= 0) return null
            val target = 96
            val out = android.graphics.Bitmap.createBitmap(target, target, android.graphics.Bitmap.Config.ARGB_8888)
            val scale = target.toFloat() / side
            val w = img.width * scale
            val h = img.height * scale
            val left = (target - w) / 2
            val top = (target - h) / 2
            android.graphics.Canvas(out).drawBitmap(img, null,
                android.graphics.RectF(left, top, left + w, top + h),
                android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
            val bytes = java.io.ByteArrayOutputStream().use {
                out.compress(android.graphics.Bitmap.CompressFormat.JPEG, 70, it); it.toByteArray()
            }
            return android.util.Base64.encodeToString(bytes, android.util.Base64.NO_WRAP)
        }

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
        fun composedIntro(p: com.roro.futurevoice.talk.UserPersona,
                          language: String = com.roro.futurevoice.data.CoreVocabulary.activeLanguage() ?: "en"): String =
            // The portrait if it has been written, the notes otherwise — sync,
            // never asks the model (it is the density gate's); screens that
            // show the paragraph await [PublicIntroComposer.compose].
            PublicIntroComposer.current(p, language)
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
        publishMirror(p, language, prefs)
    }

    /**
     * Publish the composed profile as the learner's row. The voice is the one
     * the learner picked ([CHOSEN_VOICE_KEY]); else the one already on their
     * row, so "you" never changes voices between launches; else a stable
     * per-user preset. True when the row is up.
     */
    suspend fun publishMirror(
        p: com.roro.futurevoice.talk.UserPersona,
        language: String,
        prefs: android.content.SharedPreferences? = null,
    ): Boolean {
        val intro = PublicIntroComposer.compose(p, language)
        // 80 because the DATABASE says 80: a lower client bar doesn't publish
        // thinner rows, it just fails the write on every launch.
        if (intro.length < MIN_INTRO) return false
        val uid = auth.userId ?: return false
        val picked = prefs?.getString(CHOSEN_VOICE_KEY, null)
        val voiceId = picked
            ?: runCatching { fetchMine(language)?.voice_preset_id }.getOrNull()?.takeIf { it.isNotBlank() }
            ?: run {
                val catalog = com.roro.futurevoice.talk.StockPerson.catalog
                catalog[Math.floorMod(uid.hashCode(), catalog.size)].voiceId
            }
        return runCatching {
            publishMine(
                displayName = p.displayName,
                intro = intro,
                location = listOf(p.city, p.country).filter { it.isNotBlank() }.joinToString(", "),
                occupation = p.occupation,
                interests = p.interests.joinToString(", "),
                voicePresetId = voiceId,
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
        val intro = PublicIntroComposer.compose(p, language)
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
        greeting: String? = null,
    ) = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext
        val existing = fetchMine(language)
        // The greeting is made at publish: the author's own words when given,
        // else the one already on the row, else one written from the intro.
        var line = greeting?.trim().orEmpty()
        if (line.isEmpty()) line = existing?.greeting.orEmpty()
        if (line.isEmpty()) {
            val me = com.roro.futurevoice.data.Counterpart(
                name = displayName, voicePresetId = voicePresetId,
                remoteId = "self", intro = intro, location = location)
            line = runCatching {
                com.roro.futurevoice.talk.GreetingEngine.write(me, null, language)
            }.getOrNull().orEmpty()
        }
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
            put("greeting", line)
        }
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
        pushMyPhoto()
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
    suspend fun fetchPool(language: String): List<PublicPersona> {
        val rows = fetchPoolRows(language)
        adoptPhotos(rows)
        return rows
    }

    private suspend fun fetchPoolRows(language: String): List<PublicPersona> = withContext(Dispatchers.IO) {
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

    // MARK: - Faces

    /**
     * Put the learner's current photo on every row they own (every target
     * language), or take it off when they have none. A learner with no row
     * updates nothing, so this is safe to call on any avatar change.
     *
     * The photo (2026-10-13, founder: publishing the profile already means it
     * is public) rides in its OWN read and its OWN write, never in [columns]
     * or the publish row: a select or update naming a column the database
     * hasn't got fails the WHOLE request, and the pool would come back empty
     * or the publish would fail — here a missing column just means initials.
     */
    suspend fun pushMyPhoto() = withContext(Dispatchers.IO) {
        val context = appContext ?: return@withContext
        val uid = auth.userId ?: return@withContext
        val photo = AvatarStore.load(context)?.let(::publicPhoto)
        val patch = buildJsonObject { put("photo", photo) }
        val body = Edge.json.encodeToString(JsonObject.serializer(), patch)
            .toRequestBody("application/json".toMediaType())
        val req = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas?owner_user_id=eq.$uid")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .header("Prefer", "return=minimal")
            .patch(body)
            .build()
        runCatching { Edge.client.newCall(req).execute().close() }
    }

    /**
     * Save the pool's learner photos into [CounterpartPhotoStore] under each
     * person's local id (on Android the remote id itself, [asCounterpart]) —
     * the one every face on screen already reads — so nothing that draws a
     * person needed to change. [POOL_PHOTOS_KEY] remembers which came from
     * the pool (remote id → a fingerprint of the photo), so a re-load
     * rewrites nothing that hasn't changed and a photo the author took down
     * is deleted — without ever touching a photo the learner picked for
     * someone themselves.
     */
    private suspend fun adoptPhotos(rows: List<PublicPersona>) {
        val context = appContext ?: return
        val ids = rows.filter { it.owner_user_id != null }.map { it.id }
        if (ids.isEmpty()) return
        val got: List<PhotoRow> = withContext(Dispatchers.IO) {
            runCatching {
                val url = "${Config.supabaseUrl.trimEnd('/')}/rest/v1/public_personas" +
                    "?select=id,photo&id=in.(${ids.joinToString(",")})"
                val req = Request.Builder().url(url)
                    .header("Authorization", "Bearer ${auth.accessToken()}")
                    .header("apikey", Config.supabaseAnonKey)
                    .build()
                Edge.client.newCall(req).execute().use { resp ->
                    val raw = resp.body.string()
                    if (resp.code !in 200..299) null
                    else Edge.json.decodeFromString(ListSerializer(PhotoRow.serializer()), raw)
                }
            }.getOrNull()
        } ?: return
        val prefs = prefs(context)
        val adopted = runCatching {
            Edge.json.decodeFromString(
                poolPhotosSerializer,
                prefs.getString(POOL_PHOTOS_KEY, null) ?: "{}")
        }.getOrDefault(emptyMap()).toMutableMap()
        for (row in got) {
            val b64 = row.photo
            if (!b64.isNullOrEmpty()) {
                val mark = "${b64.length}:${b64.takeLast(24)}"
                if (adopted[row.id] == mark) continue
                val bytes = runCatching { android.util.Base64.decode(b64, android.util.Base64.DEFAULT) }
                    .getOrNull() ?: continue
                val bmp = android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: continue
                CounterpartPhotoStore.save(context, row.id, bmp)
                adopted[row.id] = mark
            } else if (adopted[row.id] != null) {
                CounterpartPhotoStore.delete(context, row.id)
                adopted.remove(row.id)
            }
        }
        prefs.edit().putString(POOL_PHOTOS_KEY, Edge.json.encodeToString(
            poolPhotosSerializer,
            adopted)).apply()
    }

    private val poolPhotosSerializer = kotlinx.serialization.builtins.MapSerializer(String.serializer(), String.serializer())

    @Serializable
    private data class PhotoRow(val id: String, val photo: String? = null)

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
