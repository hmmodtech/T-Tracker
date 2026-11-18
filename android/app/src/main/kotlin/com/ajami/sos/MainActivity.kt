package com.ajami.sos

import android.content.Intent
import android.os.Bundle
import com.ajami.sos.widget.WidgetActions
import com.ajami.sos.widget.WidgetData
import com.ajami.sos.widget.WidgetKeys
import com.ajami.sos.widget.WidgetLog
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity is required by local_auth (biometric prompt).
class MainActivity : FlutterFragmentActivity() {

    private var channel: MethodChannel? = null
    private var pendingAction: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // FLAG_SECURE was removed on purpose: it blanked the recent-apps
        // thumbnail and looked like the app was hiding itself.
        pendingAction = actionFrom(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = actionFrom(intent)
        if (action != null) dispatchOrQueue(action)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val ch = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.ajami.sos/widgets"
        )
        channel = ch

        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                // Ask every home-screen widget to redraw.
                "refresh" -> {
                    WidgetActions.refreshAll(this)
                    result.success(null)
                }

                // Checkbox taps queued from the tasks widget.
                // Diagnostics for the widgets: they run inside the launcher,
                // so their failures have nowhere else to surface.
                "widgetErrors" -> {
                    result.success(WidgetLog.read(this))
                }
                "clearWidgetErrors" -> {
                    WidgetLog.clear(this)
                    result.success(null)
                }
                "pullToggles" -> {
                    val arr = org.json.JSONArray()
                    for (t in WidgetData.pendingToggles(this)) {
                        arr.put(
                            org.json.JSONObject()
                                .put("id", t.first)
                                .put("day", t.second)
                                .put("done", t.third)
                        )
                    }
                    result.success(arr.toString())
                }
                "clearToggles" -> {
                    getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
                        .edit().remove(WidgetData.KEY_TOGGLES).apply()
                    WidgetActions.refreshAll(this)
                    result.success(null)
                }
                // Font size / opacity changed from the settings screen.
                "applySettings" -> {
                    WidgetActions.refreshAll(this)
                    result.success(null)
                }
                // Which screen the user asked for by tapping a widget.
                // Payload: "action|taskId|day" so Dart can jump straight to
                // the task page or the day page.
                "consumeAction" -> {
                    val payload = pendingAction
                    pendingAction = null
                    result.success(payload)
                }
                else -> result.notImplemented()
            }
        }

        // Hand over an action that arrived before the engine was ready.
        pendingAction?.let { dispatch(it) }
    }

    private fun actionFrom(intent: Intent?): String? {
        val day = intent?.getStringExtra(WidgetKeys.EXTRA_DAY).orEmpty()
        val taskId = intent?.getIntExtra(WidgetKeys.EXTRA_TASK_ID, -1) ?: -1
        val noteId = intent?.getIntExtra(WidgetKeys.EXTRA_NOTE_ID, -1) ?: -1
        return when (intent?.action) {
            "com.ajami.sos.NEW_TASK" -> "new_task"
            "com.ajami.sos.PULL_MEMOS" -> "pull_memos"
            "com.ajami.sos.WIDGET_SETTINGS" -> "widget_settings"
            // Tapping a task row opens that task's page.
            WidgetKeys.ACTION_OPEN_TASK -> "open_task|$taskId|$day"
            // Tapping a calendar day opens that day's page (tasks + memo).
            WidgetKeys.ACTION_OPEN_DAY -> "open_day|$taskId|$day"
            WidgetKeys.ACTION_OPEN_NOTES -> "open_notes|$taskId|$day"
            // Tapping a note row opens that note's editor.
            WidgetKeys.ACTION_OPEN_NOTE -> "open_note|$noteId|$day"
            else -> null
        }
    }

    /** Some widget taps arrive while the app is already open. */
    private fun dispatchOrQueue(action: String) {
        val ch = channel
        if (ch == null) {
            pendingAction = action
        } else {
            ch.invokeMethod("openAction", action)
        }
    }

    private fun dispatch(action: String) {
        channel?.invokeMethod("openAction", action)
    }
}
