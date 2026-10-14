package com.spoticlone.spoticlone

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.chaquo.python.Python
import com.ryanheise.audioservice.AudioServiceActivity

// Bridge to yt_bridge.py (yt-dlp + ytmusicapi) over "app/yt_dlp".
// Python startup happens in App.onCreate on a background thread;
// here we only block the per-call background thread until ready.
// configureFlutterEngine itself stays instant (no ANRs).
//
// NOTE: must extend AudioServiceActivity (not plain FlutterActivity):
// audio_service verifies the activity uses its shared cached engine
// and throws "wrong FlutterEngine" in AudioService.init otherwise.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        MethodChannel(engine.dartExecutor.binaryMessenger, "app/yt_dlp")
            .setMethodCallHandler { call, res ->
                Thread({
                    try {
                        App.ensurePython(this)
                        val py = Python.getInstance().getModule("yt_bridge")
                        // yt_bridge.py returns JSON *strings* (never raw
                        // maps): pass them through untouched. Do NOT call
                        // .toList()/.toMap() here — Chaquopy cannot convert
                        // ytmusicapi's nested objects and crashes marshaling.
                        // All calls go through the lowercase call() dispatcher:
                        // Chaquopy lowercases attribute names, so camelCase
                        // lookups (getStream) would miss.
                        val query = call.argument<String>("query")!!
                        val videoId = call.argument<String>("videoId") ?: ""
                        val out: String? = when (call.method) {
                            "getStream" -> py
                                .callAttr("call", "getstream", query, videoId)
                                .toString()
                            "search" -> py
                                .callAttr("call", "search", query, "")
                                .toString()
                            "artist" -> py
                                .callAttr("call", "artist", "", videoId)
                                .toString()
                            "album" -> py
                                .callAttr("call", "album", "", videoId)
                                .toString()
                            else -> null
                        }
                        runOnUiThread { res.success(out) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            res.error("PY_ERR", e.message, null)
                        }
                    }
                }, "yt-dlp-bridge").start()
            }
    }
}
