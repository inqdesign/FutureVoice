package com.roro.futurevoice.net

import com.roro.futurevoice.core.Config
import com.roro.futurevoice.data.AuthRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody

/**
 * The invite system. Every account has a shareable code; redeeming someone
 * else's grants talk time to BOTH sides, and the inviter is rewarded for
 * their first [REWARDED_INVITE_CAP] friends.
 *
 * **All grant math is server-side** in `redeem_referral`. Nothing here adds
 * up minutes — the client only shows what came back, so a client that is a
 * version behind can't hand out time the server didn't.
 */
class ReferralClient(private val auth: AuthRepository) {

    companion object {
        /** Seconds granted to BOTH sides by `redeem_referral` — mirrors the
         *  server (1800 s since `20260818100000_referral_thirty_minutes`).
         *  Change one without the other and every number on the invite page
         *  lies. */
        const val BONUS_SECONDS = 1800
        val bonusMinutes: Int get() = BONUS_SECONDS / 60

        /** The inviter is rewarded for their first 10 redemptions; past that
         *  a friend still gets theirs. */
        const val REWARDED_INVITE_CAP = 10
    }

    /**
     * My code, how many friends redeemed it, and the code I joined with.
     *
     * [redeemedCode] is what decides whether offering the entry box is a real
     * offer or a dead one: a code counts once per account
     * (`referral_redemptions.invitee_id` is the primary key).
     */
    data class Status(
        val code: String? = null,
        val invitesUsed: Int = 0,
        val redeemedCode: String? = null,
    )

    @Serializable private data class CodeRow(val code: String = "")
    @Serializable private data class RedemptionRow(val code: String = "")

    /** Best-effort: an invite page that can't load is still a page, and none
     *  of this gates anything the learner is trying to do. */
    suspend fun status(): Status = withContext(Dispatchers.IO) {
        val uid = auth.userId ?: return@withContext Status()
        // One token for all three reads — refreshing it per request would be
        // three round trips to answer one screen.
        val token = auth.accessToken()
        val mine = get(token, "referral_codes?select=code&user_id=eq.$uid&limit=1", CodeRow.serializer())
        val joined = get(token, "referral_redemptions?select=code&invitee_id=eq.$uid&limit=1",
            RedemptionRow.serializer())
        val used = get(token, "referral_redemptions?select=code&inviter_id=eq.$uid",
            RedemptionRow.serializer())
        Status(
            code = mine.firstOrNull()?.code,
            invitesUsed = used.size,
            redeemedCode = joined.firstOrNull()?.code,
        )
    }

    private fun <T> get(
        token: String, path: String, ser: kotlinx.serialization.KSerializer<T>,
    ): List<T> =
        runCatching {
            val req = Request.Builder()
                .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/$path")
                .header("Authorization", "Bearer $token")
                .header("apikey", Config.supabaseAnonKey)
                .build()
            Edge.client.newCall(req).execute().use { resp ->
                val raw = resp.body.string()
                if (resp.code !in 200..299) emptyList()
                else Edge.json.decodeFromString(ListSerializer(ser), raw)
            }
        }.getOrDefault(emptyList())

    /** Why a redemption was refused. Each maps to one server-side guard. */
    enum class RedeemError { INVALID, ALREADY_REDEEMED, SELF_REFERRAL, ALREADY_SUBSCRIBED, UNKNOWN }

    class RedeemFailure(val reason: RedeemError) : Exception(reason.name)

    @Serializable
    private data class RedeemResult(
        val balance: Int = 0,
        val invitee_bonus: Int = 0,
        val inviter_rewarded: Boolean = false,
        val comp_plan: String? = null,
    )

    /**
     * What a code turned out to be. Nearly always an invite bonus — but the
     * same box also takes a COMP code, which hands over a subscription and
     * grants no minutes at all. The confirmation therefore cannot be written
     * from [bonusMinutes] alone.
     */
    data class Redeemed(val balance: Int, val compPlanId: String?) {
        val isComp: Boolean get() = compPlanId != null
    }

    suspend fun redeem(code: String): Redeemed = withContext(Dispatchers.IO) {
        val clean = code.trim().uppercase()
        val req = Request.Builder()
            .url("${Config.supabaseUrl.trimEnd('/')}/rest/v1/rpc/redeem_referral")
            .header("Authorization", "Bearer ${auth.accessToken()}")
            .header("apikey", Config.supabaseAnonKey)
            .post(buildJsonObject { put("p_code", clean) }.toString()
                .toRequestBody("application/json".toMediaType()))
            .build()
        Edge.client.newCall(req).execute().use { resp ->
            val raw = resp.body.string()
            if (resp.code !in 200..299) {
                // The guard that fired is named in the error body; anything
                // else is a real failure and says so.
                throw RedeemFailure(when {
                    raw.contains("ALREADY_REDEEMED") -> RedeemError.ALREADY_REDEEMED
                    raw.contains("SELF_REFERRAL") -> RedeemError.SELF_REFERRAL
                    raw.contains("ALREADY_SUBSCRIBED") -> RedeemError.ALREADY_SUBSCRIBED
                    raw.contains("INVALID_CODE") -> RedeemError.INVALID
                    else -> RedeemError.UNKNOWN
                })
            }
            val r = Edge.json.decodeFromString(RedeemResult.serializer(), raw)
            Redeemed(r.balance, r.comp_plan)
        }
    }
}
