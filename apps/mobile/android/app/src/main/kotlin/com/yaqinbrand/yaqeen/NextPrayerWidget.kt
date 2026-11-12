package com.yaqinbrand.yaqeen

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject

/**
 * «الصلاة القادمة» home-screen widget (spec §5.28). Reads the snapshot the app writes on every
 * re-plan (key `yq.widget.v1`: a week of prayers, already localised and formatted), shows the next
 * prayer with a native countdown, and wakes itself at that prayer to move on to the following one.
 * No network, no Flutter engine: it works for a week after the app was last opened.
 */
class NextPrayerWidget : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val snapshot = read(context)
        for (id in ids) manager.updateAppWidget(id, render(context, snapshot))
        scheduleNext(context, snapshot)
    }

    override fun onDisabled(context: Context) {
        alarms(context).cancel(refreshIntent(context))
    }

    private data class Next(val label: String, val time: String, val atMillis: Long)

    private class Snapshot(val json: JSONObject?) {
        fun next(now: Long): Next? {
            val prayers = json?.optJSONArray("prayers") ?: return null
            for (i in 0 until prayers.length()) {
                val p = prayers.getJSONObject(i)
                val at = p.optLong("at")
                if (at > now) return Next(p.optString("label"), p.optString("time"), at)
            }
            return null
        }

        fun text(key: String): String? = json?.optString(key)?.takeIf { it.isNotEmpty() && it != "null" }
    }

    private fun read(context: Context): Snapshot {
        val raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(KEY, null)
        return Snapshot(raw?.let { runCatching { JSONObject(it) }.getOrNull() })
    }

    private fun render(context: Context, s: Snapshot): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_next_prayer)
        val now = System.currentTimeMillis()
        val next = s.next(now)
        val rtl = s.json?.optBoolean("rtl", true) ?: true
        views.setInt(R.id.widget_root, "setLayoutDirection", if (rtl) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR)

        views.setTextViewText(R.id.widget_eyebrow, s.text("nextLabel") ?: context.getString(R.string.widget_next_prayer))
        val subtitle = listOfNotNull(s.text("ramadan") ?: s.text("hijri"), s.text("place")).joinToString(" · ")
        views.setTextViewText(R.id.widget_subtitle, subtitle)

        if (next == null) {
            // No snapshot yet, or a week without opening the app.
            views.setTextViewText(R.id.widget_prayer, "")
            views.setTextViewText(R.id.widget_time, s.text("staleText") ?: context.getString(R.string.widget_open_app))
            views.setViewVisibility(R.id.widget_countdown, View.GONE)
        } else {
            views.setTextViewText(R.id.widget_prayer, next.label)
            views.setTextViewText(R.id.widget_time, next.time)
            views.setViewVisibility(R.id.widget_countdown, View.VISIBLE)
            // Chronometer counts down to the adhan on its own; the alarm below rolls it over.
            views.setChronometer(R.id.widget_countdown, SystemClock.elapsedRealtime() + (next.atMillis - now), null, true)
            views.setChronometerCountDown(R.id.widget_countdown, true)
        }

        val wird = s.json?.optJSONObject("wird")
        if (wird != null && wird.optInt("goal") > 0) {
            views.setViewVisibility(R.id.widget_wird, View.VISIBLE)
            views.setTextViewText(R.id.widget_wird_label, wird.optString("label"))
            views.setTextViewText(R.id.widget_wird_text, wird.optString("text"))
            views.setProgressBar(R.id.widget_wird_bar, wird.optInt("goal"), wird.optInt("pages"), false)
        } else {
            views.setViewVisibility(R.id.widget_wird, View.GONE)
        }

        val open = Intent(Intent.ACTION_VIEW, Uri.parse("yaqeen://prayer")).setPackage(context.packageName)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE),
        )
        return views
    }

    /** Re-render just after the next prayer (exact when allowed, else as close as Android permits). */
    private fun scheduleNext(context: Context, s: Snapshot) {
        val next = s.next(System.currentTimeMillis()) ?: return
        val am = alarms(context)
        val at = next.atMillis + 1_000
        val pi = refreshIntent(context)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || am.canScheduleExactAlarms()) {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC, at, pi)
        } else {
            am.setAndAllowWhileIdle(AlarmManager.RTC, at, pi)
        }
    }

    private fun alarms(context: Context) = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun refreshIntent(context: Context): PendingIntent {
        val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, NextPrayerWidget::class.java))
        val intent = Intent(context, NextPrayerWidget::class.java)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(context, 1, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    companion object {
        /** Written by the home_widget plugin (HomeWidgetPublisher in the app). */
        private const val PREFERENCES = "HomeWidgetPreferences"
        private const val KEY = "yq.widget.v1"
    }
}
