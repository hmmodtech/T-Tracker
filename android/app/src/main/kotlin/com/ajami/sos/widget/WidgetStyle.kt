package com.ajami.sos.widget

import android.content.Context
import android.widget.RemoteViews
import com.ajami.sos.R

/**
 * Applies the user's widget preferences (text size and panel opacity) coming
 * from the app's settings screen.
 *
 * RemoteViews can only touch a fixed set of methods, so font sizes are set with
 * `setTextViewTextSize` and the panel opacity is faked by swapping between three
 * pre-made alpha variants of the background drawable — no custom views needed.
 */
object WidgetStyle {

  /** Text sizes are authored at 1.0 and scaled 0.85x .. 1.5x. */
  fun scale(data: WidgetData.Snapshot): Float =
    data.textScale.coerceIn(0.85f, 1.5f)

  /** Small helper: scaled size in SP. */
  fun sp(base: Float, scale: Float): Float = base * scale

  /**
   * Sets the panel background for the requested opacity.
   * 0.95 = near solid, 0.85 = default, 0.70 = airy, 0.55 = very transparent.
   */
  fun applyOpacity(views: RemoteViews, opacity: Float) {
    val res = when {
      opacity >= 0.90f -> R.drawable.widget_bg_solid
      opacity >= 0.80f -> R.drawable.widget_bg
      opacity >= 0.65f -> R.drawable.widget_bg_light
      else -> R.drawable.widget_bg_ghost
    }
    views.setInt(R.id.widget_root, "setBackgroundResource", res)
  }

  /** Convenience overload used by every provider. */
  fun apply(context: Context, views: RemoteViews, data: WidgetData.Snapshot) {
    applyOpacity(views, data.opacity)
  }
}
