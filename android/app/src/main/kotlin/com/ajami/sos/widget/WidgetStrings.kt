package com.ajami.sos.widget

import android.content.Context
import android.content.res.Configuration
import com.ajami.sos.R
import java.util.Locale

/**
 * Widget text follows the app's language switch, not the phone's locale.
 *
 * A widget has no Flutter context, so `getString()` would always resolve
 * against the phone language — an Arabic phone showed Arabic labels even when
 * the app was set to English. Here we build a context for the requested locale
 * first, then read the string.
 */
object WidgetStrings {

  fun of(context: Context, data: WidgetData.Snapshot): Context =
    localized(context, if (data.arabic) "ar" else "en")

  fun localized(context: Context, lang: String): Context {
    val locale = Locale(lang)
    Locale.setDefault(locale)
    val config = Configuration(context.resources.configuration)
    config.setLocale(locale)
    config.setLayoutDirection(locale)
    return context.createConfigurationContext(config)
  }

  /** `true` when the row title should be laid out right-to-left. */
  /**
   * أي نص مختلط (عربي + إنجليزي) يُعرض RTL.
   *
   * سابقاً كان أول حرف هو الحاكم، فجملة تبدأ بكلمة إنجليزية وتكمل بالعربية
   * تُعرض LTR فتتبعثر الكلمات. الآن RTL هو الأساس للنص المختلط، فتبقى كل
   * كلمة إنجليزية ككتلة سليمة داخل السطر العربي.
   */
  fun isRtl(text: String): Boolean {
    var hasRtl = false
    for (c in text) {
      val code = c.code
      if (code in 0x0590..0x08FF || code in 0xFB50..0xFEFF || code in 0x1EE00..0x1EEFF) {
        hasRtl = true
        break
      }
    }
    return hasRtl
  }

  fun doneOf(context: Context): String =
    context.getString(R.string.widget_done_of)

  fun left(context: Context): String =
    context.getString(R.string.widget_left)
}
