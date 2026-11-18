package com.roro.futurevoice

import com.roro.futurevoice.data.PromiseLedger
import com.roro.futurevoice.data.StudyPlan
import com.roro.futurevoice.sync.InMemorySyncTransport
import com.roro.futurevoice.sync.RoutineSync
import com.roro.futurevoice.sync.SyncEngine
import com.roro.futurevoice.sync.SyncKind
import com.roro.futurevoice.sync.SyncKindHandler
import com.roro.futurevoice.sync.SyncRegistry
import com.roro.futurevoice.sync.SyncSettings
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * A build that couldn't read the routine skipped its record while its change
 * token moved past it. The build that can read it must still fetch it once,
 * without re-listing everything (`SyncEngine.CATCH_UP_KINDS`).
 */
class RoutineCatchUpTest {

    private class Settings : SyncSettings {
        val enabled = HashSet<String>()
        override fun isEnabled(userId: String) = userId in enabled
        override fun setEnabled(userId: String, on: Boolean) { if (on) enabled.add(userId) else enabled.remove(userId) }
        override fun lastUser(): String? = null
        override fun setLastUser(id: String?) {}
        override fun setLastSyncAt(userId: String, at: Long) {}
        override fun quotaHitAt(userId: String): Long? = null
        override fun setQuotaHitAt(userId: String, at: Long?) {}
    }

    private class Device(var plan: StudyPlan?, knowsRoutine: Boolean,
                         var days: Map<String, PromiseLedger.Entry> = emptyMap()) : SyncRegistry {
        private val list: List<SyncKindHandler> = if (knowsRoutine) listOf(
            RoutineSync.PlanKind(current = { plan ?: StudyPlan() }, adopt = { plan = it }),
            RoutineSync.PromiseKind(current = { days }, replace = { days = it }))
        else emptyList()
        override fun all() = list
        override fun handler(kind: SyncKind) = list.firstOrNull { it.kind == kind }
        override fun enrolledLanguages() = listOf("en")
        override fun cardSessionId(payload: String): String? = null
        override fun deleteTurnAudio(turnIds: List<String>) {}
        override fun newestVoiceSample(): File? = null
    }

    @Test
    fun aRoutineSkippedByAnOlderBuildArrivesOnce() = runBlocking {
        val cloud = InMemorySyncTransport()
        val mine = StudyPlan(
            blocks = listOf(StudyPlan.Block(kind = StudyPlan.Kind.TALK, weekdays = setOf(2, 3), hour = 8, minute = 0, minutes = 15)),
            streakSince = 1_793_545_200_000L, editedAt = 1_794_971_045_000L)

        // The Mac pushes its routine.
        val macRoot = Files.createTempDirectory("mac").toFile()
        val mac = SyncEngine(Settings(), cloud, Device(mine, knowsRoutine = true), macRoot, deliver = { it() })
        mac.setUser("user-1"); mac.enable(); mac.syncAndWait(null)

        // The phone on the old build: pulls, can't name the kind, token moves on.
        val phoneRoot = Files.createTempDirectory("phone").toFile()
        val settings = Settings()
        val old = SyncEngine(settings, cloud, Device(null, knowsRoutine = false), phoneRoot, deliver = { it() })
        old.setUser("user-1"); old.enable(); old.syncAndWait(null)

        // The phone updates, holding the routine it seeded on install. Nothing
        // new on the server, yet the Mac's routine lands and the seed loses.
        val seed = StudyPlan(isSeed = true)
        val phone = Device(seed, knowsRoutine = true)
        val new = SyncEngine(settings, cloud, phone, phoneRoot, deliver = { it() })
        new.setUser("user-1")
        new.syncAndWait(null); mac.syncAndWait(null); new.syncAndWait(null)
        assertEquals(RoutineSync.planPayload(mine), phone.plan?.let(RoutineSync::planPayload))

        // And the two stop pushing.
        val before = cloud.saved
        new.syncAndWait(null); mac.syncAndWait(null); new.syncAndWait(null)
        assertEquals(before, cloud.saved)
    }

    @Test
    fun promiseDaysSkippedByAnOlderBuildArriveWithoutTheMacPushingAgain() = runBlocking {
        val cloud = InMemorySyncTransport()
        val kept = PromiseLedger.Entry(2, 1, true, keptAt = 1_794_916_800_000L, touched = 1, rule = 3)
        val mac = SyncEngine(Settings(), cloud, Device(StudyPlan(isSeed = true), true, mapOf("2026-11-10" to kept)),
            Files.createTempDirectory("mac").toFile(), deliver = { it() })
        mac.setUser("user-1"); mac.enable(); mac.syncAndWait(null)

        val phoneRoot = Files.createTempDirectory("phone").toFile()
        val settings = Settings()
        val old = SyncEngine(settings, cloud, Device(null, false), phoneRoot, deliver = { it() })
        old.setUser("user-1"); old.enable(); old.syncAndWait(null)

        val own = PromiseLedger.Entry(2, 0, true, touched = 0, rule = 3)
        val phone = Device(StudyPlan(isSeed = true), true, mapOf("2026-11-11" to own))
        val new = SyncEngine(settings, cloud, phone, phoneRoot, deliver = { it() })
        new.setUser("user-1")
        new.syncAndWait(null)
        assertEquals(mapOf("2026-11-10" to kept, "2026-11-11" to own), phone.days)
    }
}
