package com.example.notas

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin

class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return AgendaRemoteViewsFactory(this.applicationContext, intent)
    }
}

class AgendaRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private var evalList: List<String> = emptyList()

    override fun onCreate() {
        // Inicializar datos si es necesario
    }

    override fun onDataSetChanged() {
        // This is called when we call notifyAppWidgetViewDataChanged
        val widgetData = HomeWidgetPlugin.getData(context)
        val rawString = widgetData.getString("evaluations_list", "")
        if (rawString != null && rawString.isNotEmpty()) {
            evalList = rawString.split("|||") // usaremos "|||" como separador de items
        } else {
            evalList = emptyList()
        }
    }

    override fun onDestroy() {
        evalList = emptyList()
    }

    override fun getCount(): Int {
        return if (evalList.isEmpty()) 1 else evalList.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        if (evalList.isEmpty()) {
            val rv = RemoteViews(context.packageName, R.layout.widget_agenda_item)
            rv.setTextViewText(R.id.item_title, "Ningún evento próximo")
            rv.setTextViewText(R.id.item_subtitle, "")
            return rv
        }

        val itemText = evalList[position]
        val parts = itemText.split("###") // "Title###Subtitle"
        val title = if (parts.isNotEmpty()) parts[0] else ""
        val subtitle = if (parts.size > 1) parts[1] else ""

        val rv = RemoteViews(context.packageName, R.layout.widget_agenda_item)
        rv.setTextViewText(R.id.item_title, title)
        rv.setTextViewText(R.id.item_subtitle, subtitle)
        
        // Setup fill-in intent for clicking
        val fillInIntent = Intent()
        fillInIntent.putExtra("EXTRA_ITEM", position)
        rv.setOnClickFillInIntent(R.id.widget_item_container, fillInIntent)
        
        return rv
    }

    override fun getLoadingView(): RemoteViews? {
        return null
    }

    override fun getViewTypeCount(): Int {
        return 1
    }

    override fun getItemId(position: Int): Long {
        return position.toLong()
    }

    override fun hasStableIds(): Boolean {
        return true
    }
}
