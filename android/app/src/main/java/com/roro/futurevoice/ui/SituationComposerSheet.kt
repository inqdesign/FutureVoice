package com.roro.futurevoice.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.UnfoldMore
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.roro.futurevoice.R
import com.roro.futurevoice.data.AuthRepository
import com.roro.futurevoice.data.BillingGate
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.CounterpartStore
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.data.PersonaStore
import com.roro.futurevoice.data.ScenarioIdeaCache
import com.roro.futurevoice.data.ScenarioStore
import com.roro.futurevoice.data.StoreEvents
import com.roro.futurevoice.net.PublicPersonaClient
import com.roro.futurevoice.net.TopicClient
import com.roro.futurevoice.talk.PathIdeas
import com.roro.futurevoice.talk.PathIdeasContent
import com.roro.futurevoice.talk.Scenario
import com.roro.futurevoice.talk.StockPerson
import com.roro.futurevoice.talk.SuggestedTopic
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.Symbols
import kotlinx.coroutines.launch

/**
 * The ONE scenario creator (iOS `ScenarioComposerSheet`) — "make your own
 * situation". Talk's "+" and every Watch flow land here.
 *
 * Three ways in, one field: pick a category and narrow it down, type the real
 * upcoming thing, or tap the mic and say it. Whatever route was taken, the
 * text stays editable — a prefill is a head start, never a script.
 *
 * Categorizing is a nicety and never blocks a commit (iOS rule): a failure
 * just leaves the free text as the scenario, with no breadcrumb.
 */
enum class ComposerHost { TALK, WATCH }

/** One step of the composer's drill-down. */
private data class Crumb(val label: String, val icon: String?)

/** Category + 2 narrowing picks. Past this the scenario is specific enough. */
private const val MAX_DEPTH = 3

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ScenarioComposer(
    targetLanguage: String,
    existingCategories: List<String>,
    /** A "Likely situations" leaf, dropped in ready to edit — never locked. */
    prefill: String = "",
    /** Who the scene is with, when the composer was opened from a face. */
    person: Counterpart? = null,
    /**
     * Which surface the composer serves. Talk offers "Future self" — a call
     * with no one attached is a call with your own fluent voice, the
     * product's core. Watch doesn't: a scene always needs an other person,
     * so its default partner is a character.
     */
    host: ComposerHost = ComposerHost.TALK,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var draft by remember { mutableStateOf(prefill) }
    var committing by remember { mutableStateOf(false) }
    var path by remember { mutableStateOf<List<Crumb>>(emptyList()) }
    var options by remember { mutableStateOf<List<SuggestedTopic>>(emptyList()) }
    var loadingOptions by remember { mutableStateOf(false) }
    var optionsError by remember { mutableStateOf<String?>(null) }
    /** True once the learner has TYPED their own. In custom mode the chip
     *  grid hides and the category is DERIVED from the text, so the two
     *  input styles can never contradict each other. */
    var customMode by remember { mutableStateOf(prefill.isNotBlank()) }
    var categorizing by remember { mutableStateOf(false) }
    /** The tidy card summary — a picked chip's short label, or the model's
     *  paraphrase of typed text. Never the raw prompt. */
    var summary by remember { mutableStateOf("") }
    var usedVoice by remember { mutableStateOf(false) }
    /** Raised in place of the CTA when the account can't pay for what it
     *  starts. Presented from THIS sheet, never from the host behind it: a
     *  sheet raised underneath an open sheet never appears, and the composer
     *  staying up means the situation just written is still there after. */
    var showPaywall by remember { mutableStateOf(false) }

    // WHO the other side is. nil = the future self (Talk only). Materialized
    // into CounterpartStore on commit, so downstream it is an ordinary person.
    var partner by remember { mutableStateOf(person) }
    var pickingPartner by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) {
        // A scene needs an other person, so Watch opens on the default
        // character; Talk with nobody attached stays the fluent self.
        if (person == null && host == ComposerHost.WATCH && partner == null) {
            partner = StockPerson.catalog.first()
                .asCounterpart(CounterpartStore.shared(context).load())
        }
    }

    // Dictation language. The app language is what a situation gets described
    // in, but pinning it silently meant a learner who spoke the language they
    // are LEARNING got nonsense back with nothing on screen to explain why —
    // so the choice is visible and one tap away. Typing is language-agnostic.
    val nativeLanguage = remember {
        context.getSharedPreferences("futurevoice", android.content.Context.MODE_PRIVATE)
            // AppViewModel's key, spelled out: its companion is private, and
            // the composer only ever READS the choice made in setup / Me.
            .getString("futurevoice.nativeLanguage", null) ?: LanguageCatalog.defaultNative()
    }
    var dictationLocale by remember { mutableStateOf(nativeLanguage) }

    suspend fun refreshOptions(force: Boolean = false) {
        val labels = path.map { it.label }
        if (labels.isEmpty() || labels.size >= MAX_DEPTH) { options = emptyList(); return }
        val key = ScenarioIdeaCache.key(person?.id, labels)
        if (!force) ScenarioIdeaCache.topics(context, key)?.let { options = it; return }
        // Level 1 of a preset category: shipped seeds, zero round-trip. The
        // sub-areas of "Cafe" are the same for everyone, and waiting on the
        // model for them costs the learner the pause right after their first
        // tap. "More" (force) asks the model here too.
        if (!force && person == null && labels.size == 1) {
            PathIdeasContent.seedSubAreas(labels[0])?.let { seed ->
                options = seed.map { SuggestedTopic(title = it.title, blurb = it.blurb) }
                return
            }
        }
        loadingOptions = true; optionsError = null; options = emptyList()
        runCatching {
            PathIdeas.suggest(labels, PersonaStore.shared(context).load(), person, targetLanguage)
        }.onSuccess { result ->
            ScenarioIdeaCache.store(context, key, result)
            // Guard against a stale response (they navigated during the await).
            if (path.map { it.label } == labels) options = result
        }.onFailure { optionsError = context.getString(R.string.composer_ideaserr) }
        loadingOptions = false
    }

    /** Read the free-typed scenario and set the breadcrumb category — an
     *  existing one when it fits, otherwise the one the model names. */
    suspend fun deriveCategory() {
        val text = draft.trim()
        if (text.isEmpty() || categorizing) return
        categorizing = true
        runCatching {
            TopicClient(AuthRepository()).categorize(
                text = text,
                existing = (PathIdeasContent.categories.map { it.title } + existingCategories).distinct(),
                iconOptions = TopicClient.ICON_PALETTE,
                targetLanguage = targetLanguage)
        }.onSuccess { r ->
            val match = PathIdeasContent.categories
                .firstOrNull { it.title.equals(r.category, ignoreCase = true) }
            summary = r.summary
            // Show the derived category as the breadcrumb; stay in custom
            // mode — their text IS the scenario, so no chip grid is needed.
            path = listOf(Crumb(match?.title ?: r.category, match?.icon ?: r.icon))
        }
        // A failure just leaves the free text as the scenario, with no
        // breadcrumb. It never blocks committing.
        categorizing = false
    }

    fun onDraftChanged(new: String) {
        draft = new
        if (new.isBlank()) {
            // Cleared → back to browsing categories from scratch.
            customMode = false
            path = emptyList(); options = emptyList(); summary = ""
            return
        }
        customMode = true
        if (path.isNotEmpty()) { path = emptyList(); options = emptyList() }
    }

    val ctaTitle = stringResource(R.string.create)
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    // A SHEET, not a dialog: non-primary content lives in sheets (iOS UI
    // rules), and a dialog over a full-width composer reads as an alert.
    // FULL height, like iOS's `NavigationStack` presentation — a half sheet
    // put the category grid below the fold on every phone.
    ModalBottomSheet(
        onDismissRequest = { if (!committing) onDismiss() },
        sheetState = sheetState,
        dragHandle = null,
        containerColor = AppSurfaces.ground,
    ) {
        Column(Modifier.fillMaxSize().imePadding()) {
            // Cancel · title · the primary action, exactly as iOS's toolbar.
            Row(
                Modifier.fillMaxWidth().padding(start = 8.dp, end = 12.dp, top = 6.dp, bottom = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onDismiss, enabled = !committing) {
                    Text(stringResource(R.string.cancel))
                }
                Text(
                    if (person != null) stringResource(R.string.a_scene_with_lls, person.name)
                    else stringResource(R.string.new_scenario),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f).padding(horizontal = 8.dp),
                )
                Button(
                    enabled = draft.isNotBlank() && !committing,
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 6.dp),
                    colors = ButtonDefaults.buttonColors(),
                    onClick = {
                        committing = true
                        val text = draft.trim()
                        scope.launch {
                            // The CTA is the paid tap: the account is asked
                            // HERE, before anything is generated. Blocked
                            // means the plans and nothing else — no
                            // categorize call, no scenario minted.
                            val allowed = BillingGate.start(AuthRepository()) { }
                            if (!allowed) {
                                // The gate raises the ROOT paywall, which
                                // would replace the screen this sheet is on
                                // and lose the situation just written. This
                                // sheet owns its own.
                                BillingGate.showPaywall.value = false
                                showPaywall = true
                                committing = false
                                return@launch
                            }
                            var categoryName = path.firstOrNull()?.label
                            var icon = path.firstOrNull()?.icon
                            var sum = summary
                            // Typed but never categorized (they hit the CTA
                            // before the field lost focus) → tidy it up now,
                            // so the card shows a clean category + summary
                            // rather than the raw prompt.
                            if (categoryName == null || sum.isBlank()) {
                                runCatching {
                                    TopicClient(AuthRepository()).categorize(
                                        text = text,
                                        existing = (PathIdeasContent.categories.map { it.title } +
                                            existingCategories).distinct(),
                                        iconOptions = TopicClient.ICON_PALETTE,
                                        targetLanguage = targetLanguage)
                                }.getOrNull()?.let { r ->
                                    categoryName = categoryName ?: r.category.takeIf { it.isNotBlank() }
                                    icon = icon ?: r.icon
                                    if (sum.isBlank()) sum = r.summary
                                }
                            }
                            // A picked character/user becomes a real row the
                            // moment a scenario is built with them — from
                            // here on they are an ordinary person.
                            val who = partner
                            if (who != null && person == null) {
                                val store = CounterpartStore.shared(context)
                                if (store.load().none { it.id == who.id }) store.save(who)
                            }
                            ScenarioStore.shared(context).save(Scenario(
                                environment = text,
                                category = categoryName,
                                categoryIcon = icon,
                                summary = sum.takeIf { it.isNotBlank() },
                                // An EMPTY role is what lets a scene infer
                                // its own counterpart, so it stays empty when
                                // nobody was picked — and for a stranger or a
                                // character, whose identity rides in the
                                // prompt's counterpart block instead.
                                role = roleLine(who),
                                counterpartId = who?.id,
                                // Android's scene reads the voice off the
                                // scenario, so an attached person's preset
                                // has to be written here or the scene plays
                                // in the default character's voice.
                                voicePresetId = who?.voicePresetId?.takeIf { it.isNotBlank() },
                            ), targetLanguage)
                            StoreEvents.bump()
                            committing = false; onDismiss()
                        }
                    },
                ) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(if (committing) stringResource(R.string.working) else ctaTitle)
                }
            }

            Column(
                Modifier.weight(1f).verticalScroll(rememberScrollState())
                    .bottomBarInsets()
                    .padding(horizontal = 20.dp).padding(bottom = 32.dp),
            ) {
                if (person != null) {
                    GroupedCard { PersonRow(person) }
                }

                // MARK: Your scenario — breadcrumb + the assembled text
                GroupedSectionHeader(stringResource(R.string.your_scenario))
                GroupedCard {
                    Column(
                        Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        if (path.isNotEmpty()) {
                            Row(
                                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                                horizontalArrangement = Arrangement.spacedBy(6.dp),
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                path.forEachIndexed { i, crumb ->
                                    if (i > 0) Icon(
                                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                                        contentDescription = null,
                                        tint = MaterialTheme.colorScheme.outline,
                                        modifier = Modifier.size(16.dp))
                                    CrumbChip(crumb.label, crumb.icon, selected = i == path.lastIndex) {
                                        // Tapping the CATEGORY crumb returns
                                        // to the grid so a different one can
                                        // be picked; deeper crumbs back up.
                                        customMode = false
                                        path = path.take(i)
                                        scope.launch { refreshOptions() }
                                    }
                                }
                            }
                        }
                        // Type it, or tap the mic and say it — dictation
                        // streams into the same field, so a spoken answer can
                        // be corrected by hand without starting over. Focus
                        // is watched from the wrapper because losing it is
                        // where the category gets derived.
                        var hadFocus by remember { mutableStateOf(false) }
                        Box(Modifier.onFocusEvent { st ->
                            val has = st.hasFocus
                            if (hadFocus && !has && customMode && path.isEmpty() && draft.isNotBlank()) {
                                scope.launch { deriveCategory() }
                            }
                            hadFocus = has
                        }) {
                            SpeakOrTypeField(
                                text = draft,
                                onText = ::onDraftChanged,
                                usedVoice = usedVoice,
                                onUsedVoice = { usedVoice = it },
                                placeholder = stringResource(R.string.composer_placeholder),
                                locale = LanguageCatalog.sttLocale(dictationLocale),
                            )
                        }
                        DictationLanguageRow(dictationLocale) { dictationLocale = it }
                        if (categorizing) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                                Text(stringResource(R.string.filing_this_under_a_category),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        }
                    }
                }
                GroupedFooter(stringResource(
                    R.string.build_it_from_a_category_below_type_it_or_say_it_with_the_mi_657c0f,
                    ctaTitle))

                // MARK: Choices — the current drill level
                when {
                    // Writing their own: no chip grid to contradict the text.
                    customMode -> Unit

                    path.isEmpty() -> {
                        GroupedSectionHeader(stringResource(R.string.pick_a_category))
                        ChoiceGrid(PathIdeasContent.categories.map { it.title to it.icon }) { i ->
                            val c = PathIdeasContent.categories[i]
                            customMode = false
                            path = listOf(Crumb(c.title, c.icon))
                            scope.launch { refreshOptions() }
                        }
                    }

                    path.size < MAX_DEPTH || loadingOptions -> {
                        Row(
                            Modifier.fillMaxWidth().padding(top = 20.dp, bottom = 6.dp, start = 4.dp, end = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Text(
                                stringResource(if (path.size == 1) R.string.narrow_it_down
                                else R.string.pick_a_scenario).uppercase(),
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.weight(1f))
                            if (loadingOptions) {
                                CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            } else {
                                IconButton(
                                    onClick = { scope.launch { refreshOptions(force = true) } },
                                    modifier = Modifier.size(32.dp),
                                ) {
                                    Icon(Icons.Filled.Refresh,
                                        contentDescription = stringResource(R.string.more),
                                        tint = MaterialTheme.colorScheme.primary,
                                        modifier = Modifier.size(18.dp))
                                }
                                TextButton(
                                    onClick = { scope.launch { refreshOptions(force = true) } },
                                    contentPadding = PaddingValues(horizontal = 8.dp),
                                ) { Text(stringResource(R.string.more)) }
                            }
                        }
                        if (loadingOptions && options.isEmpty()) {
                            // Skeletons keep the grid the SAME shape while
                            // the model writes, so nothing jumps and the wait
                            // reads as "writing", not "broken".
                            SkeletonGrid()
                        } else {
                            ChoiceGrid(options.map { it.title to null }) { i ->
                                val o = options[i]
                                // The blurb IS the scenario if they stop
                                // here; one more step only narrows it. Written
                                // straight to the state, not through the change
                                // handler — Compose never reports our own write
                                // as a keystroke, so nothing has to be flagged.
                                draft = o.blurb.ifBlank { o.title }
                                summary = o.title
                                customMode = false
                                if (path.size < MAX_DEPTH) {
                                    path = path + Crumb(o.title, null)
                                    scope.launch { refreshOptions() }
                                } else options = emptyList()
                            }
                        }
                        optionsError?.let {
                            Text(it, style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.error,
                                modifier = Modifier.padding(top = 6.dp, start = 4.dp))
                        }
                        GroupedFooter(stringResource(
                            if (path.size == 1)
                                R.string.pick_an_area_to_go_one_step_deeper_or_type_your_own_above
                            else R.string.tap_one_to_fill_your_scenario_above_then_edit_it_freely))
                    }

                    else -> {
                        GroupedSectionSpacer()
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(Icons.Filled.CheckCircle, contentDescription = null,
                                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.size(18.dp))
                            Text(stringResource(
                                R.string.specific_enough_it_or_tap_a_breadcrumb_to_explore_more, ctaTitle),
                                style = MaterialTheme.typography.bodyMedium,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }

                // MARK: The other person — one row, because the choice is a
                // person, not a setting: the detail lives in the picker.
                if (person == null) {
                    GroupedSectionHeader(stringResource(R.string.the_other_person))
                    GroupedCard {
                        Row(
                            Modifier.fillMaxWidth().clickable { pickingPartner = true }
                                .padding(horizontal = 16.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            PartnerAvatar(partner)
                            Spacer(Modifier.width(12.dp))
                            Column(Modifier.weight(1f)) {
                                Text(partner?.name ?: stringResource(R.string.future_self_1384d5),
                                    style = MaterialTheme.typography.bodyLarge)
                                Text(partnerCaption(partner),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Icon(Icons.Filled.UnfoldMore, contentDescription = null,
                                tint = MaterialTheme.colorScheme.outline,
                                modifier = Modifier.size(18.dp))
                        }
                    }
                    GroupedFooter(stringResource(
                        R.string.their_role_comes_from_the_situation_you_describe_here_you_pi_35598a))
                }
            }
        }

        if (pickingPartner) {
            PartnerPickerSheet(
                host = host,
                language = targetLanguage,
                current = partner,
                onPick = { partner = it; pickingPartner = false },
                onDismiss = { pickingPartner = false },
            )
        }

        // The plans, when the CTA can't be paid for — from HERE, so the sheet
        // (and the situation in it) survives being told no.
        if (showPaywall) {
            Dialog(
                onDismissRequest = { showPaywall = false },
                properties = DialogProperties(usePlatformDefaultWidth = false),
            ) { PaywallScreen(onDismiss = { showPaywall = false }) }
        }
    }
}

/**
 * What `Scenario.role` should say for an attached person. Your OWN people
 * carry their relationship ("my landlord") — the scene is about them. A
 * character or a pool stranger carries NOTHING: the situation casts the role
 * and the person plays it, their identity riding in the prompt's counterpart
 * block. Empty = the scene infers its own counterpart.
 */
private fun roleLine(who: Counterpart?): String {
    if (who == null) return ""
    if (who.remoteId != null) return ""
    return who.relationship.ifBlank { who.name }
}

private fun partnerCaptionOf(p: Counterpart): String {
    val rid = p.remoteId
    if (rid != null && rid.startsWith("builtin:")) return StockPerson.by(p.voicePresetId).identity
    if (rid == null) return p.relationship
    return p.location
}

@Composable
private fun partnerCaption(p: Counterpart?): String =
    if (p == null) stringResource(R.string.your_own_voice_already_fluent)
    else partnerCaptionOf(p)

// MARK: - Rows and chips

@Composable
private fun PersonRow(p: Counterpart) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(40.dp)
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Text(initials(p.name), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text(p.name, style = MaterialTheme.typography.bodyLarge)
            if (p.relationship.isNotBlank()) {
                Text(p.relationship, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
    }
}

@Composable
private fun PartnerAvatar(p: Counterpart?) {
    Box(
        Modifier.size(40.dp)
            .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.15f), CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        if (p == null) {
            // The fluent self has no face — it is a voice.
            Icon(Icons.Filled.GraphicEq, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(20.dp))
        } else {
            Text(initials(p.name), style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary)
        }
    }
}

@Composable
private fun CrumbChip(label: String, icon: String?, selected: Boolean, onClick: () -> Unit) {
    Row(
        Modifier.clip(CircleShape)
            .background(
                if (selected) MaterialTheme.colorScheme.primary.copy(alpha = 0.15f)
                else MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.6f))
            .clickable(onClick = onClick)
            .padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        if (icon != null) {
            Icon(Symbols.icon(icon), contentDescription = null,
                tint = if (selected) MaterialTheme.colorScheme.primary
                else MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(14.dp))
        }
        Text(label, style = MaterialTheme.typography.labelLarge, maxLines = 1,
            color = if (selected) MaterialTheme.colorScheme.primary
            else MaterialTheme.colorScheme.onSurface)
    }
}

/**
 * Two equal columns, not wrap-to-fit: iOS lays these on an adaptive grid, so
 * the tiles line up down the page instead of stepping in and out with the
 * length of each phrase. A LazyVerticalGrid can't nest in a scrolling column,
 * and these lists are six items long — chunked rows are the honest shape.
 */
@Composable
private fun ChoiceGrid(items: List<Pair<String, String?>>, onPick: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.withIndex().chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { (i, item) ->
                    Row(
                        Modifier.weight(1f)
                            .fillMaxHeight()
                            .heightIn(min = 46.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            .clickable { onPick(i) }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        item.second?.let {
                            Icon(Symbols.icon(it), contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(18.dp))
                        }
                        Text(item.first, style = MaterialTheme.typography.bodyMedium,
                            maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun SkeletonGrid() {
    val fractions = listOf(0.72f, 0.48f, 0.63f, 0.80f, 0.55f, 0.68f)
    val transition = rememberInfiniteTransition(label = "skeleton")
    val pulse by transition.animateFloat(
        initialValue = 0.45f, targetValue = 0.9f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "pulse")
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        fractions.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { f ->
                    Box(
                        Modifier.weight(1f).height(46.dp)
                            .clip(RoundedCornerShape(12.dp))
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            .padding(horizontal = 12.dp),
                        contentAlignment = Alignment.CenterStart,
                    ) {
                        Box(
                            Modifier.fillMaxWidth(f).height(9.dp).alpha(pulse)
                                .clip(CircleShape)
                                .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.25f)))
                    }
                }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

@Composable
private fun DictationLanguageRow(current: String, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    // The learner's own language and the one they are practising first, then
    // everything else: someone Japanese living in Germany learning English
    // may find it easiest to say the situation in German, and being told to
    // pick one of two is just a wall.
    val choices = remember { LanguageCatalog.nativeChoices() }
    Box {
        Row(
            Modifier.clip(CircleShape).clickable { open = true }.padding(horizontal = 4.dp, vertical = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(LanguageCatalog.endonym(current),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant)
            Icon(Icons.Filled.UnfoldMore,
                contentDescription = stringResource(R.string.language),
                tint = MaterialTheme.colorScheme.outline,
                modifier = Modifier.size(16.dp))
        }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            choices.forEach { code ->
                DropdownMenuItem(
                    text = { Text(LanguageCatalog.endonym(code)) },
                    onClick = { onPick(code); open = false })
            }
        }
    }
}

// MARK: - Partner picker

/**
 * Pick WHO the other side is, from the same people system everything else
 * uses: the learner's own people, real users from the Find-people pool, and
 * characters. Talk also offers "Future self" — a call with nobody attached is
 * a call with your own fluent voice.
 *
 * Own people and the built-in characters render instantly; the pool streams
 * in and quietly stays absent offline.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PartnerPickerSheet(
    host: ComposerHost,
    language: String,
    current: Counterpart?,
    onPick: (Counterpart?) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    var known by remember { mutableStateOf<List<Counterpart>>(emptyList()) }
    var pool by remember { mutableStateOf<List<PublicPersonaClient.PublicPersona>>(emptyList()) }
    var poolLoading by remember { mutableStateOf(true) }
    LaunchedEffect(language) {
        known = CounterpartStore.shared(context).load()
        pool = runCatching { PublicPersonaClient(AuthRepository()).fetchPool(language) }
            .getOrDefault(emptyList())
        poolLoading = false
    }
    // A person already on disk is reused rather than minted again, so picking
    // the same character twice can never leave two rows behind.
    val existing = known
    val own = remember(known) { known.filter { it.remoteId == null } }
    val characters = remember(pool, known) {
        val builtins = StockPerson.catalog.map { it.asCounterpart(existing) }
        val fetched = pool.filter { !it.isRealUser }.map { it.asCounterpart(existing) }
        val seen = builtins.map { it.id }.toMutableSet()
        builtins + fetched.filter { seen.add(it.id) }
    }
    val users = remember(pool, known) {
        pool.filter { it.isRealUser }.map { it.asCounterpart(existing) }
    }

    ModalBottomSheet(onDismissRequest = onDismiss, containerColor = AppSurfaces.ground) {
        Column(
            Modifier.fillMaxWidth().bottomBarInsets()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 32.dp),
        ) {
            Text(stringResource(R.string.the_other_person),
                style = MaterialTheme.typography.titleLarge,
                modifier = Modifier.padding(bottom = 4.dp))
            if (host == ComposerHost.TALK) {
                GroupedSectionSpacer()
                GroupedCard {
                    PickerRow(
                        name = stringResource(R.string.future_self_1384d5),
                        caption = stringResource(R.string.your_own_voice_already_fluent),
                        person = null,
                        selected = current == null,
                    ) { onPick(null) }
                }
            }
            if (own.isNotEmpty()) {
                GroupedSectionHeader(stringResource(R.string.your_people))
                GroupedCard {
                    own.forEachIndexed { i, p ->
                        if (i > 0) GroupedRowDivider()
                        PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                    }
                }
            }
            if (users.isNotEmpty() || poolLoading) {
                GroupedSectionHeader(stringResource(R.string.people))
                GroupedCard {
                    users.forEachIndexed { i, p ->
                        if (i > 0) GroupedRowDivider()
                        PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                    }
                    if (poolLoading && users.isEmpty()) {
                        Row(
                            Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            CircularProgressIndicator(Modifier.size(14.dp), strokeWidth = 2.dp)
                            Text(stringResource(R.string.finding_people),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
            GroupedSectionHeader(stringResource(R.string.characters))
            GroupedCard {
                characters.forEachIndexed { i, p ->
                    if (i > 0) GroupedRowDivider()
                    PickerRow(p.name, partnerCaptionOf(p), p, current?.id == p.id) { onPick(p) }
                }
            }
        }
    }
}

@Composable
private fun PickerRow(
    name: String,
    caption: String,
    person: Counterpart?,
    selected: Boolean,
    onClick: () -> Unit,
) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PartnerAvatar(person)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(name, style = MaterialTheme.typography.bodyLarge)
            if (caption.isNotBlank()) {
                Text(caption, style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (selected) {
            Icon(Icons.Filled.Check, contentDescription = null,
                tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
        }
    }
}

// MARK: - Materializing a person

/** A built-in character as an ordinary person — reusing the row already on
 *  disk when there is one, so picking the same character twice is one row. */
private fun StockPerson.asCounterpart(existing: List<Counterpart>): Counterpart {
    val rid = "builtin:$voiceId"
    existing.firstOrNull { it.remoteId == rid }?.let { return it }
    return Counterpart(
        name = name,
        intro = identity,
        voicePresetId = voiceId,
        remoteId = rid,
        personaKind = "character",
    )
}

/** A pool persona as an ordinary person. Their voice is never a clone — the
 *  person on the other end is a stranger, not the fluent self. */
private fun PublicPersonaClient.PublicPersona.asCounterpart(existing: List<Counterpart>): Counterpart {
    existing.firstOrNull { it.remoteId == id }?.let { return it }
    return Counterpart(
        name = display_name,
        location = location,
        conversationStyle = conversation_style,
        commonTopics = interests,
        intro = intro,
        voicePresetId = voice_preset_id,
        remoteId = id,
        personaKind = if (isRealUser) "user" else "character",
    )
}
