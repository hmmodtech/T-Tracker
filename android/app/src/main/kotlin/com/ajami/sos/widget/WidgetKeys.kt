package com.ajami.sos.widget

/** Shared action names used by both the widgets and MainActivity. */
object WidgetKeys {
  const val ACTION_TOGGLE = "com.ajami.sos.widget.TOGGLE"
  const val ACTION_ADD_MEMO = "com.ajami.sos.widget.ADD_MEMO"
  const val ACTION_REFRESH = "com.ajami.sos.widget.REFRESH"

  const val EXTRA_TASK_ID = "task_id"
  const val EXTRA_DAY = "day"
  const val EXTRA_TEXT = "text"
  const val EXTRA_WIDGET_ID = "widget_id"

  /** Widget ids for AppWidgetManager updates. */
  const val REQ_LIST = 1001
  const val REQ_MEMO = 1002
  const val REQ_RESULT = 1003
  const val REQ_CALENDAR = 1004
  const val REQ_NOTES = 1005

  /** Long-press a widget to open the widget settings in the app. */
  const val ACTION_SETTINGS = "com.ajami.sos.widget.SETTINGS"

  // ---- Tap-through targets (widget row / calendar day → app page) ----
  const val ACTION_OPEN_TASK = "com.ajami.sos.OPEN_TASK"
  const val ACTION_OPEN_DAY = "com.ajami.sos.OPEN_DAY"
  const val ACTION_OPEN_NOTES = "com.ajami.sos.OPEN_NOTES"

  /** Fill-in intent selectors used by TasksWidgetService. */
  const val EXTRA_OPEN = "open_kind"
  const val OPEN_TASK = "task"
  const val OPEN_TOGGLE = "toggle"
  const val OPEN_NOTE = "note"
}
