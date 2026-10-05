package com.roro.futurevoice.ui

import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material3.ButtonDefaults
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.PaddingValues
import android.content.Context
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.roro.futurevoice.R
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.SpeechSpeed
import com.roro.futurevoice.talk.CoachMode
import com.roro.futurevoice.talk.Session
import com.roro.futurevoice.talk.TurnRole

/**
 * After the first call: "how was it?" — and the three things that change how
 * the next one feels, on one page (iOS `FirstCallCheckSheet`, `eaaf3af`). A
 * beginner who found the call too hard had no way to know that the level they
 * picked in setup, the voice's speed and coach mode are what to move, or where
 * each of them lives. So the answer pre-sets them — Hard: a level down, the
 * slow voice, coach on; Easy: a level up, coach off — and the learner changes
 * anything before saving. Nothing is applied until Save.
 *
 * Raised ONCE, after the learner's first call (one they spoke in), before the
 * plans pitch — `TalkScreen.pitchThenLeave`. Capture: `first-call-check[-hard]`.
 */
object FirstCallCheck {
    /** Same name as iOS's defaults key. */
    const val SHOWN_KEY = "futurevoice.firstCallCheck.shown"

    enum class Feeling { EASY, RIGHT, HARD }

    /** What a pick pre-sets below (iOS `pick(_:)`), as a value for tests. */
    data class Preset(val level: CefrLevel, val speed: SpeechSpeed, val coach: Boolean)

    fun preset(feeling: Feeling, level: CefrLevel, speed: SpeechSpeed, coach: Boolean): Preset {
        val all = CefrLevel.entries
        val i = all.indexOf(level)
        return when (feeling) {
            Feeling.HARD -> Preset(all[maxOf(0, i - 1)], SpeechSpeed.SLOWER, true)
            Feeling.EASY -> Preset(all[minOf(all.size - 1, i + 1)], speed, false)
            Feeling.RIGHT -> Preset(level, speed, coach)
        }
    }

    /** The first finished talk the learner spoke in, and at most one such
     *  talk on file: installs with a talk history already don't see it —
     *  "your first call" would be untrue for them. */
    fun isFirst(sessions: List<Session>): Boolean =
        sessions.count { s -> s.endedAt != null && s.turns.any { it.role == TurnRole.USER } } <= 1

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    suspend fun shouldShow(context: Context, learnerSpoke: Boolean): Boolean {
        if (!learnerSpoke || prefs(context).getBoolean(SHOWN_KEY, false)) return false
        val store = SessionStore.shared(context)
        val all = LanguageScope.enrolled(context).distinct()
            .flatMap { runCatching { store.load(it) }.getOrDefault(emptyList()) }
        return isFirst(all)
    }

    fun markShown(context: Context) = prefs(context).edit().putBoolean(SHOWN_KEY, true).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FirstCallCheckSheet(
    targetLanguage: String,
    /** The level the call ran at — "You picked …". */
    currentLevel: CefrLevel,
    /** Capture only: open with a pick already made. */
    initialFeeling: FirstCallCheck.Feeling? = null,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val app: AppViewModel = viewModel(factory = viewModelFactory {
        initializer { AppViewModel(context.applicationContext) }
    })
    val currentSpeed = remember { SpeechSpeed.current(context) }
    val currentCoach = remember { CoachMode.resolve(CoachMode.choice(context), currentLevel.code) }
    var feeling by remember { mutableStateOf<FirstCallCheck.Feeling?>(null) }
    var level by remember { mutableStateOf(currentLevel) }
    var speed by remember { mutableStateOf(currentSpeed) }
    var coach by remember { mutableStateOf(currentCoach) }
    fun pick(f: FirstCallCheck.Feeling) {
        feeling = f
        val p = FirstCallCheck.preset(f, currentLevel, currentSpeed, currentCoach)
        level = p.level; speed = p.speed; coach = p.coach
    }
    remember { initialFeeling?.let { pick(it) }; true }

    fun save() {
        if (level != currentLevel) app.setLevel(targetLanguage, level)
        SpeechSpeed.set(context, speed)
        // Always written: the learner saw the switch and confirmed it, and an
        // unset choice would follow the NEW level's default instead.
        CoachMode.setChoice(context, coach)
        com.roro.futurevoice.core.Telemetry.log("first_call_check", mapOf(
            "feeling" to (feeling?.name?.lowercase() ?: "none"),
            "level" to level.code, "speed" to speed.raw, "coach" to if (coach) "on" else "off",
        ))
        onDismiss()
    }

    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp)) {
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.later)) }
            }
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
                    .padding(horizontal = 20.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(stringResource(R.string.fcc_title), style = MaterialTheme.typography.headlineSmall,
                    fontWeight = FontWeight.Bold)
                Text(stringResource(R.string.fcc_you_picked, LanguageCatalog.levelLabel(currentLevel, targetLanguage)),
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(levelBlurb(currentLevel), style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)

                Spacer(Modifier.size(10.dp))
                // Words only: a hare and a tortoise read as the voice's SPEED,
                // which is a different control on this same page.
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FirstCallCheck.Feeling.entries.forEach { f ->
                        val label = stringResource(when (f) {
                            FirstCallCheck.Feeling.EASY -> R.string.fcc_easy
                            FirstCallCheck.Feeling.RIGHT -> R.string.fcc_just_right
                            FirstCallCheck.Feeling.HARD -> R.string.fcc_hard
                        })
                        // iOS: a 52 pt label inside `.bordered`, ~64 pt capsule, one line;
                        // Material's 24 dp side padding wrapped 딱 좋았어요 onto two.
                        val mod = Modifier.weight(1f).heightIn(min = 64.dp)
                        val pad = PaddingValues(horizontal = 6.dp, vertical = 6.dp)
                        val text: @Composable () -> Unit = {
                            Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold,
                                maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis)
                        }
                        // The picked one is FILLED — the system's own "selected"; the
                        // others are `.bordered` tinted `.secondary`: a grey fill, grey words.
                        if (feeling == f) Button(onClick = { pick(f) }, modifier = mod, shape = CircleShape,
                            contentPadding = pad, elevation = null) { text() }
                        else Button(onClick = { pick(f) }, modifier = mod, shape = CircleShape,
                            contentPadding = pad, elevation = null,
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.14f),
                                contentColor = MaterialTheme.colorScheme.onSurfaceVariant)) { text() }
                    }
                }
                feeling?.let { f ->
                    Footer(stringResource(when (f) {
                        FirstCallCheck.Feeling.HARD -> R.string.fcc_set_hard
                        FirstCallCheck.Feeling.EASY -> R.string.fcc_set_easy
                        FirstCallCheck.Feeling.RIGHT -> R.string.fcc_set_right
                    }))
                }

                Spacer(Modifier.size(12.dp))
                LevelRow(level, targetLanguage) { level = it }
                // A pick above can move this off the level named at the top;
                // say the move out loud, or the page reads as contradicting
                // itself ("you picked A2" over "A1").
                if (level != currentLevel) {
                    Text("${LanguageCatalog.levelLabel(currentLevel, targetLanguage)} → " +
                        LanguageCatalog.levelLabel(level, targetLanguage),
                        style = MaterialTheme.typography.bodySmall, fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.primary)
                }
                Footer(levelBlurb(level))

                Spacer(Modifier.size(12.dp))
                Text(stringResource(R.string.speaking_speed).uppercase(), style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SpeechSpeed.entries.forEachIndexed { i, s ->
                        SegmentedButton(selected = speed == s, onClick = { speed = s },
                            shape = SegmentedButtonDefaults.itemShape(i, SpeechSpeed.entries.size)) {
                            Text(stringResource(s.label), maxLines = 1)
                        }
                    }
                }
                Footer(stringResource(R.string.fcc_speed_footer))

                Spacer(Modifier.size(12.dp))
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Outlined.Lightbulb, contentDescription = null, modifier = Modifier.size(20.dp),
                        tint = MaterialTheme.colorScheme.primary)
                    Text(stringResource(R.string.cm_coach_mode), style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f))
                    com.roro.futurevoice.ui.brand.IosSwitch(checked = coach, onCheckedChange = { coach = it })
                }
                Footer(stringResource(R.string.fcc_coach_footer))
                Spacer(Modifier.size(12.dp))
            }
            Button(onClick = { save() },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp).heightIn(min = 50.dp)) {
                Text(stringResource(R.string.save), style = MaterialTheme.typography.titleMedium)
            }
        }
    }
}

@Composable
private fun LevelRow(level: CefrLevel, target: String, onPick: (CefrLevel) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Row(Modifier.fillMaxWidth().clickable { open = true }.padding(vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.Filled.BarChart, contentDescription = null, modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.primary)
            Text(stringResource(R.string.fcc_your_level), style = MaterialTheme.typography.bodyLarge,
                modifier = Modifier.weight(1f))
            Text(LanguageCatalog.levelLabel(level, target), style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.Filled.ExpandMore, contentDescription = null, modifier = Modifier.size(20.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            CefrLevel.entries.forEach { l ->
                DropdownMenuItem(text = { Text(LanguageCatalog.levelLabel(l, target)) },
                    onClick = { onPick(l); open = false })
            }
        }
    }
}

@Composable
private fun Footer(text: String) {
    Text(text, style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant)
}
