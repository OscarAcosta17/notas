package com.example.notas

import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray

class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return AgendaRemoteViewsFactory(this.applicationContext, intent)
    }
}

class AgendaRemoteViewsFactory(
    private val context: Context,
    private val intent: Intent
) : RemoteViewsService.RemoteViewsFactory {

    private data class AgendaWidgetRow(val title: String, val subtitle: String)

    private var evalList: List<AgendaWidgetRow> = emptyList()

    override fun onCreate() {
    }

    override fun onDataSetChanged() {
        val widgetData = HomeWidgetPlugin.getData(context)
        val rawString = widgetData.getString("evaluations_list", "") ?: ""
        if (rawString.isBlank()) {
            evalList = emptyList()
            return
        }
        val trimmed = rawString.trim()
        if (trimmed.startsWith("[")) {
            try {
                val arr = JSONArray(trimmed)
                val parsed = ArrayList<AgendaWidgetRow>(arr.length())
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    parsed.add(
                        AgendaWidgetRow(
                            title = obj.optString("title", ""),
                            subtitle = obj.optString("subtitle", ""),
                        )
                    )
                }
                evalList = parsed
                return
            } catch (_: Exception) {
                evalList = emptyList()
                return
            }
        }
        evalList = rawString.split("|||").map { entry ->
            val parts = entry.split("###")
            AgendaWidgetRow(
                title = parts.getOrElse(0) { "" },
                subtitle = parts.getOrElse(1) { "" },
            )
        }
    }

    override fun onDestroy() {
        evalList = emptyList()
    }

    override fun getCount(): Int {
        return if (evalList.isEmpty()) 1 else evalList.size
    }

    override fun getViewAt(position: Int): RemoteViews {
        val rv = RemoteViews(context.packageName, R.layout.widget_agenda_item)
        if (evalList.isEmpty() || position < 0 || position >= evalList.size) {
            rv.setTextViewText(R.id.item_title, "Ningún evento próximo")
            rv.setTextViewText(R.id.item_subtitle, "")
            return rv
        }

        val item = evalList[position]
        rv.setTextViewText(R.id.item_title, item.title)
        rv.setTextViewText(R.id.item_subtitle, item.subtitle)

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
