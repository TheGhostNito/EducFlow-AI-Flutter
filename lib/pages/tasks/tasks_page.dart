import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../models/asignatura.dart';
import '../../models/tarea.dart';
import '../../services/asignaturas_service.dart';
import '../../services/tareas_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/app_swipe_delete.dart';
import 'widgets/task_edit_sheet.dart';
import 'widgets/task_detail_sheet.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final TareasService _tareasService = TareasService.instance;

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  final ScrollController _scrollController = ScrollController();

  List<Tarea> _tareas = [];
  List<Asignatura> _asignaturas = [];

  bool _cargando = true;
  bool _error = false;
  bool _mostrarCompletadas = false;
  String? _procesandoTareaId;

  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  List<Tarea> get _tareasVisibles {
    return _tareas.where((tarea) {
      if (_mostrarCompletadas) {
        return tarea.completada;
      }

      return tarea.pendiente;
    }).toList();
  }

  int get _pendientes => _tareas.where((tarea) => tarea.pendiente).length;

  int get _completadas => _tareas.where((tarea) => tarea.completada).length;

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_actualizarPantalla);

    _timeFormatService.addListener(_actualizarPantalla);

    _scrollController.addListener(_escucharScroll);

    _cargarDatos();
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarPantalla);

    _timeFormatService.removeListener(_actualizarPantalla);

    _scrollController.removeListener(_escucharScroll);

    _scrollController.dispose();

    super.dispose();
  }

  void _actualizarPantalla() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _escucharScroll() {
    if (!_scrollController.hasClients) {
      return;
    }

    final double offset = _scrollController.offset;

    const double inicio = 45;
    const double fin = 145;

    final double progreso = ((offset - inicio) / (fin - inicio)).clamp(
      0.0,
      1.0,
    );

    if ((progreso - _progresoHeader).abs() < 0.01) {
      return;
    }

    setState(() {
      _progresoHeader = progreso;
    });
  }

  // =========================================================
  // CARGA
  // =========================================================

  Future<void> _cargarDatos({bool silencioso = false}) async {
    if (!silencioso && mounted) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }

    try {
      final List<Tarea> tareas = await _tareasService.obtenerTodas();

      final List<Asignatura> asignaturas = await _asignaturasService
          .obtenerTodas();

      if (!mounted) {
        return;
      }

      setState(() {
        _tareas = tareas;
        _asignaturas = asignaturas;
        _error = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      if (!silencioso) {
        setState(() {
          _error = true;
        });
      }
    } finally {
      if (mounted && !silencioso) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  Future<void> _refrescar() async {
    await _cargarDatos(silencioso: true);
  }

  // =========================================================
  // NAVEGACIÓN
  // =========================================================

  void _volver() {
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  Future<void> _nuevaTarea() async {
    HapticFeedback.selectionClick();

    final TaskEditResult? result = await showTaskEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      await _tareasService.crear(
        titulo: result.title,
        descripcion: result.description,
        asignaturaId: result.subjectId,
        prioridad: result.priority,
        fechaEntrega: result.dueDate,
        horaEntrega: result.dueTime,
      );

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      setState(() {
        _mostrarCompletadas = false;
      });

      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF158A5B),
            content: Text(
              _espanol
                  ? 'Tarea creada correctamente.'
                  : 'Task created successfully.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text(
              _espanol
                  ? 'No pudimos crear la tarea.'
                  : 'We could not create the task.',
            ),
          ),
        );
    }
  }

  Future<void> _abrirDetalleTarea(Tarea tarea) async {
    HapticFeedback.selectionClick();

    final TaskDetailAction? action = await showTaskDetailSheet(
      context: context,
      task: tarea,
      subjectName: _nombreAsignatura(tarea),
      dueText: _fechaTarea(tarea),
      priorityText: _nombrePrioridad(tarea.prioridad),
      spanish: _espanol,
    );

    if (!mounted || action == null) {
      return;
    }

    switch (action) {
      case TaskDetailAction.edit:
        await _editarTarea(tarea);
        break;

      case TaskDetailAction.delete:
        await _solicitarEliminarTarea(tarea);
        break;
    }
  }

  Future<void> _editarTarea(Tarea tarea) async {
    final TaskEditResult? result = await showTaskEditSheet(
      context: context,
      subjects: _asignaturas,
      spanish: _espanol,
      task: tarea,
    );

    if (!mounted || result == null) {
      return;
    }

    try {
      final Tarea actualizada = tarea.copyWith(
        titulo: result.title,

        descripcion: result.description,
        limpiarDescripcion: result.description == null,

        asignaturaId: result.subjectId,
        limpiarAsignatura: result.subjectId == null,

        prioridad: result.priority,

        fechaEntrega: result.dueDate,
        limpiarFechaEntrega: result.dueDate == null,

        horaEntrega: result.dueTime,
        limpiarHoraEntrega: result.dueTime == null,
      );

      await _tareasService.actualizar(actualizada);

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF158A5B),
            content: Text(
              _espanol
                  ? 'Tarea actualizada correctamente.'
                  : 'Task updated successfully.',
            ),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text(
              _espanol
                  ? 'No pudimos actualizar la tarea.'
                  : 'We could not update the task.',
            ),
          ),
        );
    }
  }

  Future<void> _solicitarEliminarTarea(Tarea tarea) async {
    final bool confirmar = await _confirmarEliminarTarea(tarea);

    if (!confirmar || !mounted) {
      return;
    }

    await _eliminarTarea(tarea);
  }

  Future<bool> _confirmarEliminarTarea(Tarea tarea) async {
    HapticFeedback.mediumImpact();

    final bool? confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (dialogContext) {
        final bool oscuro =
            Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: oscuro ? const Color(0xFF18181D) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(_espanol ? '¿Eliminar tarea?' : 'Delete task?'),
          content: Text(
            _espanol
                ? '¿Seguro que quieres eliminar "${tarea.titulo}"?\n\nEsta acción no se puede deshacer.'
                : 'Are you sure you want to delete "${tarea.titulo}"?\n\nThis action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_espanol ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: Text(_espanol ? 'Eliminar' : 'Delete'),
            ),
          ],
        );
      },
    );

    return confirmar == true;
  }

  Future<void> _eliminarTarea(Tarea tarea) async {
    try {
      await _tareasService.eliminar(tarea.id);

      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF158A5B),
            content: Text(_espanol ? 'Tarea eliminada.' : 'Task deleted.'),
          ),
        );
    } catch (_) {
      if (!mounted) {
        return;
      }

      await _cargarDatos(silencioso: true);

      if (!mounted) {
        return;
      }

      HapticFeedback.heavyImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text(
              _espanol
                  ? 'No pudimos eliminar la tarea.'
                  : 'We could not delete the task.',
            ),
          ),
        );
    }
  }

  // =========================================================
  // ESTADO
  // =========================================================

  Future<void> _cambiarEstado(Tarea tarea) async {
    if (_procesandoTareaId != null) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _procesandoTareaId = tarea.id;
    });

    try {
      final Tarea actualizada = await _tareasService.cambiarEstado(
        tarea: tarea,
        completada: !tarea.completada,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        final int index = _tareas.indexWhere((item) => item.id == tarea.id);

        if (index >= 0) {
          _tareas[index] = actualizada;
        }
      });

      HapticFeedback.mediumImpact();
    } catch (_) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFFB42318),
            content: Text(
              _espanol
                  ? 'No pudimos actualizar la tarea.'
                  : 'We could not update the task.',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _procesandoTareaId = null;
        });
      }
    }
  }

  // =========================================================
  // HELPERS
  // =========================================================

  String _nombreAsignatura(Tarea tarea) {
    final String? id = tarea.asignaturaId;

    if (id == null || id.trim().isEmpty) {
      return _espanol ? 'Tarea general' : 'General task';
    }

    for (final Asignatura asignatura in _asignaturas) {
      if (asignatura.id == id) {
        return asignatura.nombre;
      }
    }

    return _espanol ? 'Asignatura no disponible' : 'Subject unavailable';
  }

  String _nombrePrioridad(PrioridadTarea prioridad) {
    switch (prioridad) {
      case PrioridadTarea.baja:
        return _espanol ? 'Baja' : 'Low';

      case PrioridadTarea.media:
        return _espanol ? 'Media' : 'Medium';

      case PrioridadTarea.alta:
        return _espanol ? 'Alta' : 'High';
    }
  }

  Color _colorPrioridad(PrioridadTarea prioridad) {
    switch (prioridad) {
      case PrioridadTarea.baja:
        return const Color(0xFF059669);

      case PrioridadTarea.media:
        return const Color(0xFFF59E0B);

      case PrioridadTarea.alta:
        return const Color(0xFFEF4444);
    }
  }

  bool _tareaVencida(Tarea tarea) {
    if (tarea.completada) {
      return false;
    }

    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return false;
    }

    final DateTime ahora = DateTime.now();

    final DateTime fechaLimpia = DateTime(fecha.year, fecha.month, fecha.day);

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);

    // Si la fecha ya pasó.
    if (fechaLimpia.isBefore(hoy)) {
      return true;
    }

    // Si es una fecha futura.
    if (fechaLimpia.isAfter(hoy)) {
      return false;
    }

    // Es hoy. Si no tiene hora límite,
    // consideramos que vence durante todo el día.
    final String? hora = tarea.horaEntrega;

    if (hora == null || hora.trim().isEmpty) {
      return false;
    }

    final List<String> partes = hora.split(':');

    if (partes.length != 2) {
      return false;
    }

    final int? horaLimite = int.tryParse(partes[0]);

    final int? minutoLimite = int.tryParse(partes[1]);

    if (horaLimite == null || minutoLimite == null) {
      return false;
    }

    final DateTime limite = DateTime(
      ahora.year,
      ahora.month,
      ahora.day,
      horaLimite,
      minutoLimite,
    );

    final DateTime finDelMinuto = limite.add(const Duration(minutes: 1));

    return !ahora.isBefore(finDelMinuto);
  }

  Color _colorFechaTarea(Tarea tarea) {
    if (_tareaVencida(tarea)) {
      return const Color(0xFFEF4444);
    }

    return _primaryColor;
  }

  String _fechaTarea(Tarea tarea) {
    final DateTime? fecha = tarea.fechaEntrega;

    if (fecha == null) {
      return _espanol ? 'Sin fecha límite' : 'No due date';
    }

    final DateTime hoy = DateTime.now();

    final DateTime fechaLimpia = DateTime(fecha.year, fecha.month, fecha.day);

    final DateTime hoyLimpio = DateTime(hoy.year, hoy.month, hoy.day);

    final int diferencia = fechaLimpia.difference(hoyLimpio).inDays;

    final bool vencida = _tareaVencida(tarea);

    String textoFecha;

    if (vencida) {
      if (diferencia == -1) {
        textoFecha = _espanol ? 'Vencida · Ayer' : 'Overdue · Yesterday';
      } else if (diferencia == 0) {
        textoFecha = _espanol ? 'Vencida · Hoy' : 'Overdue · Today';
      } else {
        final String fechaTexto = _espanol
            ? '${fecha.day.toString().padLeft(2, '0')}/'
                  '${fecha.month.toString().padLeft(2, '0')}/'
                  '${fecha.year}'
            : '${fecha.month.toString().padLeft(2, '0')}/'
                  '${fecha.day.toString().padLeft(2, '0')}/'
                  '${fecha.year}';

        textoFecha = _espanol
            ? 'Vencida · $fechaTexto'
            : 'Overdue · $fechaTexto';
      }
    } else if (diferencia == 0) {
      textoFecha = _espanol ? 'Hoy' : 'Today';
    } else if (diferencia == 1) {
      textoFecha = _espanol ? 'Mañana' : 'Tomorrow';
    } else {
      textoFecha = _espanol
          ? '${fecha.day.toString().padLeft(2, '0')}/'
                '${fecha.month.toString().padLeft(2, '0')}/'
                '${fecha.year}'
          : '${fecha.month.toString().padLeft(2, '0')}/'
                '${fecha.day.toString().padLeft(2, '0')}/'
                '${fecha.year}';
    }

    final String? hora = tarea.horaEntrega;

    if (hora == null || hora.trim().isEmpty) {
      return textoFecha;
    }

    return '$textoFecha · '
        '${_timeFormatService.formatStoredTime(context, hora)}';
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: RefreshIndicator(
                color: _primaryColor,
                onRefresh: _refrescar,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 50),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildHeader(oscuro),
                      ),
                    ),

                    const SizedBox(height: 28),

                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _cargando
                            ? _buildLoading()
                            : _error
                            ? _buildError(oscuro)
                            : Column(
                                children: [
                                  AppReveal(child: _buildSummary(oscuro)),

                                  const SizedBox(height: 18),

                                  AppReveal(
                                    delay: const Duration(milliseconds: 70),
                                    child: _buildFilter(oscuro),
                                  ),

                                  const SizedBox(height: 18),

                                  AppReveal(
                                    delay: const Duration(milliseconds: 120),
                                    child: _buildTasks(oscuro),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppScrollHeader(
              progress: _progresoHeader,
              title: _espanol ? 'Tareas' : 'Tasks',
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
        ],
      ),
      floatingActionButton: _cargando || _error
          ? null
          : FloatingActionButton.extended(
              onPressed: _nuevaTarea,
              backgroundColor: _primaryColor,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _espanol ? 'Nueva tarea' : 'New task',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool oscuro) {
    return Transform.translate(
      offset: Offset(0, -10 * _progresoHeader),
      child: Opacity(
        opacity: 1 - _progresoHeader,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPressable(scale: 0.86, child: _buildBackButton(oscuro)),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EDUCFLOW AI',
                    style: TextStyle(
                      color: _primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 5),

                  Text(
                    _espanol ? 'Mis tareas' : 'My tasks',
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFF8FAFC)
                          : const Color(0xFF111827),
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    _espanol
                        ? 'Organiza entregas y pendientes de tus asignaturas.'
                        : 'Organize assignments and pending work for your subjects.',
                    style: TextStyle(
                      color: oscuro
                          ? const Color(0xFFA9B1BF)
                          : const Color(0xFF6B7280),
                      fontSize: 14,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton(bool oscuro) {
    return GestureDetector(
      onTap: _volver,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF18181D) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: oscuro ? const Color(0xFF303038) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Ionicons.chevronBackOutline,
          color: oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
          size: 21,
        ),
      ),
    );
  }

  Widget _buildCompactBackButton(bool oscuro) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        onTap: _volver,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF222229) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            Ionicons.chevronBackOutline,
            color: oscuro ? const Color(0xFFE7EAF0) : const Color(0xFF374151),
            size: 19,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // RESUMEN
  // =========================================================

  Widget _buildSummary(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: _panelDecoration(oscuro),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem(
              oscuro: oscuro,
              value: '$_pendientes',
              label: _espanol ? 'Pendientes' : 'Pending',
              icon: Icons.pending_actions_outlined,
            ),
          ),

          Container(
            width: 1,
            height: 48,
            color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
          ),

          Expanded(
            child: _buildSummaryItem(
              oscuro: oscuro,
              value: '$_completadas',
              label: _espanol ? 'Completadas' : 'Completed',
              icon: Icons.task_alt_rounded,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required bool oscuro,
    required String value,
    required String label,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: _primaryColor, size: 23),

        const SizedBox(height: 7),

        Text(
          value,
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          style: TextStyle(
            color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  // =========================================================
  // FILTROS
  // =========================================================

  Widget _buildFilter(bool oscuro) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF18181D) : const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildFilterButton(
              oscuro: oscuro,
              selected: !_mostrarCompletadas,
              label: _espanol ? 'Pendientes' : 'Pending',
              onTap: () {
                HapticFeedback.selectionClick();

                setState(() {
                  _mostrarCompletadas = false;
                });
              },
            ),
          ),

          const SizedBox(width: 5),

          Expanded(
            child: _buildFilterButton(
              oscuro: oscuro,
              selected: _mostrarCompletadas,
              label: _espanol ? 'Completadas' : 'Completed',
              onTap: () {
                HapticFeedback.selectionClick();

                setState(() {
                  _mostrarCompletadas = true;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterButton({
    required bool oscuro,
    required bool selected,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        height: 43,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? (oscuro ? const Color(0xFF292936) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          boxShadow: selected && !oscuro
              ? const [
                  BoxShadow(
                    color: Color(0x120F172A),
                    blurRadius: 9,
                    offset: Offset(0, 3),
                  ),
                ]
              : const [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? _primaryColor
                : (oscuro ? const Color(0xFF8993A2) : const Color(0xFF6B7280)),
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // TAREAS
  // =========================================================

  Widget _buildTasks(bool oscuro) {
    final List<Tarea> tareas = _tareasVisibles;

    if (tareas.isEmpty) {
      return _buildEmptyState(oscuro);
    }

    return Column(
      children: [
        for (int index = 0; index < tareas.length; index++) ...[
          _buildTaskCard(tareas[index], oscuro, showSwipeTutorial: index == 0),

          if (index != tareas.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildTaskCard(
    Tarea tarea,
    bool oscuro, {
    required bool showSwipeTutorial,
  }) {
    final bool procesando = _procesandoTareaId == tarea.id;

    return AppSwipeDelete(
      key: ValueKey('swipe-tarea-${tarea.id}'),
      deleteLabel: _espanol ? 'Eliminar' : 'Delete',

      tutorialKey: showSwipeTutorial ? 'educflow-swipe-delete-tasks-v2' : null,

      tutorialTitle: _espanol ? 'Elimina deslizando' : 'Swipe to delete',

      tutorialMessage: _espanol
          ? 'Desliza una tarea hacia la izquierda para eliminarla rápidamente. Antes de borrarla, siempre te pediremos confirmación.'
          : 'Swipe a task to the left to quickly delete it. We will always ask for confirmation before deleting it.',

      tutorialButtonLabel: _espanol ? 'Entendido' : 'Got it',

      onConfirmDelete: () {
        return _confirmarEliminarTarea(tarea);
      },

      onDelete: () {
        return _eliminarTarea(tarea);
      },

      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: _panelDecoration(oscuro),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppPressable(
              scale: 0.88,
              child: GestureDetector(
                onTap: procesando
                    ? null
                    : () {
                        _cambiarEstado(tarea);
                      },
                child: SizedBox(
                  width: 38,
                  height: 38,
                  child: procesando
                      ? const Padding(
                          padding: EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _primaryColor,
                          ),
                        )
                      : Icon(
                          tarea.completada
                              ? Icons.check_circle_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: tarea.completada
                              ? const Color(0xFF059669)
                              : _primaryColor,
                          size: 27,
                        ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _abrirDetalleTarea(tarea);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tarea.titulo,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        decoration: tarea.completada
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _nombreAsignatura(tarea),
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 7),

                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _buildBadge(
                          oscuro: oscuro,
                          icon: _tareaVencida(tarea)
                              ? Icons.warning_amber_rounded
                              : Icons.calendar_today_outlined,
                          text: _fechaTarea(tarea),
                          color: _colorFechaTarea(tarea),
                        ),

                        _buildBadge(
                          oscuro: oscuro,
                          icon: Icons.flag_outlined,
                          text: _nombrePrioridad(tarea.prioridad),
                          color: _colorPrioridad(tarea.prioridad),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge({
    required bool oscuro,
    required IconData icon,
    required String text,
    Color? color,
  }) {
    final Color accent = color ?? _primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: accent, size: 14),

          const SizedBox(width: 5),

          Text(
            text,
            style: TextStyle(
              color: accent,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 32, 22, 32),
      decoration: _panelDecoration(oscuro),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(21),
            ),
            child: Icon(
              _mostrarCompletadas
                  ? Icons.task_alt_rounded
                  : Icons.checklist_rounded,
              color: _primaryColor,
              size: 31,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _mostrarCompletadas
                ? (_espanol
                      ? 'Aún no hay tareas completadas'
                      : 'No completed tasks yet')
                : (_espanol
                      ? 'No tienes tareas pendientes'
                      : 'You have no pending tasks'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            _mostrarCompletadas
                ? (_espanol
                      ? 'Las tareas que completes aparecerán aquí.'
                      : 'Tasks you complete will appear here.')
                : (_espanol
                      ? 'Agrega tu primera tarea para comenzar a organizar tus entregas.'
                      : 'Add your first task to start organizing your assignments.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              height: 1.45,
            ),
          ),

          if (!_mostrarCompletadas) ...[
            const SizedBox(height: 20),

            FilledButton.icon(
              onPressed: _nuevaTarea,
              style: FilledButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _espanol ? 'Nueva tarea' : 'New task',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // ESTADOS
  // =========================================================

  Widget _buildLoading() {
    return const SizedBox(
      height: 350,
      child: Center(
        child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
      ),
    );
  }

  Widget _buildError(bool oscuro) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF321D22) : const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),

          const SizedBox(width: 13),

          Expanded(
            child: Text(
              _espanol
                  ? 'No pudimos cargar tus tareas. Desliza hacia abajo para intentarlo nuevamente.'
                  : 'We could not load your tasks. Pull down to try again.',
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF991B1B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(bool oscuro) {
    return BoxDecoration(
      color: oscuro ? const Color(0xFF18181D) : Colors.white,
      borderRadius: BorderRadius.circular(19),
      border: Border.all(
        color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
      ),
      boxShadow: oscuro
          ? const []
          : const [
              BoxShadow(
                color: Color(0x0E0F172A),
                blurRadius: 24,
                offset: Offset(0, 8),
              ),
            ],
    );
  }
}
