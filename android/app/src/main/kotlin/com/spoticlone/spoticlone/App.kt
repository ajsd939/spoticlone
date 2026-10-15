package com.spoticlone.spoticlone

import android.app.Application
import android.content.Context
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// Starts Chaquopy Python on a background thread at process start.
// First launch extracts the ~100MB runtime from the APK, which must
// NEVER run on the UI thread (ANR -> process restart -> broken plugins).
class App : Application() {
    companion object {
        private val ready = CountDownLatch(1)
        private val startLock = Any()

        // Single guarded entry: both onCreate's thread and bridge
        // fallbacks funnel here, so Python.start() can never run twice
        // concurrently (double-start = native crash on cold start).
        private fun startOnce(context: Context): Boolean {
            synchronized(startLock) {
                if (!Python.isStarted()) {
                    Python.start(
                        AndroidPlatform(context.applicationContext))
                    return true
                }
                return false
            }
        }

        // Blocks the CALLING (background) thread until Python is ready.
        // Never call from the UI thread.
        fun ensurePython(context: Context) {
            try {
                startOnce(context)
            } finally {
                // Count down once overall; extra calls are harmless.
                ready.countDown()
            }
            if (!ready.await(90, TimeUnit.SECONDS)) {
                throw IllegalStateException("Timed out starting Python")
            }
        }

        internal fun markReady() = ready.countDown()
    }

    override fun onCreate() {
        super.onCreate()
        Thread({
            try {
                startOnce(this)
            } catch (e: Exception) {
                android.util.Log.e("Nocrift", "Python.start failed", e)
            } finally {
                markReady()
            }
        }, "chaquopy-starter").start()
    }
}
