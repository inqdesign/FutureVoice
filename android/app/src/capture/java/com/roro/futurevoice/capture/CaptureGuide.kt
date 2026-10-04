package com.roro.futurevoice.capture

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.roro.futurevoice.data.PageIntroStore
import com.roro.futurevoice.ui.AppGuidePage
import com.roro.futurevoice.ui.PageIntro
import com.roro.futurevoice.ui.PageIntroSheet
import com.roro.futurevoice.ui.brand.AppSurfaces

/**
 * The tab guides (iOS `PageIntroSheet`, `e4bcd83` · `0d11490` · `e864003`):
 *
 *   app-guide               Me → App guide, every guide in one list
 *   page-intro-<page>       a guide's first page (talk · watch · review ·
 *   page-intro-<page>-<n>   progress · routine), and its later pages
 *
 * iOS raises the sheet over the tab it introduces; here it rises over the
 * plain page ground, like the other sheet captures.
 */
object CaptureGuide {
    private fun intro(page: PageIntroStore.Page, step: Int): @Composable (Context) -> Unit = {
        Box(Modifier.fillMaxSize().background(AppSurfaces.ground)) {
            PageIntroSheet(page, initialStep = step, onDismiss = {})
        }
    }

    val wired: Map<String, @Composable (Context) -> Unit> = buildMap {
        put("app-guide") { _ -> AppGuidePage(onBack = {}) }
        PageIntroStore.Page.entries.forEach { page ->
            put("page-intro-${page.raw}", intro(page, 0))
            for (n in 1..PageIntro.stepCount(page)) put("page-intro-${page.raw}-$n", intro(page, n - 1))
        }
    }
}
