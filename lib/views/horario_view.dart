import 'package:flutter/material.dart';
import '../models/clase_horario.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';

class HorarioView extends StatefulWidget {
  final int semesterId;
  const HorarioView({super.key, required this.semesterId});

  @override
  State<HorarioView> createState() => _HorarioViewState();
}

class _HorarioViewState extends State<HorarioView> {
  bool _isLoading = true;
  List<ClaseHorario> _clases = [];
  bool _notificationsEnabled = true;

  final List<String> _dias = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes'];

  @override
  void initState() {
    super.initState();
    _loadHorario();
  }
  
  @override
  void didUpdateWidget(HorarioView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.semesterId != widget.semesterId) {
      _loadHorario();
    }
  }

  Future<void> _loadHorario() async {
    final db = DatabaseHelper.instance;
    final maps = await db.queryHorariosBySemester(widget.semesterId);
    setState(() {
      _clases = maps.map((e) => ClaseHorario.fromMap(e)).toList();
      _isLoading = false;
    });
  }

  String _formatBlock(int bloque) {
    switch (bloque) {
      case 1: return '08:15 - 09:25';
      case 3: return '09:40 - 10:50';
      case 5: return '11:05 - 12:15';
      case 7: return '12:30 - 13:40';
      case 9: return '14:40 - 15:50';
      case 11: return '16:05 - 17:15';
      case 13: return '17:30 - 18:40';
      case 15: return '18:55 - 20:05';
      default: return 'Desconocido';
    }
  }

  Future<void> _addClase(String subjectName, int diaSemana, int bloque, String sala, String paralelo) async {
    final nueva = ClaseHorario(
      semesterId: widget.semesterId,
      subjectName: subjectName,
      diaSemana: diaSemana,
      bloque: bloque,
      sala: sala,
      paralelo: paralelo,
    );
    final id = await DatabaseHelper.instance.insertHorario(nueva.toMap());
    nueva.id = id;
    if (_notificationsEnabled) {
      await NotificationService.scheduleClassReminder(nueva);
    }
    _loadHorario();
  }

  Future<void> _deleteClase(ClaseHorario clase) async {
    await DatabaseHelper.instance.deleteHorario(clase.id!);
    await NotificationService.cancelClassReminder(clase.id!);
    _loadHorario();
  }

  void _showAddDialog(int diaSemana) {
    final nameCtrl = TextEditingController();
    final salaCtrl = TextEditingController();
    final paraleloCtrl = TextEditingController();
    int selectedBloque = 1;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            return AlertDialog(
              title: Text('Añadir clase al ${_dias[diaSemana - 1]}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Nombre del Ramo'),
                      textCapitalization: TextCapitalization.words,
                    ),
                    DropdownButtonFormField<int>(
                      value: selectedBloque,
                      decoration: const InputDecoration(labelText: 'Bloque'),
                      items: [1, 3, 5, 7, 9, 11, 13, 15].map((b) {
                        return DropdownMenuItem(
                          value: b,
                          child: Text('Bloque $b-${b + 1} (${_formatBlock(b)})'),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setStateSB(() => selectedBloque = val);
                      },
                    ),
                    TextField(
                      controller: salaCtrl,
                      decoration: const InputDecoration(labelText: 'Sala'),
                    ),
                    TextField(
                      controller: paraleloCtrl,
                      decoration: const InputDecoration(labelText: 'Paralelo'),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.isNotEmpty) {
                      _addClase(
                        nameCtrl.text.trim(),
                        diaSemana,
                        selectedBloque,
                        salaCtrl.text.trim(),
                        paraleloCtrl.text.trim(),
                      );
                      Navigator.pop(context);
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _toggleNotifications() async {
    if (!_notificationsEnabled) {
      final granted = await NotificationService.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso denegado. Habilítalo en ajustes.')),
          );
        }
        return;
      }
    }

    setState(() {
      _notificationsEnabled = !_notificationsEnabled;
    });

    for (var c in _clases) {
      if (_notificationsEnabled) {
        await NotificationService.scheduleClassReminder(c);
      } else {
        await NotificationService.cancelClassReminder(c.id!);
      }
    }
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_notificationsEnabled ? 'Notificaciones activadas' : 'Notificaciones desactivadas')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 5,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: Text('Horario de Clases', style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(_notificationsEnabled ? Icons.notifications_active : Icons.notifications_off),
              color: _notificationsEnabled ? Theme.of(context).colorScheme.primary : Colors.grey,
              onPressed: _toggleNotifications,
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Lun'),
              Tab(text: 'Mar'),
              Tab(text: 'Mié'),
              Tab(text: 'Jue'),
              Tab(text: 'Vie'),
            ],
          ),
        ),
        body: TabBarView(
          children: List.generate(5, (index) {
            final dia = index + 1; // 1 to 5
            final clasesDia = _clases.where((c) => c.diaSemana == dia).toList()
              ..sort((a, b) => a.bloque.compareTo(b.bloque));

            return Stack(
              children: [
                if (clasesDia.isEmpty)
                  const Center(child: Text('No hay clases este día.', style: TextStyle(color: Colors.grey)))
                else
                  ListView.builder(
                    padding: const EdgeInsets.all(16).copyWith(bottom: 100),
                    itemCount: clasesDia.length,
                    itemBuilder: (context, i) {
                      final c = clasesDia[i];
                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          title: Text(
                            c.subjectName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Bloque ${c.bloque}-${c.bloque + 1} (${_formatBlock(c.bloque)})', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('Sala: ${c.sala} | Paralelo: ${c.paralelo}'),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _deleteClase(c),
                          ),
                        ),
                      );
                    },
                  ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: FloatingActionButton(
                    heroTag: 'fab_add_clase_$dia',
                    onPressed: () => _showAddDialog(dia),
                    child: const Icon(Icons.add),
                  ),
                )
              ],
            );
          }),
        ),
      ),
    );
  }
}
