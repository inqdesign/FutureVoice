package com.roro.futurevoice.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.automirrored.outlined.VolumeUp
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.FluentSelfVoice
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.PronunciationProfile
import com.roro.futurevoice.talk.PronunciationCourse
import com.roro.futurevoice.talk.PronunciationResult
import com.roro.futurevoice.ui.brand.IosGlassTextButton
import com.roro.futurevoice.ui.brand.iosFill
import kotlinx.coroutines.launch

/**
 * What the pronunciation assessment found, written for the learner — the
 * page behind the red/orange marks (iOS `PronunciationDetailSheet`,
 * 53ec4f49 + 4998fe6e). ONE number, the sounds to work on with the words of
 * this take that carry them (and a button to hear each word in the fluent
 * self's voice), the line with its marked words — a tap opens that word's
 * sounds — the month in one line, and every other number Azure returned
 * folded under Details. Opened from the shadow result's Pronunciation line,
 * the speech result's Pronunciation row, the pronunciation call's verdict
 * pill, and the scorecard's axis (the standing alone, [results] empty).
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun PronunciationDetailSheet(
    /** The take's assessment — a speech take is several pieces, in order.
     *  Empty = the standing alone. */
    results: List<PronunciationResult>,
    language: String? = null,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val lang = language ?: remember { LanguageScope.active(context) }
    val profile = remember(lang) { PronunciationProfile.current(context, lang) }
    val namesSounds = results.flatMap { it.namedPhonemes }.isNotEmpty()

    // The fluent self's voice for the word buttons (iOS `speakingVoiceId`).
    val clone = rememberCloneVoiceId()
    val voiceId = FluentSelfVoice.speaking(context, clone)
    val player = remember { com.roro.futurevoice.audio.Mp3Player(context.cacheDir) }
    DisposableEffect(Unit) { onDispose { player.stop() } }
    val scope = rememberCoroutineScope()
    var speakingWord by remember { mutableStateOf<String?>(null) }
    var openWord by rememberSaveable { mutableStateOf<Int?>(null) }
    var detailsOpen by rememberSaveable { mutableStateOf(false) }

    fun speak(word: String) {
        val id = voiceId ?: return
        speakingWord = word
        scope.launch {
            val audio = runCatching {
                com.roro.futurevoice.data.cachedSynthesis(
                    context, voiceId = id, text = word,
                    idempotencyKey = com.roro.futurevoice.core.InstallSalt.ttsKey(word, id, timestamps = false),
                    purpose = "library")
            }.getOrNull()
            speakingWord = null
            if (audio != null) runCatching { player.play(audio) }
        }
    }

    com.roro.futurevoice.ui.speech.SpeechSheet(onDismiss) {
        SheetHeader(stringResource(R.string.pronunciation),
            trailing = { IosGlassTextButton(stringResource(R.string.done), onClick = onDismiss, bold = true) })

        // MARK: The number
        val headlineScore = if (results.isEmpty()) profile.meanAccuracy else weighted(results) { it.soundScore }
        FormSection(null) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp)) {
                headlineScore?.let { s ->
                    Text("$s", fontSize = 44.sp, fontWeight = FontWeight.Bold,
                        color = com.roro.futurevoice.ui.speech.scoreColor(s), modifier = Modifier.alignByBaseline())
                }
                Text(stringResource(if (results.isEmpty())
                        R.string.how_closely_your_sounds_matched_a_native_speaker_s_over_the_9ad53d
                    else R.string.how_closely_your_sounds_matched_a_native_speaker_s),
                    style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.alignByBaseline())
            }
        }

        if (results.isNotEmpty()) {
            // MARK: Sounds to work on (this take)
            val items = remember(results, lang) { workItems(results, namesSounds, lang) }
            FormSection(
                stringResource(if (namesSounds) R.string.sounds_to_work_on_0bf630 else R.string.words_to_work_on),
                footer = if (items.isEmpty()) null
                else if (namesSounds) stringResource(R.string.tap_a_word_to_hear_it_in_your_fluent_voice_a_sound_is_listed_aa96ef,
                    PronunciationProfile.WEAK_BAR)
                else stringResource(R.string.tap_a_word_to_hear_it_in_your_fluent_voice),
            ) {
                if (items.isEmpty()) {
                    CheckLine(stringResource(R.string.nothing_stood_out_in_this_take))
                } else {
                    items.forEachIndexed { i, item ->
                        if (i > 0) FormDivider()
                        WorkRow(item, speakingWord, enabled = voiceId != null, onSpeak = ::speak)
                    }
                }
            }

            // MARK: The line
            val lineWords = results.flatMap { it.referenceWords }
            FormSection(stringResource(R.string.what_you_read),
                footer = stringResource(R.string.red_clearly_off_orange_a_bit_off_grey_not_heard_tap_a_word_t_9a893d)) {
                FlowRow(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 14.dp),
                    horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    lineWords.forEachIndexed { i, w ->
                        val mark = markColor(w)
                        Text(w.word, style = MaterialTheme.typography.bodyLarge,
                            color = if (w.isOmission) MaterialTheme.colorScheme.onSurfaceVariant
                            else MaterialTheme.colorScheme.onSurface,
                            modifier = Modifier.clip(RoundedCornerShape(5.dp))
                                .background(if (openWord == i) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                                    else Color.Transparent)
                                .clickable { openWord = if (openWord == i) null else i }
                                .padding(horizontal = 3.dp, vertical = 2.dp)
                                .then(if (mark != null) Modifier.dotUnderline(mark) else Modifier))
                    }
                }
                val i = openWord
                if (i != null && i in lineWords.indices) {
                    FormDivider()
                    WordDetail(lineWords[i], showSpeak = voiceId != null, onSpeak = ::speak)
                }
            }
        } else {
            // MARK: The standing alone (scorecard)
            if (profile.takes > 0) {
                FormSection(stringResource(R.string.sounds_to_work_on_0bf630)) {
                    if (profile.weakSounds.isEmpty() && profile.weakWords.isEmpty()) {
                        CheckLine(stringResource(R.string.no_sound_stays_low_across_your_takes))
                    }
                    profile.weakSounds.forEachIndexed { i, s ->
                        if (i > 0) FormDivider()
                        StandingRow(soundName(s.phoneme, lang), "/${s.phoneme}/", s.mean)
                    }
                    profile.weakWords.forEachIndexed { i, w ->
                        if (i > 0 || profile.weakSounds.isNotEmpty()) FormDivider()
                        StandingRow(w.word, null, w.mean)
                    }
                }
            } else {
                FormSection(null) {
                    Text(stringResource(R.string.shadow_a_line_or_read_a_speech_and_your_sounds_are_measured_22863e),
                        style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 16.dp, vertical = 11.dp))
                }
            }
        }

        // MARK: The month
        val mean = profile.meanAccuracy
        if (profile.takes > 0 && mean != null) {
            FormSection(stringResource(R.string.last_30_days)) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                    verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.lld_takes_average_lld, profile.takes, mean),
                        style = MaterialTheme.typography.bodyLarge)
                    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
                    val sub = MaterialTheme.typography.bodyMedium
                    when {
                        profile.weakSounds.isNotEmpty() -> Text(stringResource(R.string.still_low) +
                            profile.weakSounds.take(4).joinToString(" · ") { soundName(it.phoneme, lang) },
                            style = sub, color = secondary)
                        profile.weakWords.isNotEmpty() -> Text(stringResource(R.string.low_in_several_takes) +
                            profile.weakWords.take(4).joinToString(" · ") { it.word },
                            style = sub, color = secondary)
                        profile.takes >= 3 -> Text(stringResource(R.string.nothing_stays_low_across_takes),
                            style = sub, color = secondary)
                    }
                }
            }
        }

        // MARK: Details (every number Azure returned)
        FormSection(null, footer = stringResource(R.string.scores_come_from_azure_s_pronunciation_assessment_against_a_535c64)) {
            Row(Modifier.fillMaxWidth().clickable { detailsOpen = !detailsOpen }
                .padding(horizontal = 16.dp, vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.details), style = MaterialTheme.typography.bodyLarge,
                    modifier = Modifier.weight(1f))
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, Modifier.size(22.dp)
                    .rotate(if (detailsOpen) 90f else 0f), tint = MaterialTheme.colorScheme.primary)
            }
            if (detailsOpen) {
                if (results.isNotEmpty()) {
                    weighted(results) { it.fluency }?.let { FormDivider(); NumberRow(stringResource(R.string.flow), it) }
                    weighted(results) { it.completeness }?.let { FormDivider(); NumberRow(stringResource(R.string.completeness), it) }
                    weighted(results) { it.prosody }?.let { FormDivider(); NumberRow(stringResource(R.string.intonation), it) }
                    weighted(results) { it.score }?.let { FormDivider(); NumberRow(stringResource(R.string.overall), it) }
                    results.first().locale.takeIf { it.isNotEmpty() }?.let { locale ->
                        FormDivider()
                        val chrome = LocalConfiguration.current.locales[0]
                        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp)) {
                            Text(stringResource(R.string.judged_against), style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.weight(1f))
                            Text(localeName(locale, chrome), style = MaterialTheme.typography.bodyLarge,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    val heard = results.map { it.recognized }.filter { it.isNotEmpty() }
                    if (heard.isNotEmpty()) {
                        FormDivider()
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
                            verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(stringResource(R.string.what_the_model_heard), style = MaterialTheme.typography.bodyMedium)
                            Text(heard.joinToString(" "), style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                    takeSounds(results).forEach { s ->
                        FormDivider()
                        SoundMeanRow(soundName(s.phoneme, lang), s.phoneme, s.count, s.mean)
                    }
                } else {
                    profile.sounds.forEach { s ->
                        FormDivider()
                        SoundMeanRow(soundName(s.phoneme, lang), s.phoneme, s.count, s.mean)
                    }
                }
            }
        }
    }
}

// MARK: - Rows

@Composable
private fun CheckLine(text: String) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Icon(Icons.Outlined.CheckCircle, null, Modifier.size(20.dp), tint = pronGreen())
        Text(text, style = MaterialTheme.typography.bodyLarge, color = pronGreen())
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WorkRow(item: WorkItem, speakingWord: String?, enabled: Boolean, onSpeak: (String) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(item.title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.alignByBaseline())
            item.detail?.let {
                Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.alignByBaseline())
            }
            Spacer(Modifier.weight(1f))
            Text(verdict(item.mean), style = MaterialTheme.typography.bodyMedium, color = verdictColor(item.mean),
                modifier = Modifier.alignByBaseline())
        }
        if (item.words.isNotEmpty()) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                item.words.forEach { word ->
                    val tint = if (enabled) MaterialTheme.colorScheme.primary
                        else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f)
                    Row(Modifier.height(30.dp).clip(RoundedCornerShape(15.dp)).background(iosFill())
                        .clickable(enabled = enabled) { onSpeak(word) }.padding(horizontal = 10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(if (speakingWord == word) Icons.AutoMirrored.Filled.VolumeUp
                            else Icons.AutoMirrored.Outlined.VolumeUp, null, Modifier.size(13.dp), tint = tint)
                        Spacer(Modifier.width(4.dp))
                        Text(word, style = MaterialTheme.typography.bodyMedium, color = tint)
                    }
                }
            }
        }
    }
}

@Composable
private fun WordDetail(w: PronunciationResult.Word, showSpeak: Boolean, onSpeak: (String) -> Unit) {
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(w.word, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            val a = w.accuracy
            if (w.isOmission) {
                Text(stringResource(R.string.not_heard), style = MaterialTheme.typography.bodyMedium, color = secondary)
            } else if (a != null) {
                Text(verdict(a), style = MaterialTheme.typography.bodyMedium, color = verdictColor(a))
                Text("$a", style = MaterialTheme.typography.bodyMedium, color = secondary)
            }
            if (showSpeak && !w.isOmission) {
                Icon(Icons.AutoMirrored.Outlined.VolumeUp, null, Modifier.size(22.dp).clickable { onSpeak(w.word) },
                    tint = MaterialTheme.colorScheme.primary)
            }
        }
        val named = w.phonemes.filter { it.phoneme.isNotEmpty() && it.accuracy != null }
        if (named.isNotEmpty()) {
            Text(phonemeLine(named, secondary),
                style = MaterialTheme.typography.bodySmall)
        } else {
            breakLabel(w)?.let {
                Text(stringResource(it), style = MaterialTheme.typography.bodySmall, color = secondary)
            }
        }
    }
}

/** "θ 32 (sounded like s) · ɪ 95 · ŋ 88", each sound in its own colour. */
@Composable
private fun phonemeLine(phonemes: List<PronunciationResult.Phoneme>, secondary: Color): AnnotatedString {
    val context = LocalContext.current
    val red = pronRed(); val orange = pronOrange()
    val tertiary = secondary.copy(alpha = 0.6f)
    return buildAnnotatedString {
        phonemes.forEachIndexed { i, p ->
            if (i > 0) withStyle(SpanStyle(color = tertiary)) { append(" · ") }
            val score = p.accuracy ?: 100
            // The word bars, applied to one sound: red under 35, orange under 45.
            val color = if (score < 35) red else if (score < 45) orange else secondary
            withStyle(SpanStyle(color = color)) { append("${p.phoneme} $score") }
            val heard = p.heard?.firstOrNull()
            if (heard != null && heard.phoneme != p.phoneme && score < 60) {
                append(" ")
                withStyle(SpanStyle(color = secondary)) { append(context.getString(R.string.sounded_like_14b851, heard.phoneme)) }
            }
        }
    }
}

private fun breakLabel(w: PronunciationResult.Word): Int? = when (w.error) {
    "UnexpectedBreak" -> R.string.a_stop_before_it
    "MissingBreak" -> R.string.no_pause_before_it
    "Monotone" -> R.string.flat
    else -> null
}

@Composable
private fun StandingRow(title: String, detail: String?, mean: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        detail?.let { Text(it, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        Spacer(Modifier.weight(1f))
        Text(verdict(mean), style = MaterialTheme.typography.bodyMedium, color = verdictColor(mean))
    }
}

@Composable
private fun NumberRow(title: String, value: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        Text("$value", style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Default),
            color = com.roro.futurevoice.ui.speech.scoreColor(value))
    }
}

@Composable
private fun SoundMeanRow(name: String, phoneme: String, count: Int, mean: Int) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("$name /$phoneme/", style = MaterialTheme.typography.bodyLarge)
        Text("×$count", style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
        Spacer(Modifier.weight(1f))
        Text("$mean", style = MaterialTheme.typography.bodyLarge, color = verdictColor(mean))
    }
}

// MARK: - The numbers

/** The pieces' scores weighted by the words each judged — the same
 *  weighting `PronunciationEntry` records. */
private fun weighted(results: List<PronunciationResult>, value: (PronunciationResult) -> Int?): Int? {
    var sum = 0; var total = 0
    for (r in results) {
        val v = value(r) ?: continue
        val w = maxOf(1, r.judgedWords.size)
        sum += v * w; total += w
    }
    return if (total == 0) null else sum / total
}

private data class WorkItem(
    /** "th /θ/" for a sound; the word itself where no sound is named. */
    val title: String,
    val detail: String?,
    val mean: Int,
    /** Words of this take that carry it, worst first. */
    val words: List<String>,
)

/** Sounds under the weak bar in this take (English), each with the words it
 *  was low in; elsewhere the marked words themselves. */
private fun workItems(results: List<PronunciationResult>, namesSounds: Boolean, language: String): List<WorkItem> {
    if (namesSounds) {
        val scores = LinkedHashMap<String, MutableList<Int>>()
        val carriers = LinkedHashMap<String, MutableList<Pair<String, Int>>>()
        for (w in results.flatMap { it.judgedWords }) {
            for (p in w.phonemes) {
                if (p.phoneme.isEmpty()) continue
                val a = p.accuracy ?: continue
                scores.getOrPut(p.phoneme) { mutableListOf() }.add(a)
                carriers.getOrPut(p.phoneme) { mutableListOf() }.add(w.word to a)
            }
        }
        return scores.mapNotNull { (p, v) ->
            val mean = v.sum() / v.size
            if (mean >= PronunciationProfile.WEAK_BAR) return@mapNotNull null
            val seen = HashSet<String>()
            val words = carriers[p].orEmpty().sortedBy { it.second }
                .mapNotNull { if (seen.add(it.first.lowercase())) it.first else null }
            WorkItem(soundName(p, language), "/$p/", mean, words.take(3))
        }.sortedWith(compareBy<WorkItem>({ it.mean }, { it.title }))
    }
    val seen = HashSet<String>()
    return results.flatMap { it.weakWords }.mapNotNull { w ->
        val a = w.accuracy
        if (!seen.add(w.word.lowercase()) || a == null) null else WorkItem(w.word, null, a, listOf(w.word))
    }
}

private data class SoundMean(val phoneme: String, val mean: Int, val count: Int)

private fun takeSounds(results: List<PronunciationResult>): List<SoundMean> {
    val by = LinkedHashMap<String, MutableList<Int>>()
    for (p in results.flatMap { it.namedPhonemes }) by.getOrPut(p.phoneme) { mutableListOf() }.add(p.accuracy ?: 100)
    return by.map { (p, v) -> SoundMean(p, v.sum() / v.size, v.size) }
        .sortedWith(compareBy<SoundMean>({ it.mean }, { it.phoneme }))
}

@Composable
private fun markColor(w: PronunciationResult.Word): Color? {
    if (!w.isJudged) return null
    return when (PronunciationResult.grade(w)) {
        0 -> pronRed()
        1 -> pronOrange()
        else -> null
    }
}

/** A dotted line under the word (SwiftUI `.underline(pattern: .dot)`). */
private fun Modifier.dotUnderline(color: Color): Modifier = drawBehind {
    val y = size.height - 1.dp.toPx()
    drawLine(color, Offset(2.dp.toPx(), y), Offset(size.width - 2.dp.toPx(), y),
        strokeWidth = 1.5.dp.toPx(), cap = StrokeCap.Round,
        pathEffect = PathEffect.dashPathEffect(floatArrayOf(0.01f, 3.dp.toPx())))
}

// MARK: - Names and verdicts

/** "Low" under 50, "A bit off" under 70, "Fine" otherwise — the bars the
 *  marks and the profile use. */
@Composable
private fun verdict(score: Int): String = stringResource(
    if (score < 50) R.string.low else if (score < PronunciationProfile.WEAK_BAR) R.string.a_bit_off else R.string.fine)

@Composable
private fun verdictColor(score: Int): Color =
    if (score < 50) pronRed() else if (score < PronunciationProfile.WEAK_BAR) pronOrange() else pronGreen()

/** A sound as a learner reads it: the course's own name where the sound has
 *  a chapter ("th"), a plain spelling otherwise ("sh", "ee"), the IPA
 *  itself as the last resort. */
private fun soundName(phoneme: String, language: String): String {
    PronunciationCourse.topics(language).firstOrNull { it.phonemes == listOf(phoneme) }?.let { return it.symbol }
    return ENGLISH_SOUND_NAMES[phoneme] ?: phoneme
}

private val ENGLISH_SOUND_NAMES = mapOf(
    "θ" to "th", "ð" to "th", "ʃ" to "sh", "ʒ" to "zh", "tʃ" to "ch", "dʒ" to "j", "ŋ" to "ng",
    "ɹ" to "r", "r" to "r", "j" to "y", "w" to "w", "h" to "h",
    "æ" to "a", "ɪ" to "i", "i" to "ee", "iː" to "ee", "ʊ" to "u", "u" to "oo", "uː" to "oo",
    "ɛ" to "e", "e" to "e", "ʌ" to "u", "ɑ" to "ah", "ɑː" to "ah", "ɒ" to "o", "ɔ" to "aw", "ɔː" to "aw",
    "ə" to "uh", "ɝ" to "er", "ɚ" to "er", "ɜ" to "er", "ɜː" to "er",
    "eɪ" to "ay", "aɪ" to "eye", "oʊ" to "oh", "əʊ" to "oh", "aʊ" to "ow", "ɔɪ" to "oy",
)

/** "en-US" → "English (United States)" in the app language. */
private fun localeName(id: String, chrome: java.util.Locale): String {
    val code = id.replace("_", "-")
    val name = java.util.Locale.forLanguageTag(code).getDisplayName(chrome)
    return name.ifBlank { id }
}

@Composable private fun pronGreen() = if (appIsDark()) Color(0xFF30D158) else Color(0xFF34C759)
@Composable private fun pronOrange() = if (appIsDark()) Color(0xFFFF9F0A) else Color(0xFFFF9500)
@Composable private fun pronRed() = if (appIsDark()) Color(0xFFFF453A) else Color(0xFFFF3B30)
