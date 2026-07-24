import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/clase_horario.dart';

class ScheduleImageExporter {
  static final List<String> _dias = ['LUNES', 'MARTES', 'MIÉRCOLES', 'JUEVES', 'VIERNES'];
  static final List<String> _bloques = [
    '1-2 (8:15-9:25)',
    '3-4 (9:40-10:50)',
    '5-6 (11:05-12:15)',
    '7-8 (12:30-13:40)',
    '9-10 (14:40-15:50)',
    '11-12 (16:05-17:15)',
    '13-14 (17:30-18:40)',
    '15-16 (18:55-20:05)',
  ];

  static Future<void> exportHorarioImage(List<ClaseHorario> clases, String semesterName) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    const double colWidth = 220.0;
    const double rowHeight = 90.0;
    const double headerHeight = 60.0;
    const double timeColWidth = 160.0;
    const double margin = 40.0;

    final double width = margin * 2 + timeColWidth + colWidth * 5;
    final double height = margin * 2 + headerHeight + rowHeight * 8;

    // Background
    final paintBg = Paint()..color = const Color(0xFFF8F5F0); // Light warm gray
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paintBg);

    final linePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw Headers
    for (int i = 0; i < 5; i++) {
      final rect = Rect.fromLTWH(margin + timeColWidth + i * colWidth, margin, colWidth, headerHeight);
      canvas.drawRect(rect, linePaint);
      _drawText(canvas, _dias[i], rect, true, Colors.black87, Alignment.center, 18);
    }

    // Draw Time Column & Rows
    for (int r = 0; r < 8; r++) {
      final rect = Rect.fromLTWH(margin, margin + headerHeight + r * rowHeight, timeColWidth, rowHeight);
      canvas.drawRect(rect, linePaint);
      _drawText(canvas, _bloques[r], rect, true, Colors.black87, Alignment.center, 16);

      // Draw empty cells
      for (int c = 0; c < 5; c++) {
        final cellRect = Rect.fromLTWH(margin + timeColWidth + c * colWidth, margin + headerHeight + r * rowHeight, colWidth, rowHeight);
        canvas.drawRect(cellRect, linePaint);
      }
    }

    // Colors for subjects
    final colors = [
      const Color(0xFFF19C99), // Reddish
      const Color(0xFF90B4CE), // Blueish
      const Color(0xFFC3B1E1), // Purple
      const Color(0xFFB5E48C), // Greenish
      const Color(0xFFF9DC5C), // Yellowish
      const Color(0xFFF4A261), // Orange
      const Color(0xFF8ECAE6), // Light blue
    ];
    
    final Map<String, Color> subjectColors = {};
    int colorIdx = 0;

    // Group classes by grid cell (col, row)
    final Map<String, List<ClaseHorario>> grid = {};
    for (var clase in clases) {
      if (!subjectColors.containsKey(clase.subjectName)) {
        subjectColors[clase.subjectName] = colors[colorIdx % colors.length];
        colorIdx++;
      }

      int col = clase.diaSemana - 1; // 1 = Lunes -> 0
      int row = 0;
      switch (clase.bloque) {
        case 1: row = 0; break;
        case 3: row = 1; break;
        case 5: row = 2; break;
        case 7: row = 3; break;
        case 9: row = 4; break;
        case 11: row = 5; break;
        case 13: row = 6; break;
        case 15: row = 7; break;
        default: continue;
      }

      if (col < 0 || col > 4) continue;
      
      String key = '${col}_${row}';
      grid.putIfAbsent(key, () => []).add(clase);
    }

    // Draw classes handling overlaps
    for (var entry in grid.entries) {
      final parts = entry.key.split('_');
      final int col = int.parse(parts[0]);
      final int row = int.parse(parts[1]);
      final List<ClaseHorario> cellClases = entry.value;

      int n = cellClases.length;
      double splitWidth = colWidth / n;

      for (int i = 0; i < n; i++) {
        var clase = cellClases[i];
        final subRect = Rect.fromLTWH(
          margin + timeColWidth + col * colWidth + i * splitWidth, 
          margin + headerHeight + row * rowHeight, 
          splitWidth, 
          rowHeight
        );

        final fillPaint = Paint()..color = subjectColors[clase.subjectName]!
                                 ..style = PaintingStyle.fill;
        canvas.drawRect(subRect, fillPaint);
        canvas.drawRect(subRect, linePaint); // Redraw border

        // Draw Class info
        
        // Top Left: Paralelo
        if (clase.paralelo.isNotEmpty) {
          _drawText(canvas, clase.paralelo, Rect.fromLTWH(subRect.left + 4, subRect.top + 4, subRect.width - 8, 20), true, Colors.black87, Alignment.topLeft, 12);
        }

        // Center: Name (large)
        _drawText(canvas, clase.subjectName, Rect.fromLTWH(subRect.left + 4, subRect.top + 20, subRect.width - 8, subRect.height - 40), true, Colors.black87, Alignment.center, 18);
        
        // Bottom Right: Sala
        if (clase.sala.isNotEmpty) {
          _drawText(canvas, clase.sala, Rect.fromLTWH(subRect.left + 4, subRect.bottom - 20, subRect.width - 8, 16), true, Colors.black87, Alignment.bottomRight, 12);
        }
      }
    }
    
    // Title
    _drawText(canvas, 'Horario - $semesterName', Rect.fromLTWH(margin, 5, width - margin * 2, margin - 10), true, Colors.black, Alignment.center, 28);

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    final buffer = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/horario_${semesterName.replaceAll(' ', '_')}.png');
    await file.writeAsBytes(buffer);

    await Share.shareXFiles([XFile(file.path)], text: 'Horario - $semesterName');
  }

  static void _drawText(Canvas canvas, String text, Rect rect, bool bold, Color color, Alignment alignment, double fontSize) {
    final textStyle = ui.TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
    );
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: alignment == Alignment.center ? ui.TextAlign.center : 
                 alignment == Alignment.bottomRight ? ui.TextAlign.right : ui.TextAlign.left,
    );
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(text);
    
    final paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: rect.width));

    double dy = rect.top;
    if (alignment == Alignment.center) {
      dy = rect.top + (rect.height - paragraph.height) / 2;
    } else if (alignment == Alignment.bottomRight) {
      dy = rect.bottom - paragraph.height;
    }

    canvas.drawParagraph(paragraph, Offset(rect.left, dy));
  }
}
