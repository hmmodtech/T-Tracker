package com.ajami.sos.widget

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
 * Scrollable notes list for the memo widget.
 *
 * Each row opens the note editor in the app on that note, so a long task list
 * of notes is browsable straight from the home screen.
 */
class NotesWidgetService : RemoteViewsService() {
  override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
    NotesFactory(applicationContext)
}

class NotesFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {

  private var items: List<WidgetData.Memo> = emptyList()
  private var palette: WidgetStyle.Palette = WidgetStyle.palette(WidgetData.load(context))
  private var scale: Float = 1f

  override fun onCreate() = Unit

  override fun onDataSetChanged() {
    val data = WidgetData.load(context)
    palette = WidgetStyle.palette(data)
    scale = WidgetStyle.scale(data)
    items = (WidgetData.localMemos(context) + data.memos)
      .distinctBy { it.text.trim() }
      .take(50)
  }

  override fun onDestroy() {
    items = emptyList()
  }

  override fun getCount(): Int = items.size

  override fun getViewAt(position: Int): RemoteViews? {
    val memo = items.getOrNull(position) ?: return null
    val res = RemoteViews(context.packageName, R.layout.widget_memo_row)

    res.setTextViewText(R.id.row_title, memo.text)
    res.setTextViewTextSize(
      R.id.row_title, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(11f, scale),
    )
    res.setTextColor(R.id.row_title, palette.text)
    res.setInt(
      R.id.row_title,
      "setTextDirection",
      if (WidgetStrings.isRtl(memo.text)) 3 else 2,
    )

    // Tapping the row opens that note in the app.
    res.setOnClickFillInIntent(
      R.id.row_title,
      Intent().apply {
        putExtra(WidgetKeys.EXTRA_OPEN, WidgetKeys.OPEN_NOTE)
        putExtra(WidgetKeys.EXTRA_DAY, memo.day)
        putExtra(WidgetKeys.EXTRA_TEXT, memo.text)
        data = Uri.parse("sos://note/${memo.day}")
      },
    )
    return res
  }

  override fun getLoadingView(): RemoteViews? = null
  override fun getViewTypeCount(): Int = 1
  override fun getItemId(position: Int): Long = position.toLong()
  override fun hasStableIds(): Boolean = false
}

/** Opens the app on the notes screen (used by the memo widget's + button). */
internal fun notesPageIntent(context: Context, day: String): Intent =
  Intent(context, MainActivity::class.java).apply {
    action = WidgetKeys.ACTION_OPEN_NOTES
    data = Uri.parse("sos://notes/$day")
    putExtra(WidgetKeys.EXTRA_DAY, day)
    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
  }
