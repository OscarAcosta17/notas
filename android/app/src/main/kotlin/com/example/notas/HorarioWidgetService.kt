package com.example.notas

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class HorarioWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return HorarioRemoteViewsFactory(this.applicationContext, intent)
    }
}

class HorarioRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private data class HorarioWidgetRow(val dayName: String, val content: String)

    private var itemsList: List<HorarioWidgetRow> = emptyList()

    private fun defaultWeekdays(): List<HorarioWidgetRow> = listOf(
        HorarioWidgetRow("Lunes", "Ningún evento"),
        HorarioWidgetRow("Martes", "Ningún evento"),
        HorarioWidgetRow("Miércoles", "Ningún evento"),
        HorarioWidgetRow("Jueves", "Ningún evento"),
        HorarioWidgetRow("Viernes", "Ningún evento"),
    )

    override fun onCreate() {
    }

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        val rawString = widgetData.getString("horario_list", "") ?: ""
        if (rawString.isBlank()) {
            itemsList = defaultWeekdays()
            return
        }
        val trimmed = rawString.trim()
        if (trimmed.startsWith("[")) {
            try {
                val arr = JSONArray(trimmed)
                val parsed = ArrayList<HorarioWidgetRow>(arr.length())
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    parsed.add(
                        HorarioWidgetRow(
                            dayName = obj.optString("day", ""),
                            content = obj.optString("content", "Ningún evento"),
                        )
                    )
                }
                itemsList = if (parsed.isEmpty()) defaultWeekdays() else parsed
                return
            } catch (_: Exception) {
                itemsList = defaultWeekdays()
                return
            }
        }
        itemsList = rawString.split("|||").map { entry ->
            val parts = entry.split("###")
            HorarioWidgetRow(
                dayName = parts.getOrElse(0) { "" },
                content = parts.getOrElse(1) { "" }.replace("\\n", "\n"),
            )
        }
    }

    override fun onDestroy() {
        itemsList = emptyList()
    }

    override fun getCount(): Int {
        return itemsList.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_horario_item)
        if (position < 0 || position >= itemsList.size) {
            rv.setTextViewText(R.id.item_day, "")
            rv.setTextViewText(R.id.item_content, "Ningún evento")
            rv.setTextColor(R.id.item_content, 0xFF888888.toInt())
            return rv
        }

        val item = itemsList[position]
        rv.setTextViewText(R.id.item_day, item.dayName)

        if (item.content.isBlank() || item.content == "Ningún evento") {
            rv.setTextViewText(R.id.item_content, "Ningún evento")
            rv.setTextColor(R.id.item_content, 0xFF888888.toInt())
        } else {
            rv.setTextViewText(R.id.item_content, item.content)
            rv.setTextColor(R.id.item_content, 0xFFFFFFFF.toInt())
        }

        val fillInIntent = Intent()
        rv.setOnClickFillInIntent(R.id.widget_item_container, fillInIntent)
        return rv
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
