package com.example.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class AppWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_layout)

            val evaluations = widgetData.getString("evaluations", "No hay evaluaciones próximas.")
            views.setTextViewText(R.id.widget_text, evaluations)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
