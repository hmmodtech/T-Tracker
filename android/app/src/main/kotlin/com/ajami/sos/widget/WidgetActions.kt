package com.ajami.sos.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * Widget actions are queued instead of written straight to the encrypted
 * database: the app owns the data, so it applies the queue on next launch
 * (and immediately when it is already running).
 */
object WidgetActions {

  fun toggleTask(context: Context, taskId: Int, day: String) {
    WidgetData.queueToggle(context, taskId, day)
    // The queued tick is mirrored locally so the row flips instantly, before
    // the app drains the queue and rewrites the snapshot.
    WidgetData.applyQueuedToggles(context)
    refreshAll(context)
  }

  /** Updates every widget from the current snapshot. */
  fun refreshAll(context: Context) {
    // ListView-backed widgets need an explicit dataset-changed signal,
    // otherwise the adapter keeps the rows it already built.
    try {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, TasksWidgetProvider::class.java),
      )
      for (id in ids) manager.notifyAppWidgetViewDataChanged(id, com.ajami.sos.R.id.w_list)
    } catch (_: Throwable) {
      // ignore
    }
    TasksWidgetProvider.refresh(context)
    MemoWidgetProvider.refresh(context)
    ResultWidgetProvider.refresh(context)
    CalendarWidgetProvider.refresh(context)
  }

  /** True when at least one widget of any kind is on the home screen. */
  fun hasWidgets(context: Context): Boolean {
    val manager = AppWidgetManager.getInstance(context)
    return listOf(
      TasksWidgetProvider::class.java,
      MemoWidgetProvider::class.java,
      ResultWidgetProvider::class.java,
      CalendarWidgetProvider::class.java,
    ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
  }
}
