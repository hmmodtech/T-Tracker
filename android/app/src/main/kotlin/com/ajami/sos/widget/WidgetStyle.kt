package com.ajami.sos.widget

import android.content.Context
import android.widget.RemoteViews
import com.ajami.sos.R

/**
 * Applies the user's widget preferences — text size, panel opacity and
 * light/dark mode — to every widget.
 *
 * RemoteViews can only call a whitelisted set of methods, so:
 *  • the panel background is swapped between pre-made drawable variants,
 *  • font sizes use `setTextViewTextSize`,
 *  • colours are chosen here (light palette vs dark palette) and pushed with
 *    `setTextColor` / `setBackgroundColor` / `setColorFilter`.
 *
 * Without a custom view there is no theme resolution inside a widget, which is
 * why light mode previously changed nothing: every colour was a hard-coded
 * `@color/widget_*` reference baked into the layout.
 */
object WidgetStyle {

  // ── Dark palette (Sci-Fi HUD) ──────────────────────────────────────────────
  private const val D_GREEN = 0xFF25F4C8.toInt()
  private const val D_AQUA = 0xFF38BDF8.toInt()
  private const val D_DIM = 0xFF14B8CE.toInt()
  private const val D_MINT = 0xFFB6FFE9.toInt()
  private const val D_TEXT = 0xFFD7E6F5.toInt()
  private const val D_MUTED = 0xFF7C8FAB.toInt()
  private const val D_MUTED_GREEN = 0xFF6E9E8F.toInt()
  private const val D_RED = 0xFFFF5470.toInt()
  private const val D_AMBER = 0xFFFFC15E.toInt()
  private const val D_TRACK = 0x8012283D.toInt()

  // ── Light palette (soft daylight, same identity) ───────────────────────────
  private const val L_GREEN = 0xFF0E9E86.toInt()
  private const val L_AQUA = 0xFF2E86C8.toInt()
  private const val L_DIM = 0xFF127C96.toInt()
  private const val L_MINT = 0xFF3AA894.toInt()
  private const val L_TEXT = 0xFF16283C.toInt()
  private const val L_MUTED = 0xFF61758C.toInt()
  private const val L_MUTED_GREEN = 0xFF4C7D71.toInt()
  private const val L_RED = 0xFFD6374F.toInt()
  private const val L_AMBER = 0xFFB57614.toInt()
  private const val L_TRACK = 0x33C3D3E2

  /** Palette bundle handed to the providers. */
  data class Palette(
    val green: Int,
    val aqua: Int,
    val dim: Int,
    val mint: Int,
    val text: Int,
    val muted: Int,
    val mutedGreen: Int,
    val red: Int,
    val amber: Int,
    val track: Int,
    val light: Boolean,
  ) {
    /** Text colour for a task title, dimmed when completed. */
    fun titleColor(done: Boolean): Int = if (done) muted else text
    /** Contrasting colour for a filled check/halo icon. */
    val onAccent: Int get() = if (light) 0xFFFFFFFF.toInt() else 0xFF04070F.toInt()
  }

  private val dark = Palette(
    green = D_GREEN, aqua = D_AQUA, dim = D_DIM, mint = D_MINT,
    text = D_TEXT, muted = D_MUTED, mutedGreen = D_MUTED_GREEN,
    red = D_RED, amber = D_AMBER, track = D_TRACK, light = false,
  )

  private val light = Palette(
    green = L_GREEN, aqua = L_AQUA, dim = L_DIM, mint = L_MINT,
    text = L_TEXT, muted = L_MUTED, mutedGreen = L_MUTED_GREEN,
    red = L_RED, amber = L_AMBER, track = L_TRACK, light = true,
  )

  /** Picks the palette that matches the app's current mode. */
  fun palette(data: WidgetData.Snapshot): Palette = if (data.lightMode) light else dark

  /** Text sizes are authored at 1.0 and scaled 0.85x .. 1.5x. */
  fun scale(data: WidgetData.Snapshot): Float =
    data.textScale.coerceIn(0.85f, 1.5f)

  /** Small helper: scaled size in SP. */
  fun sp(base: Float, scale: Float): Float = base * scale

  /**
   * Sets the panel background for the requested opacity and theme.
   * 0.95 = near solid, 0.85 = default, 0.70 = airy, 0.50 = very transparent.
   */
  fun applyOpacity(views: RemoteViews, opacity: Float, light: Boolean) {
    val res = when {
      opacity >= 0.90f ->
        if (light) R.drawable.widget_bg_light_solid else R.drawable.widget_bg_solid
      opacity >= 0.80f ->
        if (light) R.drawable.widget_bg_light_panel else R.drawable.widget_bg
      opacity >= 0.65f ->
        if (light) R.drawable.widget_bg_light_airy else R.drawable.widget_bg_light
      else ->
        if (light) R.drawable.widget_bg_light_ghost else R.drawable.widget_bg_ghost
    }
    views.setInt(R.id.widget_root, "setBackgroundResource", res)
  }

  /** Convenience overload used by every provider. */
  fun apply(context: Context, views: RemoteViews, data: WidgetData.Snapshot) {
    applyOpacity(views, data.opacity, data.lightMode)
  }

  /**
   * Recolours the parts of a task row that layouts cannot theme on their own.
   * Call after the row's text has been set.
   */
  fun styleTaskRow(
    row: RemoteViews,
    p: Palette,
    done: Boolean,
    priority: Int,
    isMission: Boolean,
  ) {
    row.setTextColor(R.id.row_title, p.titleColor(done))
    row.setTextColor(R.id.row_sub, p.muted)
    row.setColorFilter(
      R.id.row_check,
      if (done) p.green else p.muted,
    )
    row.setTextColor(
      R.id.row_tag,
      when {
        priority >= 2 -> p.red
        isMission -> p.aqua
        else -> p.mutedGreen
      },
    )
  }
}
