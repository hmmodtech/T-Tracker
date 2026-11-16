package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.view.View
import android.util.TypedValue
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Quick-memo widget.
 *
 * New memos are appended to a small queue in SharedPreferences. The Flutter app
 * drains that queue into the encrypted database on its next start (and right
 * away when it is already running), so typing here never needs the DB key.
 */
class MemoWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
  ) {
    for (id in ids) manager.updateAppWidget(id, build(context))
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      WidgetKeys.ACTION_ADD_MEMO -> {
        val text = intent.getStringExtra(WidgetKeys.EXTRA_TEXT).orEmpty()
        WidgetData.saveLocalMemo(context, text)
        // Let the running Flutter app persist it into the database immediately.
        try {
          context.startActivity(
            Intent(context, MainActivity::class.java).apply {
              action = "com.ajami.sos.PULL_MEMOS"
              flags = Intent.FLAG_ACTIVITY_NEW_TASK
            },
          )
        } catch (_: Throwable) {
          // App not running: it will be picked up on next launch.
        }
        refresh(context)
      }
      WidgetKeys.ACTION_REFRESH -> refresh(context)
    }
  }

  companion object {
    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, MemoWidgetProvider::class.java),
      )
      if (ids.isEmpty()) return
      val views = build(context)
      for (id in ids) manager.updateAppWidget(id, views)
    }

    fun build(context: Context): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_memo)

      views.removeAllViews(R.id.w_rows)

      val data = WidgetData.load(context)
      val scale = WidgetStyle.scale(data)
      val palette = WidgetStyle.palette(data)
      WidgetStyle.apply(context, views, data)

      views.setTextColor(R.id.w_title, palette.green)
      views.setTextColor(R.id.w_input, palette.text)
      views.setTextColor(R.id.w_empty, palette.muted)
      WidgetStyle.tint(views, R.id.w_send, palette.aqua)
      WidgetStyle.tint(views, R.id.w_accent, palette.green)

      // Queued memos first (typed on the home screen, not yet in the DB), then
      // every memo stored in the app — not just today's.
      val local = WidgetData.localMemos(context)
      val fromDb = data.memos
      val merged = (local + fromDb)
        .distinctBy { it.text.trim() }
        .take(5)

      views.setViewVisibility(
        R.id.w_empty,
        if (merged.isEmpty()) View.VISIBLE else View.GONE,
      )
      for (memo in merged) {
        val row = RemoteViews(context.packageName, R.layout.widget_memo_row)
        row.setTextViewText(R.id.row_title, memo.text)
        row.setTextColor(R.id.row_title, palette.text)
        row.setTextViewTextSize(
          R.id.row_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(11f, scale),
        )
        views.addView(R.id.w_rows, row)
      }
      views.setTextViewTextSize(
        R.id.w_input, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_empty, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(11f, scale),
      )

      views.setOnClickPendingIntent(R.id.w_send, sendIntent(context))
      views.setOnClickPendingIntent(R.id.w_input, sendIntent(context))
      views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
      return views
    }

    /** Opens the fast memo sheet (RemoteViews cannot host an EditText). */
    private fun sendIntent(context: Context): PendingIntent {
      val intent = Intent(context, QuickMemoActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
          Intent.FLAG_ACTIVITY_CLEAR_TOP or
          Intent.FLAG_ACTIVITY_EXCLUDE_FROM_RECENTS
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_MEMO, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }

    private fun openApp(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_MAIN
        addCategory(Intent.CATEGORY_LAUNCHER)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_MEMO + 1, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }
  }
}
