package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Home-screen to-do widget.
 *
 * Shows today's tasks first, then the upcoming scheduled ones (the pre-defined
 * D1–D20 plan) so the user sees what is coming without opening the app.
 * Each row can be ticked straight from the launcher.
 */
class TasksWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
  ) {
    val views = build(context)
    for (id in ids) manager.updateAppWidget(id, views)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      WidgetKeys.ACTION_TOGGLE -> {
        // Only the checkbox carries the "toggle" selector; everything else in
        // the row carries "task", so tapping the title opens the app.
        val kind = intent.getStringExtra(WidgetKeys.EXTRA_OPEN)
        val taskId = intent.getIntExtra(WidgetKeys.EXTRA_TASK_ID, -1)
        val day = intent.getStringExtra(WidgetKeys.EXTRA_DAY).orEmpty()
        if (kind == WidgetKeys.OPEN_TASK) {
          if (taskId >= 0) openTask(context, taskId, day)
          return
        }
        if (kind == WidgetKeys.OPEN_TOGGLE && taskId >= 0 && day.isNotEmpty()) {
          WidgetActions.toggleTask(context, taskId, day)
          WidgetActions.refreshAll(context)
        }
      }
      // Long-press opens the in-app widget settings.
      WidgetKeys.ACTION_SETTINGS -> openConfig(context)
    }
  }

  private fun openTask(context: Context, taskId: Int, day: String) {
    try {
      val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
      PendingIntent.getActivity(
        context, taskId, taskPageIntent(context, taskId, day), flags,
      ).send()
    } catch (_: Throwable) {
      // Never let a widget tap crash the launcher.
    }
  }

  private fun openConfig(context: Context) {
    try {
      context.startActivity(
        Intent(context, MainActivity::class.java).apply {
          action = "com.ajami.sos.WIDGET_SETTINGS"
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
      )
    } catch (_: Throwable) {
      // ignore
    }
  }

  companion object {

    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, TasksWidgetProvider::class.java),
      )
      if (ids.isEmpty()) return
      val views = build(context)
      for (id in ids) manager.updateAppWidget(id, views)
    }

    fun build(context: Context): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_tasks)
      val data = WidgetData.load(context)
      // Labels follow the app language, not the phone language.
      val res = WidgetStrings.of(context, data).resources
      val scale = WidgetStyle.scale(data)
      val palette = WidgetStyle.palette(data)

      WidgetStyle.apply(context, views, data)

      // Scrollable list: the RemoteViewsService builds the rows lazily and
      // handles both tap-to-open and tap-to-tick.
      val adapter = Intent(context, TasksWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
      }
      views.setRemoteAdapter(R.id.w_list, adapter)
      views.setEmptyView(R.id.w_list, R.id.w_empty)

      // A tick inside the list must not open the app.
      val toggled = Intent(context, TasksWidgetProvider::class.java).apply {
        action = WidgetKeys.ACTION_TOGGLE
      }
      views.setPendingIntentTemplate(
        R.id.w_list,
        PendingIntent.getBroadcast(
          context, WidgetKeys.REQ_LIST + 9, toggled, immutableFlags(),
        ),
      )

      val left = data.left
      views.setTextViewText(
        R.id.w_count,
        res.getString(R.string.widget_done_of) + " " +
          "${data.doneToday}/${data.scheduledToday}" +
          if (left > 0) "  ·  $left " + res.getString(R.string.widget_left) else "",
      )
      views.setTextViewTextSize(
        R.id.w_count, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(11f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )
      views.setTextColor(R.id.w_title, palette.green)
      views.setTextColor(R.id.w_count, palette.mutedGreen)
      views.setTextColor(R.id.w_empty, palette.muted)
      views.setColorFilter(R.id.w_add, palette.aqua)
      views.setColorFilter(R.id.w_accent, palette.green)

      views.setOnClickPendingIntent(R.id.w_add, newTaskIntent(context))
      return views
    }

    /** "Today", "Tomorrow" or a short date for upcoming rows. */
    private fun friendlyDay(key: String): String = when (key) {
      WidgetData.dayKey(0) -> "·"
      WidgetData.dayKey(1) -> "↗"
      else -> key.takeLast(5) // MM-dd
    }

    private fun openApp(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java).apply {
        action = Intent.ACTION_MAIN
        addCategory(Intent.CATEGORY_LAUNCHER)
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_LIST, intent, pendingFlags(),
      )
    }

    private fun newTaskIntent(context: Context): PendingIntent {
      val intent = Intent(context, MainActivity::class.java).apply {
        action = "com.ajami.sos.NEW_TASK"
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
      }
      return PendingIntent.getActivity(
        context, WidgetKeys.REQ_LIST + 1, intent, pendingFlags(),
      )
    }

    private fun toggleIntent(
      context: Context,
      taskId: Int,
      day: String,
    ): PendingIntent {
      val intent = Intent(context, TasksWidgetProvider::class.java).apply {
        action = WidgetKeys.ACTION_TOGGLE
        putExtra(WidgetKeys.EXTRA_TASK_ID, taskId)
        putExtra(WidgetKeys.EXTRA_DAY, day)
      }
      return PendingIntent.getBroadcast(context, taskId, intent, pendingFlags())
    }

    private fun pendingFlags(): Int =
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
  }
}
