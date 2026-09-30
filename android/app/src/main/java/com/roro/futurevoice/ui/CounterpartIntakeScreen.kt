package com.roro.futurevoice.ui

import android.graphics.Bitmap
import com.roro.futurevoice.ui.brand.ContinuousShape
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.Counterpart
import com.roro.futurevoice.data.LanguageCatalog
import com.roro.futurevoice.talk.CounterpartParser
import com.roro.futurevoice.talk.PublicFigureLookup
import com.roro.futurevoice.ui.brand.AppSurfaces
import kotlinx.coroutines.launch

/**
 * Guided new-person flow, one card per category (iOS
 * `CounterpartVoiceIntakeView`). Name is typed, the relationship is a chip
 * pick, and the relationship then TAILORS the three narrative cards (a fellow
 * Kita parent is asked about the kids; a manager about 1:1s). Narrative cards
 * are tap-first — common answers as chips plus a speak-or-type field for what
 * a chip can't say; picks and narration merge into one answer, parsed into a
 * draft that lands in the form prefilled. "Rather just fill in a form?" stays
 * for anyone who'd rather type fields.
 *
 * The copy is English, exactly as iOS ships it: none of these lines is in the
 * iOS catalog either, so translating them is one job for both platforms.
 * Chip VALUES stay English on purpose — they are what the parser reads, and it
 * writes the profile in the learner's own language whatever it is handed.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CounterpartIntakeScreen(
    nativeLanguage: String,
    targetLanguage: String,
    /** The parsed draft (or null for the plain form) and the photo picked on
     *  the first card — the person doesn't exist yet, so it rides along. */
    onDraft: (Counterpart?, Bitmap?) -> Unit,
    onCancel: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    var step by remember { mutableStateOf(Step.WHO) }
    androidx.activity.compose.BackHandler {
        if (step == Step.WHO) onCancel() else step = Step.entries[step.ordinal - 1]
    }
    var name by remember { mutableStateOf("") }
    var kind by remember { mutableStateOf<RelationshipKind?>(null) }
    var kindDetail by remember { mutableStateOf("") }
    val answers = remember { mutableStateListOf("", "", "") }
    val chips = remember { mutableStateListOf<Set<String>>(emptySet(), emptySet(), emptySet()) }
    var interests by remember { mutableStateOf<Set<String>>(emptySet()) }
    var styleTraits by remember { mutableStateOf<Set<String>>(emptySet()) }
    var styleNotes by remember { mutableStateOf("") }
    var photo by remember { mutableStateOf<Bitmap?>(null) }
    var parsing by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    // Answered IN the learner's own language by default: that's where people
    // say the most about someone they know.
    val locale = remember { LanguageCatalog.sttLocale(nativeLanguage) }

    val canAdvance = when (step) {
        Step.WHO -> name.isNotBlank()
        Step.RELATIONSHIP -> kind != null
        else -> true
    }

    fun parseAndContinue() {
        scope.launch {
            parsing = true; error = null
            val k = kind ?: RelationshipKind.OTHER
            val kindLabel = listOf(k.label, kindDetail).filter { it.isNotBlank() }.joinToString(" — ")
            val styleLine = (styleTraits.joinToString(", ") +
                if (styleNotes.isBlank()) "" else ". $styleNotes").trim()
            val sections = mutableListOf("Their name: ${name.trim()}")
            if (kindLabel.isNotEmpty()) sections += "Relationship to me: $kindLabel"
            k.cards.forEachIndexed { i, card ->
                // Chip picks + whatever was spoken or typed form ONE answer.
                val parts = buildList {
                    if (chips[i].isNotEmpty()) add(chips[i].joinToString(", "))
                    answers[i].trim().takeIf { it.isNotEmpty() }?.let(::add)
                }
                if (parts.isNotEmpty()) sections += "Q: ${card.question}\nA: ${parts.joinToString(". ")}"
            }
            if (interests.isNotEmpty()) sections += "What they're into: ${interests.joinToString(", ")}"
            if (styleLine.isNotEmpty()) sections += "How they talk: $styleLine"
            val relationshipFallback = kindDetail.ifBlank { k.label }
            try {
                val draft = when {
                    // A public figure is looked up whatever was said: the
                    // profile comes from coverage, not from the cards.
                    k == RelationshipKind.PUBLIC_FIGURE -> PublicFigureLookup.lookUp(
                        Counterpart(name = name.trim(), relationship = kindDetail,
                            howWeMet = sections.drop(2).joinToString("\n\n"),
                            commonTopics = interests.joinToString(", "),
                            conversationStyle = styleLine,
                            isPublicFigure = true),
                        nativeLanguage, targetLanguage)
                    // Nothing to extract — skip the model, straight to the form.
                    answers.all { it.isBlank() } && chips.all { it.isEmpty() } -> Counterpart(
                        name = name.trim(), relationship = relationshipFallback,
                        conversationStyle = styleLine, commonTopics = interests.joinToString(", "))
                    else -> CounterpartParser.parse(sections.joinToString("\n\n"), locale, nativeLanguage)
                        .copy(name = name.trim())
                }
                // The relationship card was required, so there always is one —
                // but the parser won't invent, and an empty relationship leaves
                // the form's Save greyed out.
                onDraft(draft.copy(
                    relationship = draft.relationship.ifBlank { relationshipFallback }), photo)
            } catch (e: Exception) {
                error = "Couldn't parse: ${e.message.orEmpty()}"
            } finally {
                parsing = false
            }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = AppSurfaces.topBarColors(),
                title = { Text(stringResource(R.string.tell_me_about_them)) },
                navigationIcon = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) } },
            )
        },
        bottomBar = {
            Row(Modifier.fillMaxWidth().bottomBarInsets().padding(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                if (step != Step.WHO) OutlinedButton(
                    onClick = { step = Step.entries[step.ordinal - 1] },
                    modifier = Modifier.weight(1f),
                ) { Text(stringResource(R.string.back)) }
                Button(
                    enabled = canAdvance && !parsing,
                    onClick = {
                        if (step == Step.STYLE) parseAndContinue()
                        else step = Step.entries[step.ordinal + 1]
                    },
                    modifier = Modifier.weight(1f),
                ) {
                    if (parsing) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
                    else Text(stringResource(if (step == Step.STYLE) R.string.continue_ else R.string.next))
                }
            }
        },
    ) { padding ->
        Column(
            Modifier.padding(padding).fillMaxSize().background(AppSurfaces.ground)
                .padding(horizontal = 20.dp).verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            LinearProgressIndicator(progress = { (step.ordinal + 1f) / Step.entries.size },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp))
            when (step) {
                Step.WHO -> {
                    StepHeader("Who are we adding?",
                        "Someone you actually talk to — dialogues get simulated with them, in their manner.")
                    // Their face, optional; saved small and square with the
                    // person, never sent anywhere.
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        PersonPhotoButton(onImage = { photo = it },
                            onRemove = if (photo == null) null else ({ photo = null })) {
                            PersonBubble(name = name, photoId = null, size = 88.dp,
                                photo = photo?.asImageBitmap())
                        }
                        Text("A photo is optional. Without one, their initials stand in.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    OutlinedTextField(value = name, onValueChange = { name = it }, singleLine = true,
                        label = { Text(stringResource(R.string.their_name_as_you_call_them)) },
                        modifier = Modifier.fillMaxWidth())
                    TextButton(onClick = { onDraft(null, photo) }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.rather_just_fill_in_a_form),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Step.RELATIONSHIP -> {
                    StepHeader("Who are they to you?",
                        "This shapes what I ask next — a manager and a best friend live in different worlds.")
                    Card {
                        ChipPicker(RelationshipKind.entries.map { it.label },
                            setOfNotNull(kind?.label), allowsCustom = false) { tag ->
                            kind = RelationshipKind.entries.first { it.label == tag }
                        }
                        OutlinedTextField(value = kindDetail, onValueChange = { kindDetail = it },
                            singleLine = true, placeholder = { Text("More precisely? — e.g. College roommate") },
                            modifier = Modifier.fillMaxWidth())
                    }
                    if (kind == RelationshipKind.PUBLIC_FIGURE) {
                        Text("A public figure's profile is filled from public coverage — where they're from, what they're known for, how they talk in interviews. Their voice is a preset, never their real one.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                Step.NARRATIVE1, Step.NARRATIVE2, Step.NARRATIVE3 -> {
                    val i = step.ordinal - Step.NARRATIVE1.ordinal
                    val card = (kind ?: RelationshipKind.OTHER).cards[i]
                    StepHeader(card.question, card.detail)
                    ChipPicker(card.chips, chips[i], allowsCustom = true) { tag ->
                        chips[i] = if (tag in chips[i]) chips[i] - tag else chips[i] + tag
                    }
                    SpeakOrTypeField(
                        text = answers[i], onText = { answers[i] = it },
                        usedVoice = false, onUsedVoice = {},
                        placeholder = "Anything more? Type — or tap the mic and talk.",
                        locale = locale,
                    )
                }
                Step.INTERESTS -> {
                    StepHeader(if (name.isBlank()) "What are they into?" else "What's ${name.trim()} into?",
                        "Tap what fits — these become what you two talk about.")
                    ChipPicker(INTEREST_PRESETS, interests, allowsCustom = true) { tag ->
                        interests = if (tag in interests) interests - tag else interests + tag
                    }
                }
                Step.STYLE -> {
                    StepHeader(if (name.isBlank()) "How do they talk?" else "How does ${name.trim()} talk?",
                        "Tap what fits — the simulated ${name.trim().ifBlank { "person" }} should sound like the real one.")
                    ChipPicker(STYLE_PRESETS, styleTraits, allowsCustom = false) { tag ->
                        styleTraits = if (tag in styleTraits) styleTraits - tag else styleTraits + tag
                    }
                    OutlinedTextField(value = styleNotes, onValueChange = { styleNotes = it },
                        minLines = 2, maxLines = 4,
                        placeholder = { Text("In your own words (optional) — e.g. switches to English when excited") },
                        modifier = Modifier.fillMaxWidth())
                }
            }
            error?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
            }
            Box(Modifier.size(8.dp))
        }
    }
}

private enum class Step { WHO, RELATIONSHIP, NARRATIVE1, NARRATIVE2, NARRATIVE3, INTERESTS, STYLE }

@Composable
private fun StepHeader(question: String, detail: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(question, style = MaterialTheme.typography.titleLarge)
        if (detail.isNotEmpty()) Text(detail, style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun Card(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth()
        .background(MaterialTheme.colorScheme.surface, ContinuousShape(12.dp)).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) { content() }
}

/** Common answers as chips; with [allowsCustom], a row to add one's own
 *  (iOS `ChipPickerField`). Custom picks show as chips beside the presets. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ChipPicker(presets: List<String>, selection: Set<String>, allowsCustom: Boolean,
                       onToggle: (String) -> Unit) {
    var custom by remember { mutableStateOf("") }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (presets + selection.filter { it !in presets }).forEach { tag ->
                FilterChip(selected = tag in selection, onClick = { onToggle(tag) }, label = { Text(tag) })
            }
        }
        if (allowsCustom) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(value = custom, onValueChange = { custom = it }, singleLine = true,
                    placeholder = { Text(stringResource(R.string.add)) },
                    modifier = Modifier.weight(1f))
                IconButton(enabled = custom.isNotBlank(), onClick = {
                    val t = custom.trim()
                    if (t !in selection) onToggle(t)
                    custom = ""
                }) { Icon(Icons.Filled.Add, contentDescription = null) }
            }
        }
    }
}

private val STYLE_PRESETS = listOf(
    "Direct", "Playful", "Sarcastic", "Formal", "Warm",
    "Talkative", "Quiet", "Blunt", "Fast talker", "Careful",
)

// `PersonaOnboardingView.interestPresets` — the same list the learner's own
// intake offers.
private val INTEREST_PRESETS = listOf(
    "AI / tech", "parenting", "language learning", "music", "podcasts",
    "cooking", "travel", "sports", "fashion", "finance", "science", "art",
)

private const val TAP_OR_TALK = "Tap what fits, add your own — or just talk, your native language is fine."
private const val REAL = "This is what makes the dialogues feel real."

private class NarrativeCard(val question: String, val detail: String, val chips: List<String>)

/** Card 2's pick — each kind supplies the three narrative cards that follow
 *  (iOS `RelationshipKind`). Adding a kind or reworking copy happens only here. */
private enum class RelationshipKind(val label: String, val cards: List<NarrativeCard>) {
    FRIEND("Friend", listOf(
        NarrativeCard("How did you two meet?", TAP_OR_TALK, listOf("From school", "From work", "Through friends", "Online", "Childhood friends", "Met recently")),
        NarrativeCard("What's their life like right now?", "", listOf("Works full-time", "Studying", "Recently moved", "Raising kids", "Lives nearby", "Lives abroad")),
        NarrativeCard("What's just between you two?", REAL, listOf("Inside jokes", "We tease each other", "Deep talks", "Mostly banter", "Shared hobby", "They know everything about me")))),
    FAMILY("Family", listOf(
        NarrativeCard("Who are they in your family?", TAP_OR_TALK, listOf("Older sibling", "Younger sibling", "Parent", "Grandparent", "Cousin", "In-law")),
        NarrativeCard("What's going on in their life?", "", listOf("Busy with work", "Retired", "New hobby", "Just moved", "Raising kids", "Health ups and downs")),
        NarrativeCard("What do you two usually talk about?", REAL, listOf("Family news", "Food and recipes", "Health", "Old memories", "Money and plans", "They nag me lovingly")))),
    PARTNER("Partner", listOf(
        NarrativeCard("How did your story start?", TAP_OR_TALK, listOf("Together for years", "Newly dating", "Met through friends", "Met online", "Living together", "Long distance")),
        NarrativeCard("What fills your conversations these days?", "", listOf("Daily logistics", "Future plans", "Food and cooking", "Travel plans", "Work stories", "Our pets")),
        NarrativeCard("What's your dynamic like?", REAL, listOf("Playful teasing", "Pet names", "Lots of inside jokes", "Calm and cozy", "We debate everything", "They call me out")))),
    COWORKER("Coworker", listOf(
        NarrativeCard("How do you work together?", TAP_OR_TALK, listOf("Same team", "Cross-team", "We share projects", "Desk neighbors", "Worked together for years", "They're new")),
        NarrativeCard("What do your work chats look like?", "", listOf("Daily standups", "Reviews", "Lunch together", "Coffee breaks", "Mostly chat apps", "Casual between us")),
        NarrativeCard("What's the context around you two?", REAL, listOf("Deadline crunch", "Office jokes", "New project starting", "We vent together", "After-work drinks", "Company changes going on")))),
    MANAGER("Manager", listOf(
        NarrativeCard("What's your working relationship?", TAP_OR_TALK, listOf("My direct manager", "Weekly 1:1s", "Manager for years", "New to me", "Skip-level", "We talk daily")),
        NarrativeCard("What do you usually discuss?", "", listOf("Project updates", "Feedback", "Career growth", "Priorities", "Pretty formal", "Fairly casual")),
        NarrativeCard("What else should I know about them?", REAL, listOf("Direct style", "Supportive", "Detail-oriented", "Big-picture person", "Busy calendar", "Knows my life a bit")))),
    FELLOW_PARENT("Fellow parent", listOf(
        NarrativeCard("How are your families connected?", TAP_OR_TALK, listOf("Same Kita", "Same school", "Same class", "Playground friends", "Kids are best friends", "Known for years")),
        NarrativeCard("Where do you usually run into each other?", "", listOf("Drop-off", "Pick-up", "Playdates", "Birthday parties", "School events", "The playground")),
        NarrativeCard("What do you two talk about?", REAL, listOf("The kids", "School news", "Logistics and schedules", "Weekend plans", "Parenting tips", "Neighborhood news")))),
    NEIGHBOR("Neighbor", listOf(
        NarrativeCard("How did you become neighbors?", TAP_OR_TALK, listOf("Next door", "Same building", "Same street", "Neighbors for years", "I moved in recently", "They moved in recently")),
        NarrativeCard("Where do your chats happen?", "", listOf("Hallway", "Elevator", "Garden or yard", "On the street", "Neighborhood events", "Walking the dog")),
        NarrativeCard("What do you usually talk about?", REAL, listOf("Neighborhood news", "The weather", "Their family", "Pets", "Home projects", "We trade favors")))),
    TEACHER("Teacher", listOf(
        NarrativeCard("Whose teacher — and of what?", TAP_OR_TALK, listOf("My teacher", "My kid's teacher", "Language teacher", "Music teacher", "Sports coach", "Known for a while")),
        NarrativeCard("When do you talk with them?", "", listOf("In class", "Office hours", "Parent meetings", "Over messages", "Pretty formal", "Fairly relaxed")),
        NarrativeCard("What else should I know about them?", REAL, listOf("Strict but fair", "Encouraging", "Patient", "Talks fast", "Recent school events", "I want to ask more questions")))),
    /** Someone not in the learner's life — its own kind, not "Other": the
     *  profile is the public record, not the learner's guess. */
    PUBLIC_FIGURE("Public figure", listOf(
        NarrativeCard("Why this person?", TAP_OR_TALK, listOf("Fan for years", "Their music", "Their films or shows", "Their sport", "Their interviews", "They're why I'm learning this language")),
        NarrativeCard("Where would you meet them?", "The scene is built around this moment.", listOf("Fan meeting", "An interview", "Backstage", "At the airport", "By chance, in a cafe", "A signing event")),
        NarrativeCard("What would you want to say to them?", "Say it in your own language — the fluent self says it in theirs.", listOf("Thank them", "Tell them what their work meant to me", "Ask about their work", "Ask for advice", "Just say hello properly", "A question I've always had")))),
    OTHER("Other", listOf(
        NarrativeCard("How do you know each other?", TAP_OR_TALK, listOf("Through friends", "From work", "From a hobby", "From the neighborhood", "Online", "Met recently")),
        NarrativeCard("What's their life like?", "", listOf("Works full-time", "Studying", "Raising kids", "Lives nearby", "Lives abroad", "Busy lately")),
        NarrativeCard("What's the context between you?", REAL, listOf("Recurring topics", "Inside jokes", "We meet regularly", "Mostly texting", "They know my life well", "Still getting to know each other")))),
}
