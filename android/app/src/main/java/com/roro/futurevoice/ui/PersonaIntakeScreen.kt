package com.roro.futurevoice.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AvatarStore
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.ContinuousShape
import kotlinx.coroutines.launch

/**
 * First-run persona collection — `PersonaIntakeView`, three light cards only:
 * name, home, and interests (they feed the news rail). The fourth card,
 * "What do you want to be able to do in English?", was cut from onboarding on
 * 2026-10-08 (founder, iOS `PersonaIntakeView`): two seconds of chips, never
 * revisited, and the first call learns what someone needs the language for
 * far better; its slot went to the accent question (`SetupFlowScreen`).
 * `persona.situations` stays editable in Me → Profile (`PersonaEditScreen`,
 * iOS `PersonaOnboardingView`), which is its own form, not these cards. The
 * narrative answers are
 * deliberately NOT asked here; the first talk works generic-but-warm.
 * Chip VALUES stay English on purpose (they are prompt material and the
 * selection match key); only labels would localize.
 */
@Composable
fun PersonaIntakeScreen(
    initial: UserPersona,
    targetLanguage: String,
    nativeLanguage: String,
    onBackToSetup: () -> Unit,
    onFinish: (UserPersona) -> Unit,
) {
    // iOS `PersonaIntakeView`'s draft: answers + the current card survive an
    // app kill and a cross-stage Back, so a relaunch resumes where the
    // learner left off instead of re-asking the cards. Saved at every step
    // transition, cleared on finish.
    val context = LocalContext.current
    // A draft from an interrupted run wins over [initial].
    val seed = remember { PersonaDraft.load(context) }
    val from = seed?.first ?: initial
    val lastStep = 2
    var step by remember { mutableIntStateOf((seed?.second ?: 0).coerceIn(0, lastStep)) }
    var name by remember { mutableStateOf(from.displayName) }
    var city by remember { mutableStateOf(from.city) }
    var country by remember { mutableStateOf(from.country) }
    var stay by remember { mutableStateOf(from.lengthOfStay) }
    var interests by remember { mutableStateOf(from.interests.toSet()) }
    fun draft() = initial.copy(
        displayName = name.trim(), city = city.trim(),
        country = country.trim(), lengthOfStay = stay.trim(),
        interests = interests.toList(),
    )
    fun saveDraft() { PersonaDraft.save(context, draft(), step) }
    /** Back: a step within the cards, or — on the first — reopen setup.
     *  Answers survive either way: the draft here, the app state there. */
    fun back() {
        if (step > 0) { step -= 1; saveDraft() } else { saveDraft(); onBackToSetup() }
    }
    androidx.activity.compose.BackHandler { back() }

    val canAdvance = when (step) {
        0 -> name.isNotBlank()
        1 -> city.isNotBlank()
        else -> true
    }

    // iOS: a NavigationStack with the inline title "About you" (no buttons),
    // the progress capsule, the card in a ScrollView (20 pt sides, 20 between
    // blocks) and `IntakeBottomBar` — the same pieces the people intake uses.
    val page = MaterialTheme.colorScheme.surface
    Column(Modifier.fillMaxSize().background(page)) {
        SheetHeader(stringResource(R.string.about_you),
            modifier = Modifier.statusBarsPadding().padding(horizontal = 16.dp).padding(top = 8.dp, bottom = 4.dp))
        IntakeProgress((step + 1f) / (lastStep + 1f), Modifier.padding(horizontal = 20.dp).padding(top = 8.dp))
        Column(
            Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(top = 16.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            // Keyed by card, so the interests card's unsubmitted "add your
            // own" text is folded in as it leaves (iOS `.onDisappear`).
            androidx.compose.runtime.key(step) { when (step) {
                0 -> {
                    IntakeStepHeader(stringResource(R.string.what_should_i_call_you),
                        stringResource(R.string.we_re_building_your_fluent_self_it_ll_speak_in_your_own_voic_e7ccbb))
                    // The picture is the learner's to pick: neither sign-in
                    // hands one over.
                    val scope = rememberCoroutineScope()
                    val pick = rememberLauncherForActivityResult(
                        ActivityResultContracts.PickVisualMedia()) { uri ->
                        uri?.let { scope.launch { AvatarStore.save(context, it) } }
                    }
                    // iOS: the avatar (88) with `pencil.circle.fill` at its
                    // bottom-trailing edge, and a centred `.title3` name field,
                    // in one grey card (padding 20 × 14, r 12).
                    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill())
                        .padding(vertical = 20.dp, horizontal = 14.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(16.dp)) {
                        Box(Modifier.clickable(
                            interactionSource = remember { MutableInteractionSource() }, indication = null) {
                            pick.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                        }, contentAlignment = Alignment.BottomEnd) {
                            ProfileAvatar(initials = name, size = 88.dp)
                            Box(Modifier.size(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.primary),
                                contentAlignment = Alignment.Center) {
                                Icon(Icons.Filled.Edit, contentDescription = null, modifier = Modifier.size(16.dp),
                                    tint = MaterialTheme.colorScheme.onPrimary)
                            }
                        }
                        BareField(name, { name = it }, stringResource(R.string.your_name),
                            style = MaterialTheme.typography.titleLarge, center = true,
                            capitalization = KeyboardCapitalization.Words)
                    }
                }
                1 -> {
                    IntakeStepHeader(stringResource(R.string.where_s_home_these_days),
                        stringResource(R.string.real_places_make_your_conversations_concrete_no_small_talk_a_d2fe54))
                    // City only (iOS 2026-10-08, founder): this card tells the
                    // fluent self where they live, and a city says that —
                    // typing the country too was effort for nothing. The
                    // field stays on the persona and in Me → Profile.
                    Column(Modifier.fillMaxWidth().clip(ContinuousShape(12.dp)).background(cardFill())) {
                        BareField(city, { city = it }, stringResource(R.string.city),
                            capitalization = KeyboardCapitalization.Words, modifier = Modifier.padding(14.dp))
                        // iOS `CardDivider(inset: 14)`: a 45% hairline, inset both sides.
                        HorizontalDivider(Modifier.padding(horizontal = 14.dp), thickness = 0.5.dp,
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.45f))
                        BareField(stay, { stay = it }, stringResource(R.string.how_long_have_you_been_there_optional),
                            modifier = Modifier.padding(14.dp))
                    }
                }
                else -> {
                    IntakeStepHeader(stringResource(R.string.what_are_you_into),
                        stringResource(R.string.tap_what_fits_these_pick_your_news_stories_and_fuel_conversa_369fbd))
                    ChipPickerField(PERSONA_INTEREST_PRESETS, interests, allowsCustom = true) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
                    }
                }
            } }
        }
        IntakeBottomBar(
            backVisible = true,
            // Voice clone follows this flow, so the last card is a "Next",
            // not the app entrance.
            nextTitle = stringResource(R.string.next),
            nextEnabled = canAdvance,
            working = false,
            onBack = { back() },
            onNext = {
                if (step < lastStep) { step += 1; saveDraft() }
                else {
                    PersonaDraft.clear(context)
                    onFinish(draft())
                }
            },
        )
    }
}

/** iOS `TextField` with no chrome: the text, the prompt as placeholder. */
@Composable
private fun BareField(
    value: String,
    onChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    center: Boolean = false,
    capitalization: KeyboardCapitalization = KeyboardCapitalization.Sentences,
) {
    val s = style.copy(color = MaterialTheme.colorScheme.onSurface,
        textAlign = if (center) TextAlign.Center else TextAlign.Start)
    BasicTextField(
        value = value, onValueChange = onChange, textStyle = s, singleLine = true,
        cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
        keyboardOptions = KeyboardOptions(capitalization = capitalization),
        modifier = modifier.fillMaxWidth(),
        decorationBox = { inner ->
            Box(Modifier.fillMaxWidth(), contentAlignment = if (center) Alignment.Center else Alignment.CenterStart) {
                if (value.isEmpty()) Text(placeholder, style = s,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.28f), maxLines = 1)
                inner()
            }
        },
    )
}

/**
 * The first-run intake's draft (iOS `futurevoice.personaDraft` /
 * `futurevoice.personaDraftStep`): the answers and the card they were on.
 */
internal object PersonaDraft {
    private const val KEY = "futurevoice.personaDraft"
    private const val STEP_KEY = "futurevoice.personaDraftStep"

    fun load(c: android.content.Context): Pair<UserPersona, Int>? {
        val p = c.getSharedPreferences("futurevoice", 0)
        val raw = p.getString(KEY, null) ?: return null
        val persona = runCatching {
            com.roro.futurevoice.data.StoreJson.json.decodeFromString(UserPersona.serializer(), raw)
        }.getOrNull() ?: return null
        // A step from an older, longer flow can point past the end — clamp
        // instead of silently restarting at card one.
        return persona to p.getInt(STEP_KEY, 0).coerceIn(0, 2)
    }

    fun save(c: android.content.Context, persona: UserPersona, step: Int) {
        c.getSharedPreferences("futurevoice", 0).edit()
            .putString(KEY, com.roro.futurevoice.data.StoreJson.json.encodeToString(UserPersona.serializer(), persona))
            .putInt(STEP_KEY, step).apply()
    }

    fun clear(c: android.content.Context) {
        c.getSharedPreferences("futurevoice", 0).edit().remove(KEY).remove(STEP_KEY).apply()
    }
}
