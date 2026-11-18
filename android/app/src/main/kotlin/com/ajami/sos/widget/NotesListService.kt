package com.ajami.sos.widget

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.ajami.sos.R

/** Scrollable list backing the notes widget. */
class NotesListService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
    NotesListFactory(applicationContext)
}

class NotesListFactory(private val context: Context) :
  RemoteViewsService.RemoteViewsFactory {

  private var items: List<WidgetData.NoteEntry> = emptyList()
  private var palette: WidgetStyle.Palette = WidgetStyle.palette(WidgetData.load(context))
  private var scale: Float = 1f

  override fun onCreate() = Unit

  override fun onDataSetChanged() {
    // Contained: a throw here would leave the widget on "Loading" for good.
    items = try {
      val data = WidgetData.load(context)
      palette = WidgetStyle.palette(data)
      scale = WidgetStyle.scale(data)
      data.notes
    } catch (_: Throwable) {
      emptyList()
    }
  }

  override fun onDestroy() {
    items = emptyList()
  }

  override fun getCount(): Int = items.size

  override fun getViewAt(position: Int): RemoteViews {
    return try {
      buildRow(position)
    } catch (e: Throwable) {
      WidgetLog.report(context, "note row $position", e)
      emptyRow()
    }
  }

  private fun emptyRow(): RemoteViews {
    val res = RemoteViews(context.packageName, R.layout.widget_notes_row)
    res.setTextViewText(R.id.note_title, "")
    res.setViewVisibility(R.id.note_preview, View.GONE)
    return res
  }

  private fun buildRow(position: Int): RemoteViews {
    val note = items.getOrNull(position) ?: return emptyRow()
    val res = RemoteViews(context.packageName, R.layout.widget_notes_row)

    res.setTextViewText(R.id.note_title, note.title.ifEmpty { note.preview.take(60) })
    res.setTextViewTextSize(
      R.id.note_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
    )
    res.setTextColor(R.id.note_title, palette.text)
    WidgetStrings.align(res, R.id.note_title, note.title)

    // التاريخ معلومة على السطر، مع المجلد إن وُجد.
    val meta = buildString {
      if (note.day.isNotEmpty()) append(note.day)
      if (note.group.isNotEmpty()) {
        if (isNotEmpty()) append("  ·  ")
        append(note.group)
      }
    }
    if (meta.isNotEmpty()) {
      res.setViewVisibility(R.id.note_meta, View.VISIBLE)
      res.setTextViewText(R.id.note_meta, meta)
      res.setTextViewTextSize(
        R.id.note_meta, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(9f, scale),
      )
      res.setTextColor(R.id.note_meta, palette.mutedGreen)
      WidgetStrings.align(res, R.id.note_meta, meta)
    } else {
      res.setViewVisibility(R.id.note_meta, View.GONE)
    }

    if (note.preview.isNotEmpty() && note.title.isNotEmpty()) {
      res.setViewVisibility(R.id.note_preview, View.VISIBLE)
      res.setTextViewText(R.id.note_preview, note.preview)
      res.setTextViewTextSize(
        R.id.note_preview, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(10f, scale),
      )
      res.setTextColor(R.id.note_preview, palette.muted)
      WidgetStrings.align(res, R.id.note_preview, note.preview)
    } else {
      res.setViewVisibility(R.id.note_preview, View.GONE)
    }

    // Coloured spine per note (the note's own colour, or the accent).
    WidgetStyle.tint(
      res,
      R.id.note_spine,
      parseColor(note.color, if (note.pinned) palette.amber else palette.dim),
    )

    // Tapping a note opens that note's editor.
    res.setOnClickFillInIntent(
      R.id.note_row_root,
      Intent().apply {
        putExtra(WidgetKeys.EXTRA_OPEN, WidgetKeys.OPEN_NOTE)
        putExtra(WidgetKeys.EXTRA_NOTE_ID, note.id)
        putExtra(WidgetKeys.EXTRA_DAY, note.day)
        setData(Uri.parse("sos://note/${note.id}"))
      },
    )
    return res
  }

  private fun parseColor(hex: String?, fallback: Int): Int {
    if (hex.isNullOrBlank()) return fallback
    return try {
      val clean = hex.removePrefix("#")
      val v = clean.toLong(16)
      if (clean.length <= 6) (0xFF000000L or v).toInt() else v.toInt()
    } catch (_: Throwable) {
      fallback
    }
  }

  override fun getLoadingView(): RemoteViews? = null
  override fun getViewTypeCount(): Int = 1
  override fun getItemId(position: Int): Long = items.getOrNull(position)?.id?.toLong() ?: 0L
  override fun hasStableIds(): Boolean = true
}
