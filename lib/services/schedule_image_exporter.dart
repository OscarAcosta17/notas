import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../models/aula_course.dart';
import '../models/clase_horario.dart';
import '../utils/schedule_blocks.dart';
import 'app_cache_service.dart';

class ScheduleImageExporter {
  static const List<String> _dias = [
    'LUNES',
    'MARTES',
    'MIÉRCOLES',
    'JUEVES',
    'VIERNES',
  ];

  static Future<void> exportHorarioImage(
    List<ClaseHorario> clases,
    String semesterName,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    const colWidth = 220.0;
    const rowHeight = 90.0;
    const headerHeight = 60.0;
    const timeColWidth = 160.0;
    const margin = 40.0;

    final bloques = ScheduleBlocks.blockAxisLabels;
    final width = margin * 2 + timeColWidth + colWidth * 5;
    final height = margin * 2 + headerHeight + rowHeight * bloques.length;

    // Background
    final paintBg = Paint()..color = const Color(0xFFF8F5F0);
    canvas.drawRect(Rect.fromLTWH(0, 0, width, height), paintBg);

    final linePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    // Draw Headers
    for (var i = 0; i < _dias.length; i++) {
      final rect = Rect.fromLTWH(
        margin + timeColWidth + i * colWidth,
        margin,
        colWidth,
        headerHeight,
      );
      canvas.drawRect(rect, linePaint);
      _drawText(
        canvas,
        _dias[i],
        rect,
        true,
        Colors.black87,
        Alignment.center,
        18,
      );
    }

    // Draw Time Column & Rows
    for (var r = 0; r < bloques.length; r++) {
      final rect = Rect.fromLTWH(
        margin,
        margin + headerHeight + r * rowHeight,
        timeColWidth,
        rowHeight,
      );
      canvas.drawRect(rect, linePaint);
      _drawText(
        canvas,
        bloques[r],
        rect,
        true,
        Colors.black87,
        Alignment.center,
        16,
      );

      // Draw empty cells
      for (var c = 0; c < _dias.length; c++) {
        final cellRect = Rect.fromLTWH(
          margin + timeColWidth + c * colWidth,
          margin + headerHeight + r * rowHeight,
          colWidth,
          rowHeight,
        );
        canvas.drawRect(cellRect, linePaint);
      }
    }

    // Colors for subjects
    const colors = [
      Color(0xFFF19C99),
      Color(0xFF90B4CE),
      Color(0xFFC3B1E1),
      Color(0xFFB5E48C),
      Color(0xFFF9DC5C),
      Color(0xFFF4A261),
      Color(0xFF8ECAE6),
    ];

    final subjectColors = <String, Color>{};
    var colorIdx = 0;

    // Group classes by grid cell (col, row)
    final grid = <String, List<ClaseHorario>>{};
    for (final clase in clases) {
      if (!subjectColors.containsKey(clase.subjectName)) {
        subjectColors[clase.subjectName] = colors[colorIdx % colors.length];
        colorIdx++;
      }

      final col = clase.diaSemana - 1;
      final row = ScheduleBlocks.rowIndexForBlock(clase.bloque);
      if (row == null || col < 0 || col > 4) continue;

      final key = '${col}_$row';
      grid.putIfAbsent(key, () => []).add(clase);
    }

    // Draw classes handling overlaps
    for (final entry in grid.entries) {
      final parts = entry.key.split('_');
      final col = int.parse(parts[0]);
      final row = int.parse(parts[1]);
      final cellClases = entry.value;

      final n = cellClases.length;
      final splitWidth = colWidth / n;

      for (var i = 0; i < n; i++) {
        final clase = cellClases[i];
        final subRect = Rect.fromLTWH(
          margin + timeColWidth + col * colWidth + i * splitWidth,
          margin + headerHeight + row * rowHeight,
          splitWidth,
          rowHeight,
        );

        final fillPaint = Paint()
          ..color = subjectColors[clase.subjectName]!
          ..style = PaintingStyle.fill;
        canvas.drawRect(subRect, fillPaint);
        canvas.drawRect(subRect, linePaint);

        canvas.save();
        canvas.clipRect(subRect.deflate(2));

        if (clase.paralelo.isNotEmpty) {
          _drawText(
            canvas,
            clase.paralelo,
            Rect.fromLTWH(
              subRect.left + 4,
              subRect.top + 4,
              subRect.width - 8,
              20,
            ),
            true,
            Colors.black87,
            Alignment.topLeft,
            12,
          );
        }

        _drawText(
          canvas,
          clase.subjectName,
          Rect.fromLTWH(
            subRect.left + 4,
            subRect.top + 20,
            subRect.width - 8,
            subRect.height - 40,
          ),
          true,
          Colors.black87,
          Alignment.center,
          18,
          maxLines: 2,
        );

        if (clase.sala.isNotEmpty) {
          _drawText(
            canvas,
            clase.sala,
            Rect.fromLTWH(
              subRect.left + 4,
              subRect.bottom - 20,
              subRect.width - 8,
              16,
            ),
            true,
            Colors.black87,
            Alignment.bottomRight,
            12,
          );
        }

        canvas.restore();
      }
    }

    // Title
    _drawText(
      canvas,
      'Horario - $semesterName',
      Rect.fromLTWH(margin, 5, width - margin * 2, margin - 10),
      true,
      Colors.black,
      Alignment.center,
      28,
    );

    ui.Picture? picture;
    ui.Image? img;
    late final List<int> pngBytes;
    try {
      picture = recorder.endRecording();
      img = await picture.toImage(width.toInt(), height.toInt());
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception('No se pudo codificar la imagen del horario.');
      }
      pngBytes = byteData.buffer.asUint8List();
    } finally {
      img?.dispose();
      picture?.dispose();
    }

    final safeBase = MoodleCourse.sanitizeFileName('horario_$semesterName');
    final fileName = safeBase.toLowerCase().endsWith('.png')
        ? safeBase
        : '$safeBase.png';

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final savedPath = await FilePicker.saveFile(
        dialogTitle: 'Guardar imagen del horario',
        fileName: fileName,
        type: FileType.image,
        allowedExtensions: const ['png'],
      );
      if (savedPath != null && savedPath.trim().isNotEmpty) {
        await File(savedPath).writeAsBytes(pngBytes, flush: true);
        return;
      }
    }

    final dir = await AppCacheService.getCacheDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(pngBytes, flush: true);

    await Share.shareXFiles([XFile(file.path)], text: 'Horario - $semesterName');
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Rect rect,
    bool bold,
    Color color,
    Alignment alignment,
    double fontSize, {
    int maxLines = 1,
  }) {
    final textStyle = ui.TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
    );
    final paragraphStyle = ui.ParagraphStyle(
      textAlign: alignment == Alignment.center
          ? ui.TextAlign.center
          : alignment == Alignment.bottomRight
              ? ui.TextAlign.right
              : ui.TextAlign.left,
      maxLines: maxLines,
      ellipsis: '…',
    );
    final paragraphBuilder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(text);

    final paragraph = paragraphBuilder.build();
    paragraph.layout(ui.ParagraphConstraints(width: rect.width));

    var dy = rect.top;
    if (alignment == Alignment.center) {
      dy = rect.top + (rect.height - paragraph.height) / 2;
    } else if (alignment == Alignment.bottomRight) {
      dy = rect.bottom - paragraph.height;
    }

    canvas.drawParagraph(paragraph, Offset(rect.left, dy));
  }
}
