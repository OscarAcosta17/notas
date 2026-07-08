package com.example.notas

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider

class HorarioWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences
    ) {
        for (appWidgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_horario)

            val horarioText = widgetData.getString("horario_text", "No hay clases programadas hoy.")
            views.setTextViewText(R.id.widget_text_horario, horarioText)

            appWidgetManager.updateAppWidget(appWidgetId, views)
        }
    }
}
