package com.ajami.sos.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.widget.RemoteViews
import com.ajami.sos.MainActivity
import com.ajami.sos.R

/**
 * Result widget: today's completion percentage as a big number plus a progress
 * bar, with yesterday and the rolling 7-day rate underneath.
 */
class ResultWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(
    context: Context,
    manager: AppWidgetManager,
    ids: IntArray,
  ) {
    for (id in ids) manager.updateAppWidget(id, build(context))
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == WidgetKeys.ACTION_REFRESH) refresh(context)
  }

  companion object {
    fun refresh(context: Context) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(
        ComponentName(context, ResultWidgetProvider::class.java),
      )
      if (ids.isEmpty()) return
      val views = build(context)
      for (id in ids) manager.updateAppWidget(id, views)
    }

    fun build(context: Context): RemoteViews {
      val views = RemoteViews(context.packageName, R.layout.widget_result)
      val data = WidgetData.load(context)
      val res = WidgetStrings.of(context, data).resources
      val scale = WidgetStyle.scale(data)
      val palette = WidgetStyle.palette(data)
      WidgetStyle.apply(context, views, data)

      views.setColorFilter(R.id.w_accent, palette.green)
      views.setTextColor(R.id.w_big, palette.mint)
      views.setTextColor(R.id.w_count, palette.muted)
      views.setTextColor(R.id.w_yesterday, palette.text)
      views.setTextColor(R.id.w_week, palette.aqua)
      views.setColorFilter(R.id.w_refresh, palette.green)

      views.setTextViewText(R.id.w_big, "${data.rateToday}%")
      views.setTextViewText(
        R.id.w_count,
        "${data.doneToday}/${data.scheduledToday} " +
          res.getString(R.string.widget_done),
      )
      views.setProgressBar(R.id.w_bar, 100, data.rateToday, false)

      views.setTextViewText(
        R.id.w_yesterday,
        if (data.scheduledYesterday == 0) "—" else "${data.doneYesterday}/${data.scheduledYesterday}",
      )
      views.setTextViewText(R.id.w_week, "${data.rate7}%")

      // Honour the widget font-size setting.
      views.setTextViewTextSize(
        R.id.w_big, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(34f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_count, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_yesterday, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(12f, scale),
      )
      views.setTextViewTextSize(
        R.id.w_week, TypedValue.COMPLEX_UNIT_SP, WidgetStyle.sp(20f, scale),
      )

      views.setOnClickPendingIntent(R.id.w_refresh, refreshIntent(context))
      views.setOnClickPendingIntent(R.id.widget_root, openApp(context))
      return views
    }

    private fun refreshIntent(context: Context): PendingIntent {
      val intent = Intent(context, ResultWidgetProvider::class.java).apply {
        action = WidgetKeys.ACTION_REFRESH
      }
      return PendingIntent.getBroadcast(
        context, WidgetKeys.REQ_RESULT, intent,
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
        context, WidgetKeys.REQ_RESULT + 1, intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
      )
    }
  }
}
