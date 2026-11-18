package com.ajami.sos.widget

import android.content.Context
import android.util.Log
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * سجل أخطاء الودجت.
 *
 * الودجت تعمل داخل عملية الـ launcher، فأي فشل يظهر كـ «Loading» بلا أثر
 * يمكن للمستخدم إرساله. نكتب آخر الأخطاء في SharedPreferences ليقرأها
 * التطبيق ويعرضها في الإعدادات ← تشخيص الودجت.
 */
object WidgetLog {
  private const val TAG = "TTrackerWidget"
  private const val PREFS = "ttracker_widget_debug"
  private const val KEY = "last_errors"
  private const val MAX = 12

  fun report(context: Context, where: String, e: Throwable) {
    Log.e(TAG, "widget failure at $where", e)
    try {
      val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
      val stamp = SimpleDateFormat("MM-dd HH:mm:ss", Locale.US).format(Date())
      val line = "$stamp  $where  ${e.javaClass.simpleName}: ${e.message}"
      val old = prefs.getString(KEY, null) ?: ""
      val lines = (listOf(line) + old.split('\n'))
        .filter { it.isNotBlank() }
        .take(MAX)
      prefs.edit().putString(KEY, lines.joinToString("\n")).apply()
    } catch (_: Throwable) {
      // Diagnostics must never be the thing that breaks the widget.
    }
  }

  fun read(context: Context): String =
    try {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getString(KEY, null) ?: ""
    } catch (_: Throwable) {
      ""
    }

  fun clear(context: Context) {
    try {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .edit().remove(KEY).apply()
    } catch (_: Throwable) {
      // ignore
    }
  }
}
