package com.roro.futurevoice.ui

import android.content.Context
import androidx.compose.foundation.background
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
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.SheetValue
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.roro.futurevoice.R
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.data.CefrLevel
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.LanguageScope
import com.roro.futurevoice.data.SessionStore
import com.roro.futurevoice.data.SpeechSpeed
import com.roro.futurevoice.talk.CoachMode
import com.roro.futurevoice.talk.SendToAnswer
import com.roro.futurevoice.talk.TurnRole
import com.roro.futurevoice.talk.TutorMode

/**
 * Before the first call: the few settings that decide how a call feels, set
 * BEFORE the fluent self says a word (iOS `FirstCallSetupSheet`, 6d90ac85 +
 * f39a7f4b + 6cc0f4a8, 2026-10-24, founder request). The after-call check
 * ([FirstCallCheckSheet]) asks "how was it?" once the learner has already
 * struggled through a call at whatever the defaults were; this is the same
 * page in front of the call, so a beginner can slow the voice and turn coach
 * mode on before they need it. Tutor mode too, since it decides how the call
 * OPENS (a lesson instead of a hello).
 *
 * Raised ONCE, from [TalkScreen] before the call starts — the one door every
 * fresh call goes through — and only on an install with no spoken talk on
 * file. The call waits on it like it waits on the mic sheet. There is no Skip,
 * and neither a swipe, the scrim nor Back closes it (iOS, 2026-11-06, founder:
 * "this has to be chosen, always"): Start is the only way out, writes
 * everything, and marks the sheet shown, so a killed app asks again next call.
 * Capture: `first-call-setup`.
 */
object FirstCallSetup {
    /** Same name as iOS's defaults key. */
    const val SHOWN_KEY = "futurevoice.firstCallSetup.shown"

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences("futurevoice", Context.MODE_PRIVATE)

    /** No talk the learner spoke in yet, and never asked before. An install
     *  with a history has already found these settings by living with them. */
    suspend fun shouldShow(context: Context): Boolean {
        if (prefs(context).getBoolean(SHOWN_KEY, false)) return false
        val store = SessionStore.shared(context)
        return LanguageScope.enrolled(context).distinct().none { lang ->
            runCatching { store.load(lang) }.getOrDefault(emptyList())
                .any { s -> s.turns.any { it.role == TurnRole.USER } }
        }
    }

    fun markShown(context: Context) = prefs(context).edit().putBoolean(SHOWN_KEY, true).apply()
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FirstCallSetupSheet(
    targetLanguage: String,
    /** The stored level (iOS `appState.proficiency`). */
    currentLevel: CefrLevel,
    /** Every way out; [started] = the learner pressed Start the call. */
    onDismiss: (started: Boolean) -> Unit,
) {
    val context = LocalContext.current
    val app: AppViewModel = viewModel(factory = viewModelFactory {
        initializer { AppViewModel(context.applicationContext) }
    })
    var level by remember { mutableStateOf(currentLevel) }
    var speed by remember { mutableStateOf(SpeechSpeed.current(context)) }
    var coach by remember { mutableStateOf(CoachMode.resolve(CoachMode.choice(context), currentLevel.code)) }
    var sendToAnswer by remember {
        mutableStateOf(SendToAnswer.resolve(SendToAnswer.choice(context), currentLevel.code))
    }

    fun report(event: String, extra: Map<String, String> = emptyMap()) {
        val props = mapOf("level_before" to currentLevel.code) + extra
        com.roro.futurevoice.core.Telemetry.log(event, props)
        com.roro.futurevoice.core.Analytics.capture(event, props)
    }
    LaunchedEffect(Unit) { report("first_call_setup_shown") }

    // Coach mode and Send follow the level until the learner flips them
    // (`CoachMode.resolve`), so moving the level here moves them with it, as
    // it would anywhere else. Back on the stored level = what is stored, so
    // loading the sheet never overwrites a choice already made.
    fun pickLevel(new: CefrLevel) {
        level = new
        if (new == currentLevel) {
            coach = CoachMode.resolve(CoachMode.choice(context), currentLevel.code)
            sendToAnswer = SendToAnswer.resolve(SendToAnswer.choice(context), currentLevel.code)
        } else {
            coach = CoachMode.resolve(null, new.code)
            sendToAnswer = SendToAnswer.resolve(null, new.code)
        }
    }

    fun start() {
        if (level != currentLevel) app.setLevel(targetLanguage, level)
        SpeechSpeed.set(context, speed)
        // Written even when unchanged: the learner saw the switch and chose,
        // and an unset choice would follow a later level change instead.
        CoachMode.setChoice(context, coach)
        SendToAnswer.setChoice(context, sendToAnswer)
        FirstCallSetup.markShown(context)
        report("first_call_setup", mapOf(
            "level" to level.code, "speed" to speed.raw,
            "coach" to if (coach) "on" else "off", "send" to if (sendToAnswer) "on" else "off",
            "tutor" to if (TutorMode.isOn(context)) "on" else "off",
        ))
        onDismiss(true)
    }

    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
            confirmValueChange = { it != SheetValue.Hidden },
        ),
        onDismissRequest = {}, containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Column(
                Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
            ) {
                Column(Modifier.padding(start = 4.dp, end = 4.dp, top = 8.dp, bottom = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(stringResource(R.string.before_your_first_call),
                        style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Text(stringResource(R.string.you_can_change_these_any_time_during_a_call),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant)
                }

                // How a turn ends, first, with what it changes (iOS,
                // 2026-11-06, founder). A call is a phone call; Send makes it
                // wait like a message, so it stays a switch.
                GroupedSectionSpacer()
                GroupedCard {
                    SetupToggleRow(Icons.AutoMirrored.Outlined.Send, stringResource(R.string.answer_with_send),
                        sendToAnswer) { sendToAnswer = it }
                }
                GroupedFooter(stringResource(
                    R.string.a_call_answers_the_moment_you_pause_with_this_on_your_future_3f6834))

                GroupedSectionSpacer()
                GroupedCard { SetupLevelRow(level, targetLanguage) { pickLevel(it) } }
                GroupedFooter(levelBlurb(level))

                GroupedSectionHeader(stringResource(R.string.speaking_speed))
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    SpeechSpeed.entries.forEachIndexed { i, s ->
                        SegmentedButton(selected = speed == s, onClick = { speed = s },
                            shape = SegmentedButtonDefaults.itemShape(i, SpeechSpeed.entries.size)) {
                            Text(stringResource(s.label), maxLines = 1)
                        }
                    }
                }

                GroupedSectionSpacer()
                GroupedCard {
                    SetupToggleRow(Icons.Outlined.Lightbulb, stringResource(R.string.try_saying), coach) { coach = it }
                }
                GroupedFooter(stringResource(
                    R.string.each_time_your_future_self_says_something_you_see_a_line_you_9bbb1d))


                Spacer(Modifier.size(12.dp))
            }
            Box(Modifier.fillMaxWidth().background(AppSurfaces.ground)
                .padding(horizontal = 20.dp, vertical = 8.dp)) {
                Button(onClick = { start() }, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)) {
                    Text(stringResource(R.string.start_the_call), style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold)
                }
            }
        }
    }
}

/** iOS: a menu `Picker` labelled "Your level" with `chart.bar`. */
@Composable
private fun SetupLevelRow(level: CefrLevel, target: String, onPick: (CefrLevel) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Row(Modifier.fillMaxWidth().clickable { open = true }.heightIn(min = 52.dp)
        .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(Icons.Filled.BarChart, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.your_level_0ad2c2), style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f))
        Box {
            Row(verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(LanguageCatalog.levelLabel(level, target), style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary)
                Icon(Icons.Filled.UnfoldMore, contentDescription = null, modifier = Modifier.size(15.dp),
                    tint = MaterialTheme.colorScheme.primary)
            }
            com.roro.futurevoice.ui.brand.IosPickerMenu(
                expanded = open, onDismissRequest = { open = false },
                options = CefrLevel.entries.map { it to LanguageCatalog.levelLabel(it, target) },
                selected = level, onPick = onPick)
        }
    }
}

@Composable
private fun SetupToggleRow(icon: ImageVector, text: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        Icon(icon, contentDescription = null, modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.primary)
        Text(text, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.weight(1f))
        com.roro.futurevoice.ui.brand.IosSwitch(checked = checked, onCheckedChange = onChange)
    }
}
