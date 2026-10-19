package com.roro.futurevoice.audio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.media.MediaMetadata
import android.media.MediaPlayer
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.roro.futurevoice.MainActivity
import com.roro.futurevoice.R
import com.roro.futurevoice.core.Analytics
import com.roro.futurevoice.data.PlaylistLine
import com.roro.futurevoice.talk.WordTiming
import com.roro.futurevoice.talk.WordTimings

/**
 * Plays a playlist of situation lines, one after another, with the screen on
 * or off (iOS `PlaylistPlayer`, 2026-10-18).
 *
 * One app-wide instance, because the Talk tab's button shows what is playing
 * and the player sheet can be closed while the list keeps going. Its
 * [positionMs] drives the caption's karaoke.
 *
 * **It yields to everything.** Any other surface that starts audio
 * ([Mp3Player], [PcmStreamPlayer], the shadow players) pauses it, and a call
 * takes the lock screen from it ([com.roro.futurevoice.talk.CallForegroundService]).
 * It never resumes on its own afterwards — it keeps its place and waits for
 * a tap.
 *
 * iOS's lock-screen controls (`MPRemoteCommandCenter` / Now Playing) and its
 * Live Activity (the line being said, in the Dynamic Island) are, on Android,
 * ONE thing: a [MediaSession] with a media-style notification held by a
 * `mediaPlayback` foreground service ([PlaylistService]). The foreground
 * service is also what keeps the list going with the screen off — iOS plays
 * the pause between lines as silence for that; here the service holds the
 * process and the pause is a timer.
 *
 * Main thread only, apart from [yieldToOtherAudio], which hops there itself.
 */
object PlaylistPlayer {

    enum class RepeatMode(val raw: String) { OFF("off"), ALL("all"), ONE("one") }

    /** What happens between two lines. */
    enum class Gap(val raw: String) {
        /** Straight on. */
        NONE("none"),
        /** Two seconds to let the line land. */
        SHORT("short"),
        /** As long as the line itself — time to say it back out loud. */
        ECHO("echo");

        fun seconds(after: Double): Double = when (this) {
            NONE -> 0.0
            SHORT -> 2.0
            ECHO -> after.coerceIn(1.5, 20.0)
        }
    }

    var title by mutableStateOf(""); private set
    /** The list in its ORIGINAL order; [order] is the play order. */
    var lines by mutableStateOf<List<PlaylistLine>>(emptyList()); private set
    var order by mutableStateOf<List<Int>>(emptyList()); private set
    var position by mutableStateOf(0); private set
    var isPlaying by mutableStateOf(false); private set
    /** In the pause between two lines (the caption keeps the last line). */
    var isInGap by mutableStateOf(false); private set
    /** The playing line's word timings — measured when the take kept them,
     *  otherwise spread over the audio by character count, so the caption
     *  always moves with the voice (karaoke always works). */
    var timings by mutableStateOf<List<WordTiming>>(emptyList()); private set

    var repeatMode by mutableStateOf(RepeatMode.ALL); private set
    var shuffle by mutableStateOf(false); private set
    var gap by mutableStateOf(Gap.NONE); private set

    private const val PREFS = "futurevoice"
    private const val REPEAT_KEY = "futurevoice.playlist.repeat"
    private const val SHUFFLE_KEY = "futurevoice.playlist.shuffle"
    private const val GAP_KEY = "futurevoice.playlist.gap"

    private var app: Context? = null
    private val main = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    /** Bumped on every jump, so a line that finishes after the learner has
     *  already moved on can't advance the list a second time. */
    private var generation = 0
    private var gapTask: Runnable? = null
    private var skipStreak = 0

    /** Load the saved options once; every entry point calls it. */
    fun attach(context: Context) {
        if (app != null) return
        val c = context.applicationContext
        app = c
        val p = c.getSharedPreferences(PREFS, 0)
        repeatMode = RepeatMode.entries.firstOrNull { it.raw == p.getString(REPEAT_KEY, null) } ?: RepeatMode.ALL
        shuffle = p.getBoolean(SHUFFLE_KEY, false)
        gap = Gap.entries.firstOrNull { it.raw == p.getString(GAP_KEY, null) } ?: Gap.NONE
    }

    // ── State ──

    val hasQueue: Boolean get() = lines.isNotEmpty()

    val current: PlaylistLine?
        get() {
            val i = order.getOrNull(position) ?: return null
            return lines.getOrNull(i)
        }

    /** Playback head of the line, ms. */
    fun positionMs(): Int = player?.let { runCatching { it.currentPosition }.getOrDefault(0) } ?: 0
    fun durationMs(): Int = player?.let { runCatching { it.duration }.getOrDefault(0) } ?: 0

    /** How far through the list, 0…1 — the Talk button's ring. */
    fun progress(): Float {
        if (order.isEmpty()) return 0f
        val d = durationMs()
        val lineShare = if (d > 0) (positionMs().toFloat() / d).coerceAtMost(1f) else 0f
        return (position + (if (isInGap) 1f else lineShare)) / order.size
    }

    // ── Control ──

    /** Load a list and start it. [startAt] is an index into [newLines]. */
    fun play(context: Context, newLines: List<PlaylistLine>, title: String, startAt: Int = 0) {
        attach(context)
        val playable = newLines.filter { it.hasAudio }
        if (playable.isEmpty()) return
        val start = newLines.getOrNull(startAt)?.let { s -> playable.indexOfFirst { it.id == s.id }.takeIf { it >= 0 } } ?: 0
        this.title = title
        lines = playable
        order = makeOrder(playable, shuffle, start)
        position = 0
        Analytics.capture("playlist_started", mapOf("lines" to playable.size,
            "shuffle" to shuffle, "gap" to gap.raw))
        startCurrent()
    }

    fun togglePlayPause() { if (isPlaying) pause() else resume() }

    fun resume() {
        if (!hasQueue) return
        val d = durationMs()
        if (isInGap || player == null || d == 0 || positionMs() >= d - 50) {
            if (isInGap) position = minOf(position + 1, order.size - 1)
            startCurrent()
        } else {
            startCurrent(positionMs())
        }
    }

    fun pause() {
        if (!isPlaying && !isInGap) return
        generation += 1
        cancelGap()
        isInGap = false
        isPlaying = false
        runCatching { player?.pause() }
        publishNowPlaying()
    }

    fun next() {
        if (!hasQueue) return
        if (position + 1 < order.size) {
            position += 1
        } else {
            position = 0
            if (shuffle) order = makeOrder(lines, true, null)
        }
        startCurrent()
    }

    /** Back to the start of this line if it has been playing a while, else
     *  the line before — the music-player convention. */
    fun previous() {
        if (!hasQueue) return
        if (positionMs() > 2500 || position == 0) {
            startCurrent()
        } else {
            position -= 1
            startCurrent()
        }
    }

    /** Jump to a line of the list (index into [lines]). */
    fun jump(toLine: Int) {
        val p = order.indexOf(toLine)
        if (p < 0) return
        position = p
        startCurrent()
    }

    fun toggleShuffle(on: Boolean) {
        shuffle = on
        app?.getSharedPreferences(PREFS, 0)?.edit()?.putBoolean(SHUFFLE_KEY, on)?.apply()
        if (!hasQueue) return
        // Keep the line that is playing; reorder everything around it.
        val playing = order.getOrNull(position) ?: 0
        order = makeOrder(lines, on, playing)
        position = order.indexOf(playing).coerceAtLeast(0)
    }

    fun cycleRepeat() {
        val all = RepeatMode.entries
        repeatMode = all[(all.indexOf(repeatMode) + 1) % all.size]
        app?.getSharedPreferences(PREFS, 0)?.edit()?.putString(REPEAT_KEY, repeatMode.raw)?.apply()
    }

    fun chooseGap(value: Gap) {
        gap = value
        app?.getSharedPreferences(PREFS, 0)?.edit()?.putString(GAP_KEY, value.raw)?.apply()
    }

    /** Stop and forget the list. */
    fun close() {
        pause()
        lines = emptyList()
        order = emptyList()
        position = 0
        title = ""
        releasePlayer()
        abandonFocus()
        releaseLockScreen()
    }

    /** Another surface is about to make sound. Pause and keep the place.
     *  Safe from any thread. */
    fun yieldToOtherAudio() {
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post { yieldToOtherAudio() }; return }
        if (!isPlaying && !isInGap) return
        pause()
    }

    /** A call takes the lock screen; the call's own service calls this first. */
    fun yieldToCall() {
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post { yieldToCall() }; return }
        yieldToOtherAudio()
        releaseLockScreen()
    }

    // ── Playback ──

    private fun startCurrent(fromMs: Int = 0) {
        val c = app ?: return
        generation += 1
        val mine = generation
        cancelGap()
        isInGap = false
        val line = current ?: run { isPlaying = false; return }
        val file = line.audioFile(c)?.takeIf { it.exists() }
        if (file == null) {
            // Gone since the list was loaded (a re-clone outside the lineage,
            // a deleted talk) — skip, never synthesize.
            advance(0.0, mine, skipping = true)
            return
        }
        releasePlayer()
        try {
            val mp = MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build())
                setDataSource(file.absolutePath)
                prepare()
            }
            mp.setOnCompletionListener {
                if (generation != mine) return@setOnCompletionListener
                advance(mp.duration / 1000.0, mine, skipping = false)
            }
            mp.setOnErrorListener { _, _, _ ->
                if (generation == mine) advance(0.0, mine, skipping = true)
                true
            }
            player = mp
            if (fromMs > 0) mp.seekTo(fromMs)
            requestFocus()
            mp.start()
            val stored = line.storedTimings(c).orEmpty().filter { it.endMs > it.startMs }
            timings = stored.ifEmpty {
                WordTimings.estimate(line.text, mp.duration,
                    com.roro.futurevoice.data.LanguageScope.active(c))
            }
            isPlaying = true
            claimLockScreen()
            publishNowPlaying()
        } catch (e: Exception) {
            releasePlayer()
            advance(0.0, mine, skipping = true)
        }
    }

    private fun advance(duration: Double, mine: Int, skipping: Boolean) {
        if (generation != mine) return
        // A whole lap of lines with no audio must end, not spin.
        skipStreak = if (skipping) skipStreak + 1 else 0
        val wait = if (skipping) 0.0 else pauseAfter(duration)
        val move = move@{
            if (generation != mine) return@move
            isInGap = false
            if (!skipping && repeatMode == RepeatMode.ONE) {
                startCurrent()
            } else if (position + 1 < order.size) {
                position += 1
                startCurrent()
            } else if (repeatMode != RepeatMode.OFF && skipStreak < order.size) {
                position = 0
                if (shuffle) order = makeOrder(lines, true, null)
                startCurrent()
            } else {
                // The end of the list: stay on the last line, stopped.
                isPlaying = false
                publishNowPlaying()
            }
        }
        if (wait <= 0.0) { move(); return }
        isInGap = true
        val r = Runnable { gapTask = null; move() }
        gapTask = r
        main.postDelayed(r, (wait * 1000).toLong())
    }

    private fun cancelGap() {
        gapTask?.let { main.removeCallbacks(it) }
        gapTask = null
    }

    /** The gap after the line that just played. "Time to say it back" is for
     *  the learner's own lines — the other person's line in a scene is
     *  answered by the next one, not repeated. Between two scenes a short
     *  breath, so one conversation doesn't run straight into the next. */
    private fun pauseAfter(duration: Double): Double {
        val line = current ?: return 0.0
        var wait = if (gap == Gap.ECHO && !line.isFluentSelf) 0.0 else gap.seconds(duration)
        val nextPosition = position + 1
        if (nextPosition < order.size && repeatMode != RepeatMode.ONE &&
            lines[order[nextPosition]].bookId != line.bookId) {
            wait = maxOf(wait, 1.2)
        }
        return wait
    }

    private fun releasePlayer() {
        player?.let { p ->
            p.setOnCompletionListener(null)
            p.setOnErrorListener(null)
            runCatching { p.stop() }
            runCatching { p.release() }
        }
        player = null
    }

    /** Play order. Shuffling a list that holds whole conversations shuffles
     *  the SCENES and keeps every scene's lines in order — a dialogue out of
     *  order is noise. */
    private fun makeOrder(lines: List<PlaylistLine>, shuffled: Boolean, first: Int?): List<Int> {
        val count = lines.size
        if (!shuffled) {
            if (first == null || first <= 0 || first >= count) return (0 until count).toList()
            return (first until count).toList() + (0 until first).toList()
        }
        if (lines.none { !it.isFluentSelf }) {
            val o = (0 until count).shuffled().toMutableList()
            if (first != null) { val i = o.indexOf(first); if (i >= 0) java.util.Collections.swap(o, 0, i) }
            return o
        }
        val groups = mutableListOf<MutableList<Int>>()
        for (i in 0 until count) {
            val last = groups.lastOrNull()?.lastOrNull()
            if (last != null && lines[last].bookId == lines[i].bookId) groups.last().add(i)
            else groups.add(mutableListOf(i))
        }
        groups.shuffle()
        if (first != null) {
            val g = groups.indexOfFirst { first in it }
            if (g >= 0) java.util.Collections.swap(groups, 0, g)
        }
        return groups.flatten()
    }

    // ── Audio focus (iOS: the audio session's interruption → pause) ──

    private var focusRequest: AudioFocusRequest? = null

    private fun requestFocus() {
        val c = app ?: return
        if (focusRequest != null) return
        val am = c.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener({ change ->
                // Another app took the speaker (a phone call, music): pause
                // and keep the place, never resume by ourselves.
                if (change == AudioManager.AUDIOFOCUS_LOSS ||
                    change == AudioManager.AUDIOFOCUS_LOSS_TRANSIENT) {
                    pause()
                    if (change == AudioManager.AUDIOFOCUS_LOSS) abandonFocus()
                }
            }, main)
            .build()
        focusRequest = req
        am.requestAudioFocus(req)
    }

    private fun abandonFocus() {
        val c = app ?: return
        val req = focusRequest ?: return
        focusRequest = null
        (c.getSystemService(Context.AUDIO_SERVICE) as AudioManager).abandonAudioFocusRequest(req)
    }

    // ── Lock screen + notification (iOS Now Playing + Live Activity) ──

    private var session: MediaSession? = null
    private val ownsLockScreen: Boolean get() = session != null

    private fun claimLockScreen() {
        val c = app ?: return
        if (session == null) {
            session = MediaSession(c, "situations").apply {
                setCallback(object : MediaSession.Callback() {
                    override fun onPlay() { resume() }
                    override fun onPause() { pause() }
                    override fun onSkipToNext() { next() }
                    override fun onSkipToPrevious() { previous() }
                }, main)
                setSessionActivity(openAppIntent(c))
                isActive = true
            }
        }
        PlaylistService.start(c)
    }

    private fun releaseLockScreen() {
        val c = app ?: return
        if (!ownsLockScreen) return
        session?.let { s ->
            s.isActive = false
            s.release()
        }
        session = null
        PlaylistService.stop(c)
    }

    private fun publishNowPlaying() {
        val c = app ?: return
        val s = session ?: return
        val line = current ?: return
        s.setMetadata(MediaMetadata.Builder()
            .putString(MediaMetadata.METADATA_KEY_TITLE, line.text)
            .putString(MediaMetadata.METADATA_KEY_ARTIST, line.bookTitle)
            .putString(MediaMetadata.METADATA_KEY_ALBUM, title)
            .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs().toLong())
            .build())
        s.setPlaybackState(PlaybackState.Builder()
            .setActions(PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
                PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SKIP_TO_NEXT or
                PlaybackState.ACTION_SKIP_TO_PREVIOUS)
            .setState(if (isPlaying || isInGap) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED,
                positionMs().toLong(), if (isPlaying) 1f else 0f)
            .build())
        (c.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .notify(PlaylistService.NOTIFICATION_ID, notification(c))
    }

    private fun openAppIntent(c: Context): PendingIntent = PendingIntent.getActivity(
        c, 0, Intent(c, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

    /**
     * The line being said and who says it, the place in the list, and
     * previous · play/pause · next — iOS's Live Activity (speaker, line,
     * scene, position, play/pause · next) and its lock-screen transport in
     * one media notification.
     */
    internal fun notification(c: Context): Notification {
        PlaylistService.ensureChannel(c)
        val words = com.roro.futurevoice.core.UILanguage.localized(c)
        fun action(a: String, req: Int): PendingIntent = PendingIntent.getService(
            c, req, Intent(c, PlaylistService::class.java).setAction(a),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val line = current
        val playing = isPlaying || isInGap
        val b = Notification.Builder(c, PlaylistService.CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(line?.speaker ?: title)
            .setContentText(line?.text.orEmpty())
            .setSubText(if (line != null) "${position + 1}/${order.size} · ${line.bookTitle}" else null)
            .setContentIntent(openAppIntent(c))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setCategory(Notification.CATEGORY_TRANSPORT)
            .addAction(Notification.Action.Builder(null, words.getString(R.string.previous),
                action(PlaylistService.ACTION_PREVIOUS, 1)).build())
            .addAction(Notification.Action.Builder(null,
                words.getString(if (playing) R.string.pause else R.string.play),
                action(PlaylistService.ACTION_TOGGLE, 2)).build())
            .addAction(Notification.Action.Builder(null, words.getString(R.string.next),
                action(PlaylistService.ACTION_NEXT, 3)).build())
        val style = Notification.MediaStyle().setShowActionsInCompactView(0, 1, 2)
        session?.let { style.setMediaSession(it.sessionToken) }
        b.style = style
        return b.build()
    }

    /** iOS `PlaylistPlayer.unreportedPlaybackSources` keeps "playlist" out of
     *  `audio_played`; this player never goes through [Mp3Player], so it
     *  logs nothing per line either. */
    internal fun onServiceCommand(action: String?) {
        when (action) {
            PlaylistService.ACTION_TOGGLE -> togglePlayPause()
            PlaylistService.ACTION_NEXT -> next()
            PlaylistService.ACTION_PREVIOUS -> previous()
        }
    }
}

/**
 * Holds the situation player in the foreground while a list is loaded, so it
 * keeps playing with the screen off and its controls stay on the lock screen
 * (the Android half of iOS's background audio + Now Playing + Live
 * Activity). The notification and the session belong to [PlaylistPlayer];
 * this only keeps them alive and routes the notification's buttons.
 */
class PlaylistService : Service() {

    companion object {
        const val CHANNEL_ID = "situation_player"
        const val NOTIFICATION_ID = 4803
        const val ACTION_TOGGLE = "com.roro.futurevoice.playlist.TOGGLE"
        const val ACTION_NEXT = "com.roro.futurevoice.playlist.NEXT"
        const val ACTION_PREVIOUS = "com.roro.futurevoice.playlist.PREVIOUS"

        private var running = false

        fun start(context: Context) {
            if (running) return
            running = true
            runCatching { context.startForegroundService(Intent(context, PlaylistService::class.java)) }
                .onFailure { running = false }
        }

        fun stop(context: Context) {
            running = false
            runCatching { context.stopService(Intent(context, PlaylistService::class.java)) }
        }

        fun ensureChannel(context: Context) {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) != null) return
            // DEFAULT, sound and vibration off: a LOW channel is filed as
            // "silent" and hidden from the lock screen on some phones (the
            // call notification learnt this, CallForegroundService).
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, com.roro.futurevoice.core.UILanguage.localized(context).getString(R.string.player), NotificationManager.IMPORTANCE_DEFAULT).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            })
        }
    }

    // The notification's words must be the app language, not the device's.
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(com.roro.futurevoice.core.UILanguage.localized(newBase))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val n = PlaylistPlayer.notification(this)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
        intent?.action?.let { PlaylistPlayer.onServiceCommand(it) }
        // Not sticky: a list the system had to kill is not one to resurrect.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }
}
