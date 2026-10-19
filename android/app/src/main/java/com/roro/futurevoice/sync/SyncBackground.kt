package com.roro.futurevoice.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.NetworkType
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * iOS `SyncBackground`: a pass keeps going after the app closes. Android has
 * no `BGProcessingTask`; WorkManager's periodic work is the same promise — it
 * runs on the system's schedule (at most every 15 minutes, batched with
 * other apps), so the tablet hears about the phone's talk before it is next
 * opened, and a first sync's audio finishes without the learner holding the
 * app open. Every pass is resumable, so being cut off anywhere costs nothing.
 *
 * There is no server wake here (iOS `SyncPush`): Drive's change
 * notifications need a public webhook, and the foreground pass is the one
 * that always runs anyway; this only makes it earlier.
 */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val engine = SyncEngine.shared(applicationContext)
        engine.restoreLastUserIfNeeded()
        if (!engine.isEnabled) return Result.success()
        engine.syncAndWait(null)
        return Result.success()
    }
}

object SyncBackground {
    private const val NAME = "drive-sync"

    fun schedule(context: Context) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(
                if (SyncStore.cellularForAudio(context)) NetworkType.CONNECTED else NetworkType.UNMETERED)
            .setRequiresBatteryNotLow(true)
            .build()
        val request = PeriodicWorkRequestBuilder<SyncWorker>(30, TimeUnit.MINUTES)
            .setConstraints(constraints)
            .build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(NAME, ExistingPeriodicWorkPolicy.UPDATE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(NAME)
    }
}
