package com.example.notas

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin

class HorarioWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return HorarioRemoteViewsFactory(this.applicationContext, intent)
    }
}

class HorarioRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private var itemsList: List<String> = emptyList()

    override fun onCreate() {
    }

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        val rawString = widgetData.getString("horario_list", "")
        if (rawString != null && rawString.isNotEmpty()) {
            itemsList = rawString.split("|||")
        } else {
            itemsList = listOf("Lunes###Ningún evento", "Martes###Ningún evento", "Miércoles###Ningún evento", "Jueves###Ningún evento", "Viernes###Ningún evento")
        }
    }

    override fun onDestroy() {
        itemsList = emptyList()
    }

    override fun getCount(): Int {
        return itemsList.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        val itemText = itemsList[position]
        val parts = itemText.split("###")
        val dayName = if (parts.isNotEmpty()) parts[0] else ""
        val content = if (parts.size > 1) parts[1] else ""
        
        // We can use a different layout depending on if it's an event or "Ningún evento"
        val rv = RemoteViews(context.packageName, R.layout.widget_horario_item)
        rv.setTextViewText(R.id.item_day, dayName)
        
        if (content == "Ningún evento") {
            rv.setTextViewText(R.id.item_content, content)
            rv.setTextColor(R.id.item_content, 0xFF888888.toInt()) // Gray color for empty
        } else {
            // Replace newlines with actual newlines in UI
            rv.setTextViewText(R.id.item_content, content.replace("\\n", "\n"))
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
