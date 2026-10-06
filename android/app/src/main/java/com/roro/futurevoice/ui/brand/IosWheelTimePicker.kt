package com.roro.futurevoice.ui.brand

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.flow.distinctUntilChanged
import java.util.Locale
import kotlin.math.abs

/**
 * iOS's `DatePicker(displayedComponents: .hourAndMinute).datePickerStyle(.wheel)`
 * — the time control on the onboarding steps (`DailyCallOnboardingView`,
 * `WeeklyRhythmOnboardingView`), which iOS caps at 150 pt.
 *
 * Material's `TimePicker` dial is ~400 dp tall: on a short phone it pushed the
 * step's CTA below its own minimum height (reported: "Call me every day" drew
 * as a thin bar). A wheel is a fixed [WheelHeight] whatever the screen, which
 * is the whole reason iOS uses one there.
 *
 * Hours and minutes loop like iOS's; a 12-hour locale gets the AM/PM column,
 * placed where the locale's own pattern puts it (오전/오후 first in Korean).
 */
val WheelHeight: Dp = 150.dp
private val RowHeight: Dp = 30.dp
private const val LOOPS = 400

@Composable
fun IosWheelTimePicker(
    hour: Int,
    minute: Int,
    onChange: (hour: Int, minute: Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val locale: Locale = LocalConfiguration.current.locales[0]
    val is24 = remember(context) { DateFormat.is24HourFormat(context) }
    val ampmFirst = remember(locale) {
        DateFormat.getBestDateTimePattern(locale, "hm").trimStart().startsWith("a")
    }
    val change by rememberUpdatedState(onChange)
    val h by rememberUpdatedState(hour)
    val m by rememberUpdatedState(minute)
    val symbols = remember(locale) { java.text.DateFormatSymbols.getInstance(locale).amPmStrings }

    Box(modifier.fillMaxWidth().height(WheelHeight), contentAlignment = Alignment.Center) {
        // The selection band behind the middle row (iOS draws a grey capsule).
        Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp).height(RowHeight + 4.dp)
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f), RoundedCornerShape(8.dp)))
        Row(horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
            val ampm: @Composable () -> Unit = {
                Wheel(count = 2, value = if (hour >= 12) 1 else 0, loop = false, width = 64.dp,
                    label = { symbols[it] }) { pm ->
                    val base = h % 12
                    change(if (pm == 1) base + 12 else base, m)
                }
            }
            if (!is24 && ampmFirst) ampm()
            if (is24) {
                Wheel(count = 24, value = hour, loop = true, width = 64.dp,
                    label = { "%02d".format(it) }) { change(it, m) }
            } else {
                Wheel(count = 12, value = hour % 12, loop = true, width = 56.dp,
                    label = { if (it == 0) "12" else it.toString() }) { v ->
                    change(if (h >= 12) v + 12 else v, m)
                }
            }
            Wheel(count = 60, value = minute, loop = true, width = 64.dp,
                label = { "%02d".format(it) }) { change(h, it) }
            if (!is24 && !ampmFirst) ampm()
        }
    }
}

@Composable
private fun Wheel(
    count: Int,
    value: Int,
    loop: Boolean,
    width: Dp,
    label: (Int) -> String,
    onValue: (Int) -> Unit,
) {
    val total = if (loop) count * LOOPS else count
    val base = if (loop) count * (LOOPS / 2) else 0
    val state = rememberLazyListState(initialFirstVisibleItemIndex = base + value)
    val haptic = LocalHapticFeedback.current
    val pick by rememberUpdatedState(onValue)
    val current by rememberUpdatedState(value)
    val rowPx = with(LocalDensity.current) { RowHeight.toPx() }
    // The row in the middle is the value; padding of two rows above and below
    // puts the first visible item there.
    LaunchedEffect(state) {
        androidx.compose.runtime.snapshotFlow {
            state.firstVisibleItemIndex + if (state.firstVisibleItemScrollOffset > rowPx / 2) 1 else 0
        }.distinctUntilChanged().collect { idx ->
            val v = idx % count
            if (v != current) haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            pick(v)
        }
    }
    val side = (WheelHeight - RowHeight) / 2
    LazyColumn(
        state = state,
        flingBehavior = rememberSnapFlingBehavior(state, SnapPosition.Start),
        contentPadding = PaddingValues(vertical = side),
        modifier = Modifier.width(width).height(WheelHeight)
            .semantics { contentDescription = label(value) },
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        items(total) { i ->
            Box(Modifier.height(RowHeight).fillMaxWidth()
                .graphicsLayer {
                    val info = state.layoutInfo
                    val center = (info.viewportStartOffset + info.viewportEndOffset) / 2f
                    val item = info.visibleItemsInfo.firstOrNull { it.index == i }
                    val d = if (item == null) 1f else
                        (abs(item.offset + item.size / 2f - center) / (size.height * 2.5f)).coerceIn(0f, 1f)
                    alpha = 1f - d * 0.75f
                    val s = 1f - d * 0.12f
                    scaleX = s; scaleY = s
                    rotationX = (if (item != null && item.offset + item.size / 2f < center) 1 else -1) * d * 50f
                },
                contentAlignment = Alignment.Center) {
                Text(label(i % count), fontSize = 20.sp, textAlign = TextAlign.Center,
                    color = MaterialTheme.colorScheme.onSurface, maxLines = 1, softWrap = false)
            }
        }
    }
}
