package com.ajami.sos.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import com.ajami.sos.R

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

  /**
   * Updates every widget from the current snapshot.
   *
   * Each widget is refreshed in its own `try`: a provider that throws (a
   * launcher refusing a binder, a malformed row) used to abort the whole
   * chain, which left later widgets stuck on "Loading".
   */
  fun refreshAll(context: Context) {
    for (step in steps) {
      try {
        step(context)
      } catch (_: Throwable) {
        // Never let one widget break the others.
      }
    }
  }

  private fun notifyList(context: Context, provider: Class<*>) {
    val manager = AppWidgetManager.getInstance(context)
    val ids = manager.getAppWidgetIds(ComponentName(context, provider))
    for (id in ids) manager.notifyAppWidgetViewDataChanged(id, R.id.w_list)
  }

  private val steps: List<(Context) -> Unit> = listOf(
    { ctx -> notifyList(ctx, TasksWidgetProvider::class.java) },
    { ctx -> notifyList(ctx, MemoWidgetProvider::class.java) },
    { ctx -> notifyList(ctx, NotesWidgetProvider::class.java) },
    { ctx -> TasksWidgetProvider.refresh(ctx) },
    { ctx -> MemoWidgetProvider.refresh(ctx) },
    { ctx -> ResultWidgetProvider.refresh(ctx) },
    { ctx -> CalendarWidgetProvider.refresh(ctx) },
    { ctx -> NotesWidgetProvider.refresh(ctx) },
  )

  /** True when at least one widget of any kind is on the home screen. */
  fun hasWidgets(context: Context): Boolean {
    val manager = AppWidgetManager.getInstance(context)
    return listOf(
      TasksWidgetProvider::class.java,
      MemoWidgetProvider::class.java,
      ResultWidgetProvider::class.java,
      CalendarWidgetProvider::class.java,
      NotesWidgetProvider::class.java,
    ).any { manager.getAppWidgetIds(ComponentName(context, it)).isNotEmpty() }
  }
}
