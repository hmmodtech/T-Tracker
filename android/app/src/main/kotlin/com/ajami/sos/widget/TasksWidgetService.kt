package com.ajami.sos.widget

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Fills the scrollable task list inside the tasks widget.
 *
 * A widget cannot scroll a LinearLayout, so the rows live in a ListView backed
 * by this service. Every row carries two fill-in intents:
 *  • tapping the row body opens that task's page in the app,
 *  • tapping the checkbox toggles the task without leaving the launcher.
 */
class TasksWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
    TasksFactory(applicationContext)
}

private data class Row(
  val task: WidgetData.Task,
  val day: String,
  val upcoming: Boolean,
)

class TasksFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

  private var rows: List<Row> = emptyList()
  private var palette: WidgetStyle.Palette = WidgetStyle.palette(WidgetData.load(context))
  private var scale: Float = 1f

  override fun onCreate() = Unit

  override fun onDataSetChanged() {
    val data = WidgetData.load(context)
    palette = WidgetStyle.palette(data)
    scale = WidgetStyle.scale(data)

    val today = WidgetData.dayKey(0)
    val list = mutableListOf<Row>()

    // Today first, then the pre-defined plan as it approaches.
    data.today.forEach { list += Row(it, it.day.ifEmpty { today }, false) }
    data.upcoming.forEach { list += Row(it, it.day, true) }
    // Past days that were never ticked, so nothing silently disappears.
    data.overdue.forEach {
      val day = it.day.ifEmpty { today }
      if (list.none { r -> r.task.id == it.id && r.day == day }) {
        list += Row(it, day, false)
      }
    }
    rows = list
  }

  override fun onDestroy() {
    rows = emptyList()
  }

  override fun getCount(): Int = rows.size

  override fun getViewAt(position: Int): RemoteViews? {
    val row = rows.getOrNull(position) ?: return null
    val task = row.task
    val res = RemoteViews(context.packageName, R.layout.widget_tasks_row)

    res.setTextViewText(R.id.row_title, task.title)
    // Arabic (or mixed) titles read right-to-left even on an English phone,
    // which is what stops English words inside them from being scrambled.
    if (WidgetStrings.isRtl(task.title)) {
      res.setInt(R.id.row_title, "setTextDirection", 3) // TEXT_DIRECTION_RTL
    }
    res.setTextViewTextSize(
      R.id.row_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
    )

    val sub = buildString {
      if (row.upcoming) {
        append(dayLabel(row.day))
        if (!task.time.isNullOrEmpty()) { append(" · "); append(task.time) }
      } else if (!task.time.isNullOrEmpty()) {
        append(task.time)
      }
      if (task.subtitle.isNotEmpty()) {
        if (isNotEmpty()) append("  ")
        append("☑ "); append(task.subtitle)
      }
      if (task.isPrivate) {
        if (isNotEmpty()) append("  ")
        append("🔒")
      }
    }
    if (sub.isNotEmpty()) {
      res.setViewVisibility(R.id.row_sub, View.VISIBLE)
      res.setTextViewText(R.id.row_sub, sub)
      res.setTextViewTextSize(
        R.id.row_sub, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(10f, scale),
      )
    } else {
      res.setViewVisibility(R.id.row_sub, View.GONE)
    }

    res.setViewVisibility(
      R.id.row_strike,
      if (task.done) View.VISIBLE else View.GONE,
    )
    res.setImageViewResource(
      R.id.row_check,
      if (task.done) R.drawable.widget_check_on else R.drawable.widget_check_off,
    )

    if (task.priority >= 2) {
      res.setViewVisibility(R.id.row_tag, View.VISIBLE)
      res.setTextViewText(R.id.row_tag, "●")
    } else if (task.isMission) {
      res.setViewVisibility(R.id.row_tag, View.VISIBLE)
      res.setTextViewText(R.id.row_tag, "◆")
    } else {
      res.setViewVisibility(R.id.row_tag, View.GONE)
    }
    res.setTextViewTextSize(
      R.id.row_tag, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(10f, scale),
    )

    WidgetStyle.styleTaskRow(res, palette, task.done, task.priority, task.isMission)

    // Tapping the row opens that task's page in the app.
    val openFill = Intent().apply {
      putExtra(WidgetKeys.EXTRA_OPEN, WidgetKeys.OPEN_TASK)
      putExtra(WidgetKeys.EXTRA_TASK_ID, task.id)
      putExtra(WidgetKeys.EXTRA_DAY, row.day)
    }
    res.setOnClickFillInIntent(R.id.row_title, openFill)
    res.setOnClickFillInIntent(R.id.row_sub, openFill)
    res.setOnClickFillInIntent(R.id.row_open, openFill)

    // Tapping the checkbox ticks it in place.
    val toggleFill = Intent().apply {
      putExtra(WidgetKeys.EXTRA_OPEN, WidgetKeys.OPEN_TOGGLE)
      putExtra(WidgetKeys.EXTRA_TASK_ID, task.id)
      putExtra(WidgetKeys.EXTRA_DAY, row.day)
    }
    res.setOnClickFillInIntent(R.id.row_check, toggleFill)

    return res
  }

  override fun getLoadingView(): RemoteViews? = null
  override fun getViewTypeCount(): Int = 1
  override fun getItemId(position: Int): Long = rows.getOrNull(position)?.task?.id?.toLong() ?: 0L
  override fun hasStableIds(): Boolean = false

  @Suppress("unused")
  private fun dayLabel(key: String): String = when (key) {
    WidgetData.dayKey(0) -> "•"
    WidgetData.dayKey(1) -> "↗"
    else -> key.takeLast(5) // MM-dd
  }
}

/** Intent helpers shared by the widget providers. */
internal fun taskPageIntent(context: Context, taskId: Int, day: String): Intent =
  Intent(context, MainActivity::class.java).apply {
    action = WidgetKeys.ACTION_OPEN_TASK
    data = Uri.parse("sos://task/$taskId?day=$day")
    putExtra(WidgetKeys.EXTRA_TASK_ID, taskId)
    putExtra(WidgetKeys.EXTRA_DAY, day)
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
  }

internal fun dayPageIntent(context: Context, day: String): Intent =
  Intent(context, MainActivity::class.java).apply {
    action = WidgetKeys.ACTION_OPEN_DAY
    data = Uri.parse("sos://day/$day")
    putExtra(WidgetKeys.EXTRA_DAY, day)
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
  }

internal fun immutableFlags(): Int =
  PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
