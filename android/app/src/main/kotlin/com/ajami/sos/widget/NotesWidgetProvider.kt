package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Dedicated notes widget.
 *
 * The memo widget is a fast capture box; this one is the reading surface for
 * long, formatted notes. It shows a scrollable list with a coloured spine per
 * note, and tapping a note opens the rich editor on that note.
 */
class NotesWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val views = build(context)
    for (id in ids) manager.updateAppWidget(id, views)
    for (id in ids) {
      try {
        manager.notifyAppWidgetViewDataChanged(id, R.id.w_list)
      } catch (_: Throwable) {
        // ignore
      }
    }
  }

  companion object {
    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, NotesWidgetProvider::class.java),
      )
      if (ids.isEmpty()) return
      for (id in ids) {
        manager.notifyAppWidgetViewDataChanged(id, R.id.w_list)
      }
      manager.updateAppWidget(ids, build(context))
    }

    fun build(context: Context): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_notes)
      val data = WidgetData.load(context)
      val scale = WidgetStyle.scale(data)
      val palette = WidgetStyle.palette(data)
      WidgetStyle.apply(context, views, data)
      views.setTextColor(R.id.w_title, palette.green)
      views.setTextColor(R.id.w_count, palette.mutedGreen)
      views.setTextColor(R.id.w_empty, palette.muted)
      WidgetStyle.tint(views, R.id.w_add, palette.aqua)
      WidgetStyle.tint(views, R.id.w_accent, palette.green)

      views.setTextViewTextSize(
        R.id.w_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )

      val notes = data.notes
      views.setTextViewText(
        R.id.w_count,
        if (notes.isEmpty()) "" else "${notes.size}",
      )

      val newNote = PendingIntent.getActivity(
        context,
        WidgetKeys.REQ_NOTES + 1,
        Intent(context, MainActivity::class.java).apply {
          action = WidgetKeys.ACTION_OPEN_NOTES
          setData(Uri.parse("sos://notes/new"))
          putExtra(WidgetKeys.EXTRA_OPEN, "new")
          flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        WidgetStyle.pendingFlags(),
      )
      views.setOnClickPendingIntent(R.id.w_add, newNote)

      // The list is backed by NotesListService; row taps fill in the note id.
      views.setRemoteAdapter(
        R.id.w_list,
        Intent(context, NotesListService::class.java).apply {
          setData(Uri.parse("sos://widget/notelist/${context.packageName}"))
        },
      )
      views.setEmptyView(R.id.w_list, R.id.w_empty)
      views.setPendingIntentTemplate(
        R.id.w_list,
        PendingIntent.getActivity(
          context,
          WidgetKeys.REQ_NOTES + 7,
          Intent(context, MainActivity::class.java).apply {
            action = WidgetKeys.ACTION_OPEN_NOTE
            setData(Uri.parse("sos://note/template"))
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
          },
          WidgetStyle.pendingFlags(),
        ),
      )

      return views
    }
  }
}
