package com.roro.futurevoice.data

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import io.github.jan.supabase.postgrest.from

/**
 * Whether this install is behind, and how badly — `AppUpdateService.swift`.
 *
 * The comparison is on the BUILD NUMBER (`versionCode`), never the version
 * name. The name is a label the team moves for its own reasons — iOS went
 * 1.1.0 → 1.0 on 2026-08-21 when the first public release was renamed — while
 * the build number is the one value Play forces upward on every upload.
 * Comparing labels would have told every 1.1.0 tester they were ahead of the
 * build that actually replaced theirs.
 *
 * TWO AUDIENCES, and the whole point of the feature is not to confuse them.
 * A Play install can only ever get what review has ACTUALLY released; a
 * sideloaded or internal-test install gets whatever was uploaded last. Telling
 * a store user about a build the store hasn't got yet is a button that opens a
 * page still showing the version they already have — which is what happened on
 * iOS on 2026-09-11, and is why the server carries two numbers.
 *
 * Silent on every failure: an update notice is the least important thing the
 * app does, and a network blip must never produce a wrong claim about the
 * build someone is running.
 */
object AppUpdateService {

    /** The app's own Play page — the only destination a store install has. */
    const val PLAY_URL = "https://play.google.com/store/apps/details?id=com.roro.futurevoice"

    data class AppUpdate(
        val latestBuild: Int,
        val latestVersion: String?,
        val notes: String?,
        /** The server says this build can no longer be trusted to describe it.
         *  The sheet then has no way out — see `UpdateAvailableSheet`. */
        val required: Boolean,
        /** Whether this install came from Play. Decides both which number it
         *  was compared against and where the button goes. */
        val fromPlay: Boolean,
        val url: String,
    )

    /** Set when there is something to say. Null the rest of the time, which is
     *  almost always — this must never be a screen people learn to dismiss. */
    private val _pending = MutableStateFlow<AppUpdate?>(null)
    val pending: StateFlow<AppUpdate?> = _pending

    /** The last build the optional sheet was already shown for. An optional
     *  update is worth saying ONCE; saying it every launch is how a notice
     *  becomes furniture people tap past without reading. */
    private const val PREFS = "futurevoice"
    private const val SEEN_KEY = "futurevoice.updateSeenBuild"

    @Volatile private var checked = false

    @Serializable
    private data class ReleaseRow(
        @SerialName("latest_build") val latestBuild: Int = 0,
        /** The DEFAULT speed rung, tunable without a build (NULL = the app's own). */
        @SerialName("default_speech_speed") val defaultSpeechSpeed: Double? = null,
        /** Play's own beta channels, and a sideloaded APK. Null until an
         *  Android build has ever been uploaded. */
        @SerialName("latest_beta_build") val latestBetaBuild: Int? = null,
        @SerialName("min_build") val minBuild: Int = 0,
        @SerialName("latest_version") val latestVersion: String? = null,
        /** Where a BETA install goes to get the new build. Server-side so the
         *  internal-test opt-in link can be set without shipping a build. */
        @SerialName("beta_url") val betaUrl: String? = null,
        @SerialName("notes_ko") val notesKo: String? = null,
        @SerialName("notes_en") val notesEn: String? = null,
    )

    /** Asked once per launch, from the foreground. */
    suspend fun check(context: Context) = withContext(Dispatchers.IO) {
        if (checked) return@withContext
        checked = true

        val build = currentBuild(context)
        // A build of 0 means the package couldn't be read at all. That is
        // "can't tell", never "hopelessly old" — locking someone out on a
        // failed lookup is the one outcome worse than a missed notice.
        if (build <= 0) return@withContext

        val row = runCatching {
            Supa.client.from("app_release")
                .select {
                    filter { eq("platform", "android") }
                    limit(1)
                }
                .decodeSingleOrNull<ReleaseRow>()
        }.getOrNull() ?: return@withContext

        // Before any of this build's own guards: they stop for reasons about
        // THIS build, none of which is a reason to ignore a retuned speed.
        com.roro.futurevoice.data.SpeechSpeed.storeRemoteDefault(context, row.defaultSpeechSpeed)
        val fromPlay = installedFromPlay(context)
        // The build this install can actually GO AND GET.
        val latest = if (fromPlay) row.latestBuild
                     else maxOf(row.latestBetaBuild ?: 0, row.latestBuild)

        val required = build < row.minBuild
        if (!required && build >= latest) return@withContext

        val prefs = context.getSharedPreferences(PREFS, 0)
        if (!required && prefs.getInt(SEEN_KEY, 0) >= latest) return@withContext

        // Release notes are MATERIAL for the reader, not for the machine: the
        // learner reads them in the language the app speaks to them in.
        val notes = if (com.roro.futurevoice.core.UILanguage.current(context)?.startsWith("ko") == true)
            row.notesKo else row.notesEn

        _pending.value = AppUpdate(
            latestBuild = latest,
            latestVersion = row.latestVersion,
            notes = notes?.trim()?.takeIf { it.isNotEmpty() },
            required = required,
            fromPlay = fromPlay,
            url = if (fromPlay) PLAY_URL else (row.betaUrl?.takeIf { it.isNotBlank() } ?: PLAY_URL),
        )
    }

    /** Remember an optional notice as said, and put the sheet away. A REQUIRED
     *  one is never recorded and never dismissed — there is nothing to
     *  remember, because it has to come back. */
    fun dismiss(context: Context) {
        val update = _pending.value ?: return
        if (update.required) return
        context.getSharedPreferences(PREFS, 0).edit()
            .putInt(SEEN_KEY, update.latestBuild).apply()
        _pending.value = null
    }

    /** This install's build number, read from the package rather than from
     *  `BuildConfig`, so a failure is a real 0 and not a compiled-in lie. */
    fun currentBuild(context: Context): Int = runCatching {
        val info = context.packageManager.getPackageInfo(context.packageName, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode.toInt()
        else @Suppress("DEPRECATION") info.versionCode
    }.getOrDefault(0)

    fun currentVersion(context: Context): String = runCatching {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName
    }.getOrNull() ?: "—"

    /**
     * Whether THIS install came from the Play store.
     *
     * iOS reads a sandbox receipt; Android reads the installer package.
     * `com.android.vending` is Play — and Play is the only installer that can
     * hand this install a newer build on its own. Anything else (adb, a
     * sideloaded APK, a file manager, a null installer on an old OS) is a
     * build we handed someone directly, so it is the beta audience.
     */
    private fun installedFromPlay(context: Context): Boolean {
        val pm: PackageManager = context.packageManager
        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                pm.getInstallSourceInfo(context.packageName).installingPackageName
            else
                @Suppress("DEPRECATION") pm.getInstallerPackageName(context.packageName)
        }.getOrNull()
        return installer == "com.android.vending"
    }
}
