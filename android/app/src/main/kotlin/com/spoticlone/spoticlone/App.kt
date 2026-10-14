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

        // Blocks the CALLING (background) thread until Python is ready.
        // Never call from the UI thread.
        fun ensurePython(context: Context) {
            if (!Python.isStarted()) {
                // Fallback in case onCreate's thread hasn't started it.
                synchronized(this) {
                    if (!Python.isStarted()) {
                        Python.start(
                            AndroidPlatform(context.applicationContext))
                        ready.countDown()
                    }
                }
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
                if (!Python.isStarted()) {
                    Python.start(AndroidPlatform(this))
                }
            } catch (e: Exception) {
                android.util.Log.e("Spoticlone", "Python.start failed", e)
            } finally {
                markReady()
            }
        }, "chaquopy-starter").start()
    }
}
