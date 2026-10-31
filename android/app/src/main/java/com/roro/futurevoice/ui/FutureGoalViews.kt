package com.roro.futurevoice.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.RadioButtonUnchecked
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.roro.futurevoice.R
import com.roro.futurevoice.data.FutureGoal
import com.roro.futurevoice.data.LearningPurpose
import com.roro.futurevoice.data.LearningPurposeStore
import com.roro.futurevoice.talk.UserPersona
import com.roro.futurevoice.ui.brand.AppSurfaces
import com.roro.futurevoice.ui.brand.IosGlassTextButton

/**
 * The goals under each picked purpose, as tick rows — setup's "Imagine your
 * future" step and the Me → Profile editor draw the same rows (iOS
 * `FutureGoalRows`). As many as the learner likes.
 */
@Composable
fun FutureGoalRows(
    purposes: List<LearningPurpose>,
    picked: List<FutureGoal>,
    onPicked: (List<FutureGoal>) -> Unit,
) {
    purposes.forEach { purpose ->
        GroupedSectionHeader(stringResource(purpose.title))
        GroupedCard {
            FutureGoal.options(purpose).forEachIndexed { i, goal ->
                if (i > 0) FormDivider(inset = 52.dp)
                FutureGoalRow(goal, on = goal in picked) {
                    onPicked(if (goal in picked) picked - goal else picked + goal)
                }
            }
        }
    }
}

@Composable
private fun FutureGoalRow(goal: FutureGoal, on: Boolean, onToggle: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = onToggle)
            .semantics { selected = on }
            .padding(horizontal = 16.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(
            if (on) Icons.Filled.CheckCircle else Icons.Filled.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (on) MaterialTheme.colorScheme.primary else tertiaryLabel(),
            modifier = Modifier.size(24.dp),
        )
        Text(stringResource(goal.title), style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurface, modifier = Modifier.weight(1f))
    }
}

/**
 * Me → Profile: change the goals later (iOS `FutureGoalsEditor`). Shows the
 * purposes the learner picked, or every purpose when there are none on file.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FutureGoalsEditorSheet(
    persona: UserPersona?,
    onSave: (UserPersona) -> Unit,
    onDismiss: () -> Unit,
) {
    val context = LocalContext.current
    // Seeded once, like iOS's `onAppear`.
    var picked by remember { mutableStateOf(persona?.futureGoals.orEmpty()) }
    val purposes = remember {
        val list = LearningPurposeStore.purposes(context).toMutableList()
        // A goal already on file keeps its purpose on screen.
        persona?.futureGoals.orEmpty().forEach { if (it.purpose !in list) list += it.purpose }
        if (list.isEmpty()) LearningPurpose.entries.toList() else list
    }

    fun save() {
        val p = persona ?: run { onDismiss(); return }
        onSave(p.copy(goals = picked.map { it.raw }, updatedAt = System.currentTimeMillis()))
        onDismiss()
    }

    ModalBottomSheet(
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        onDismissRequest = onDismiss,
        containerColor = AppSurfaces.ground,
    ) {
        SheetHeader(
            title = stringResource(R.string.my_future),
            leading = { IosGlassTextButton(stringResource(R.string.cancel), onClick = onDismiss) },
            trailing = { IosGlassTextButton(stringResource(R.string.save), onClick = { save() }, bold = true) },
            modifier = Modifier.padding(horizontal = 16.dp).padding(top = 4.dp, bottom = 8.dp),
        )
        Column(Modifier.fillMaxWidth().bottomBarInsets().verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp).padding(bottom = 28.dp)) {
            FutureGoalRows(purposes, picked) { picked = it }
            GroupedFooter(stringResource(R.string.pick_as_many_as_you_like_your_fluent_self_already_lives_them))
        }
    }
}
