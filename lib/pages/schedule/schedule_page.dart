import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/auth/auth_service.dart';
import '../../models/asignatura.dart';
import '../../models/perfil_usuario.dart';
import '../../services/asignaturas_service.dart';
import '../../services/perfil_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import '../../widgets/main_bottom_nav.dart';
import '../subjects/subject_detail_page.dart';
import '../subjects/subjects_page.dart';
import 'widgets/schedule_class_edit_sheet.dart';
import '../../services/horario_conflict_service.dart';
import '../../services/time_format_service.dart';
import '../calendar/calendar_page.dart';
import '../ai/ai_chat_page.dart';
import '../notifications/notifications_page.dart';
import '../../widgets/app_status_snackbar.dart';

class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  static const List<Color> _accentColors = [
    Color(0xFF7C3AED),
    Color(0xFF2563EB),
    Color(0xFFDB2777),
    Color(0xFF0891B2),
    Color(0xFF059669),
  ];

  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final ScrollController _scrollController = ScrollController();

  final HorarioConflictService _horarioConflictService =
      HorarioConflictService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  PerfilUsuario? _perfil;

  List<Asignatura> _asignaturas = [];

  bool _cargando = true;
  bool _error = false;

  double _progresoHeader = 0;

  DateTime _lunesSemana = DateTime.now();

  int _diaSeleccionado = 0;

  bool get _espanol => _translationService.isSpanish;

  NivelEducativoPerfil get _nivel =>
      _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

  bool get _esEscolar =>
      _nivel == NivelEducativoPerfil.basica ||
      _nivel == NivelEducativoPerfil.media;

  List<Asignatura> get _asignaturasPendientes {
    return _asignaturas
        .where((asignatura) => asignatura.horario.isEmpty)
        .toList();
  }

  bool get _tieneAsignaturas => _asignaturas.isNotEmpty;

  bool get _tieneAlgunHorario {
    return _asignaturas.any((asignatura) => asignatura.horario.isNotEmpty);
  }

  List<_ScheduleDay> get _diasVisibles {
    final List<_ScheduleDay> dias = [
      const _ScheduleDay(day: DiaSemana.lunes),
      const _ScheduleDay(day: DiaSemana.martes),
      const _ScheduleDay(day: DiaSemana.miercoles),
      const _ScheduleDay(day: DiaSemana.jueves),
      const _ScheduleDay(day: DiaSemana.viernes),
    ];

    if (!_esEscolar) {
      dias.add(const _ScheduleDay(day: DiaSemana.sabado));
    }

    return dias;
  }

  _ScheduleDay get _diaActual {
    final List<_ScheduleDay> dias = _diasVisibles;

    final int index = _diaSeleccionado >= 0 && _diaSeleccionado < dias.length
        ? _diaSeleccionado
        : 0;

    return dias[index];
  }

  List<_ScheduleClass> get _clasesDiaSeleccionado {
    return _obtenerClasesDelDia(_diaActual.day);
  }

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_actualizarIdioma);

    _timeFormatService.addListener(_actualizarFormatoHora);

    _scrollController.addListener(_escucharScroll);

    _cargarDatos();
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarIdioma);

    _timeFormatService.removeListener(_actualizarFormatoHora);

    _scrollController.removeListener(_escucharScroll);

    _scrollController.dispose();

    super.dispose();
  }

  // =========================================================
  // CICLO
  // =========================================================

  void _actualizarFormatoHora() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _actualizarIdioma() {
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
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = false;
      });
    }

    try {
      final usuario = _authService.usuarioActual;

      if (usuario == null) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }

        return;
      }

      final List<dynamic> resultados = await Future.wait([
        _perfilService.obtenerPerfil(usuario.uid),
        _asignaturasService.obtenerTodas(),
      ]);

      final PerfilUsuario? perfil = resultados[0] as PerfilUsuario?;

      final List<Asignatura> asignaturas = resultados[1] as List<Asignatura>;

      if (perfil == null) {
        throw StateError('No existe el perfil del usuario.');
      }

      asignaturas.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      final _WeekSelection semana = _calcularSemanaInicial(
        perfil.nivelEducativo,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = perfil;
        _asignaturas = asignaturas;

        _lunesSemana = semana.monday;

        _diaSeleccionado = semana.selectedIndex;

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
  // SEMANA
  // =========================================================

  _WeekSelection _calcularSemanaInicial(NivelEducativoPerfil nivel) {
    final DateTime ahora = DateTime.now();

    final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day, 12);

    final bool escolar =
        nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media;

    DateTime lunes = hoy.subtract(Duration(days: hoy.weekday - 1));

    int seleccionado = 0;

    if (escolar) {
      // Básica / Media:
      //
      // Lunes a viernes.
      // Si estamos sábado o domingo,
      // mostramos la semana que comienza
      // el lunes siguiente.
      if (hoy.weekday >= DateTime.saturday) {
        lunes = lunes.add(const Duration(days: 7));

        seleccionado = 0;
      } else {
        seleccionado = hoy.weekday - 1;
      }
    } else {
      // Superior / Técnico / Curso:
      //
      // Lunes a sábado.
      // El domingo mostramos la semana
      // que comienza al día siguiente.
      if (hoy.weekday == DateTime.sunday) {
        lunes = lunes.add(const Duration(days: 7));

        seleccionado = 0;
      } else {
        seleccionado = hoy.weekday - 1;
      }
    }

    return _WeekSelection(monday: lunes, selectedIndex: seleccionado);
  }

  void _seleccionarDia(int index) {
    if (index == _diaSeleccionado) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _diaSeleccionado = index;
    });
  }

  // =========================================================
  // CLASES
  // =========================================================

  List<_ScheduleClass> _obtenerClasesDelDia(DiaSemana dia) {
    final List<_ScheduleClass> clases = [];

    for (
      int indexAsignatura = 0;
      indexAsignatura < _asignaturas.length;
      indexAsignatura++
    ) {
      final Asignatura asignatura = _asignaturas[indexAsignatura];

      final Color accent =
          _accentColors[indexAsignatura % _accentColors.length];

      for (
        int blockIndex = 0;
        blockIndex < asignatura.horario.length;
        blockIndex++
      ) {
        final BloqueHorario bloque = asignatura.horario[blockIndex];

        if (bloque.dia != dia) {
          continue;
        }

        final String profesor = asignatura.profesor?.trim() ?? '';

        final String salaBloque = bloque.sala?.trim() ?? '';

        final String salaAsignatura = asignatura.sala?.trim() ?? '';

        final String sala = salaBloque.isNotEmpty ? salaBloque : salaAsignatura;

        clases.add(
          _ScheduleClass(
            asignatura: asignatura,
            bloque: bloque,
            blockIndex: blockIndex,
            professor: profesor.isNotEmpty
                ? profesor
                : (_espanol ? 'Sin profesor' : 'No teacher'),
            room: sala.isNotEmpty ? sala : (_espanol ? 'Sin sala' : 'No room'),
            accent: accent,
          ),
        );
      }
    }

    clases.sort((a, b) => a.bloque.horaInicio.compareTo(b.bloque.horaInicio));

    return clases;
  }

  // =========================================================
  // NOMBRES
  // =========================================================

  String _nombreDia(DiaSemana dia) {
    if (_espanol) {
      switch (dia) {
        case DiaSemana.lunes:
          return 'Lunes';

        case DiaSemana.martes:
          return 'Martes';

        case DiaSemana.miercoles:
          return 'Miércoles';

        case DiaSemana.jueves:
          return 'Jueves';

        case DiaSemana.viernes:
          return 'Viernes';

        case DiaSemana.sabado:
          return 'Sábado';
      }
    }

    switch (dia) {
      case DiaSemana.lunes:
        return 'Monday';

      case DiaSemana.martes:
        return 'Tuesday';

      case DiaSemana.miercoles:
        return 'Wednesday';

      case DiaSemana.jueves:
        return 'Thursday';

      case DiaSemana.viernes:
        return 'Friday';

      case DiaSemana.sabado:
        return 'Saturday';
    }
  }

  String _nombreDiaCorto(DiaSemana dia) {
    if (_espanol) {
      switch (dia) {
        case DiaSemana.lunes:
          return 'Lun';

        case DiaSemana.martes:
          return 'Mar';

        case DiaSemana.miercoles:
          return 'Mié';

        case DiaSemana.jueves:
          return 'Jue';

        case DiaSemana.viernes:
          return 'Vie';

        case DiaSemana.sabado:
          return 'Sáb';
      }
    }

    switch (dia) {
      case DiaSemana.lunes:
        return 'Mon';

      case DiaSemana.martes:
        return 'Tue';

      case DiaSemana.miercoles:
        return 'Wed';

      case DiaSemana.jueves:
        return 'Thu';

      case DiaSemana.viernes:
        return 'Fri';

      case DiaSemana.sabado:
        return 'Sat';
    }
  }

  String _mesCorto(int mes) {
    final List<String> meses = _espanol
        ? const [
            'Ene',
            'Feb',
            'Mar',
            'Abr',
            'May',
            'Jun',
            'Jul',
            'Ago',
            'Sep',
            'Oct',
            'Nov',
            'Dic',
          ]
        : const [
            'Jan',
            'Feb',
            'Mar',
            'Apr',
            'May',
            'Jun',
            'Jul',
            'Aug',
            'Sep',
            'Oct',
            'Nov',
            'Dec',
          ];

    return meses[mes - 1];
  }

  String _fechaTexto(DateTime fecha) {
    final DateTime ahora = DateTime.now();

    if (fecha.month == ahora.month && fecha.year == ahora.year) {
      return '${fecha.day}';
    }

    return '${fecha.day} ${_mesCorto(fecha.month)}';
  }

  String _mostrarHora(String hora) {
    return _timeFormatService.formatStoredTime(context, hora);
  }

  String get _descripcionPendientes {
    final int cantidad = _asignaturasPendientes.length;

    if (_espanol) {
      if (cantidad == 1) {
        return '1 asignatura todavía no tiene bloques de horario configurados.';
      }

      return '$cantidad asignaturas todavía no tienen bloques de horario configurados.';
    }

    if (cantidad == 1) {
      return '1 subject does not have schedule blocks yet.';
    }

    return '$cantidad subjects do not have schedule blocks yet.';
  }

  // =========================================================
  // NAVEGACIÓN
  // =========================================================

  void _volverInicio() {
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  Future<void> _abrirIA() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AiChatPage(),
      ),
    );
  }

  Future<void> _abrirCalendario() async {
    HapticFeedback.selectionClick();

    await Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const CalendarPage()));
  }

  Future<void> _abrirNotificaciones() async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const NotificationsPage()),
    );
  }

  Future<void> _abrirAsignaturas() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const SubjectsPage()));

    if (!mounted) {
      return;
    }

    await _refrescar();
  }

  Future<void> _abrirAsignatura(
    Asignatura asignatura, {
    bool editar = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectDetailPage(
          subjectId: asignatura.id,
          startInEditMode: editar,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refrescar();
  }

  Future<bool> _confirmarConflictosHorario({
    required Asignatura asignatura,
    required BloqueHorario bloquePropuesto,
    required List<ConflictoHorario> conflictos,
  }) async {
    HapticFeedback.mediumImpact();

    final bool? resultado = await showDialog<bool>(
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
          titlePadding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
          contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
          actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF35291D)
                      : const Color(0xFFFFF7E8),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B),
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Text(
                  _espanol ? 'Conflicto de horario' : 'Schedule conflict',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _espanol
                    ? 'El horario que quieres guardar para "${asignatura.nombre}" se superpone con ${conflictos.length == 1 ? 'otra clase' : 'otras clases'}.'
                    : 'The schedule you want to save for "${asignatura.nombre}" overlaps with ${conflictos.length == 1 ? 'another class' : 'other classes'}.',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFB8BEC9)
                      : const Color(0xFF6B7280),
                  height: 1.45,
                ),
              ),

              const SizedBox(height: 15),

              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF222229)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: oscuro
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.edit_calendar_outlined,
                      color: _primaryColor,
                      size: 20,
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        '${_nombreDia(bloquePropuesto.dia)} · '
                        '${_mostrarHora(bloquePropuesto.horaInicio)} – '
                        '${_mostrarHora(bloquePropuesto.horaFin)}',
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF1F2937),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              for (final ConflictoHorario conflicto in conflictos) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF2A2020)
                        : const Color(0xFFFFF5F5),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: oscuro
                          ? const Color(0xFF563030)
                          : const Color(0xFFFECACA),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFFEF4444),
                        size: 20,
                      ),

                      const SizedBox(width: 11),

                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              conflicto.asignatura.nombre,
                              style: TextStyle(
                                color: oscuro
                                    ? const Color(0xFFF8FAFC)
                                    : const Color(0xFF1F2937),
                                fontWeight: FontWeight.w700,
                              ),
                            ),

                            const SizedBox(height: 3),

                            Text(
                              '${_mostrarHora(conflicto.bloque.horaInicio)} – '
                              '${_mostrarHora(conflicto.bloque.horaFin)}',
                              style: const TextStyle(
                                color: Color(0xFFEF4444),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: Text(_espanol ? 'Volver y corregir' : 'Go back'),
            ),

            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: const Color(0xFF1F1600),
              ),
              child: Text(
                _espanol ? 'Guardar de todos modos' : 'Save anyway',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    return resultado ?? false;
  }

  Future<void> _guardarBloqueEditado(
    _ScheduleClass clase,
    BloqueHorario bloqueEditado,
  ) async {
    final Asignatura original = clase.asignatura;

    if (clase.blockIndex < 0 || clase.blockIndex >= original.horario.length) {
      return;
    }

    final List<ConflictoHorario> conflictos = _horarioConflictService
        .buscarConflictos(
          asignaturas: _asignaturas,
          asignaturaId: original.id,
          bloquePropuesto: bloqueEditado,
          bloqueIndexIgnorar: clase.blockIndex,
        );

    if (conflictos.isNotEmpty) {
      final bool guardarIgual = await _confirmarConflictosHorario(
        asignatura: original,
        bloquePropuesto: bloqueEditado,
        conflictos: conflictos,
      );

      if (!mounted || !guardarIgual) {
        return;
      }
    }

    final List<BloqueHorario> horario = [...original.horario];

    horario[clase.blockIndex] = bloqueEditado;

    horario.sort((a, b) {
      final int diferenciaDia = _ordenDia(a.dia) - _ordenDia(b.dia);

      if (diferenciaDia != 0) {
        return diferenciaDia;
      }

      return a.horaInicio.compareTo(b.horaInicio);
    });

    final Asignatura actualizada = Asignatura(
      id: original.id,
      nombre: original.nombre,
      profesor: original.profesor,
      correoProfesor: original.correoProfesor,
      sala: original.sala,
      periodo: original.periodo,
      horario: horario,
      estado: original.estado,
      origen: original.origen,
      sigla: original.sigla,
      seccion: original.seccion,
      creditos: original.creditos,
      semestreMalla: original.semestreMalla,
      cursoNivel: original.cursoNivel,
      anioAcademico: original.anioAcademico,
      modalidad: original.modalidad,
      lugar: original.lugar,
      institucion: original.institucion,
      prerrequisitosIds: [...original.prerrequisitosIds],
      asignaturasSiguientesIds: [...original.asignaturasSiguientesIds],
    );

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) {
        return const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator(color: _primaryColor)),
        );
      },
    );

    try {
      await _asignaturasService.actualizar(actualizada);

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      await _refrescar();

      if (!mounted) {
        return;
      }

      final int nuevoIndice = _diasVisibles.indexWhere(
        (dia) => dia.day == bloqueEditado.dia,
      );

      if (nuevoIndice >= 0) {
        setState(() {
          _diaSeleccionado = nuevoIndice;
        });
      }

      HapticFeedback.mediumImpact();

      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'Clase actualizada correctamente.'
            : 'Class updated successfully.',
        type: AppStatusType.success,
        bottomMargin: 92,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      HapticFeedback.heavyImpact();

      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'No pudimos actualizar la clase.'
            : 'We could not update the class.',
        type: AppStatusType.error,
        bottomMargin: 92,
      );
    }
  }

  int _ordenDia(DiaSemana dia) {
    switch (dia) {
      case DiaSemana.lunes:
        return 1;
      case DiaSemana.martes:
        return 2;
      case DiaSemana.miercoles:
        return 3;
      case DiaSemana.jueves:
        return 4;
      case DiaSemana.viernes:
        return 5;
      case DiaSemana.sabado:
        return 6;
    }
  }

  Future<void> _mostrarResumenClase(_ScheduleClass clase) async {
    HapticFeedback.selectionClick();

    final Asignatura asignatura = clase.asignatura;

    final String correoProfesor = asignatura.correoProfesor?.trim() ?? '';

    final String salaBloque = clase.bloque.sala?.trim() ?? '';

    final String salaAsignatura = asignatura.sala?.trim() ?? '';

    final String sala = salaBloque.isNotEmpty
        ? salaBloque
        : salaAsignatura.isNotEmpty
        ? salaAsignatura
        : (_espanol ? 'Sin sala' : 'No room');

    final String? accion = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (sheetContext) {
        final bool oscuro =
            Theme.of(sheetContext).brightness == Brightness.dark;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF18181D) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: oscuro
                    ? const Color(0xFF303038)
                    : const Color(0xFFE7EAF0),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF4B4B53)
                        : const Color(0xFFD5D9E0),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: clase.accent.withValues(
                        alpha: oscuro ? 0.18 : 0.10,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      Ionicons.bookOutline,
                      color: clase.accent,
                      size: 25,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _espanol ? 'ASIGNATURA' : 'SUBJECT',
                          style: const TextStyle(
                            color: _primaryColor,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          asignatura.nombre,
                          style: TextStyle(
                            color: oscuro
                                ? const Color(0xFFF8FAFC)
                                : const Color(0xFF111827),
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 5),

                        Text(
                          '${_nombreDia(clase.bloque.dia)} · '
                          '${_mostrarHora(clase.bloque.horaInicio)} – '
                          '${_mostrarHora(clase.bloque.horaFin)}',
                          style: TextStyle(
                            color: oscuro
                                ? const Color(0xFFA9B1BF)
                                : const Color(0xFF6B7280),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 8),

                  PopupMenuButton<String>(
                    tooltip: '',
                    color: oscuro ? const Color(0xFF222229) : Colors.white,
                    surfaceTintColor: Colors.transparent,
                    elevation: 10,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    onSelected: (value) {
                      Navigator.of(sheetContext).pop(value);
                    },
                    itemBuilder: (context) {
                      return [
                        PopupMenuItem<String>(
                          value: 'edit',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.edit_outlined,
                                color: _primaryColor,
                                size: 20,
                              ),

                              const SizedBox(width: 11),

                              Text(
                                _espanol ? 'Editar clase' : 'Edit class',
                                style: TextStyle(
                                  color: oscuro
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF1F2937),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),

                        PopupMenuItem<String>(
                          value: 'details',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.menu_book_outlined,
                                color: _primaryColor,
                                size: 20,
                              ),

                              const SizedBox(width: 11),

                              Text(
                                _espanol ? 'Ver más detalle' : 'View details',
                                style: TextStyle(
                                  color: oscuro
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF1F2937),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ];
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: oscuro
                            ? const Color(0xFF24242A)
                            : const Color(0xFFF3F4F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.more_horiz_rounded,
                        color: _primaryColor,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF222229)
                      : const Color(0xFFFAFBFC),
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: oscuro
                        ? const Color(0xFF34343C)
                        : const Color(0xFFE7EAF0),
                  ),
                ),
                child: Column(
                  children: [
                    _buildClassInfoRow(
                      oscuro: oscuro,
                      icon: Ionicons.timeOutline,
                      label: _espanol ? 'Horario' : 'Schedule',
                      value:
                          '${_nombreDia(clase.bloque.dia)} · '
                          '${_mostrarHora(clase.bloque.horaInicio)} – '
                          '${_mostrarHora(clase.bloque.horaFin)}',
                    ),

                    const SizedBox(height: 15),

                    _buildClassInfoRow(
                      oscuro: oscuro,
                      icon: Ionicons.personOutline,
                      label: _espanol ? 'Profesor/a' : 'Teacher',
                      value: clase.professor,
                    ),

                    if (correoProfesor.isNotEmpty) ...[
                      const SizedBox(height: 15),

                      _buildClassInfoRow(
                        oscuro: oscuro,
                        icon: Ionicons.mailOutline,
                        label: _espanol
                            ? 'Correo del profesor'
                            : 'Teacher email',
                        value: correoProfesor,
                      ),
                    ],

                    const SizedBox(height: 15),

                    _buildClassInfoRow(
                      oscuro: oscuro,
                      icon: Ionicons.locationOutline,
                      label: _espanol ? 'Sala' : 'Room',
                      value: sala,
                    ),

                    if (_esEscolar &&
                        asignatura.cursoNivel?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 15),

                      _buildClassInfoRow(
                        oscuro: oscuro,
                        icon: Ionicons.schoolOutline,
                        label: _espanol ? 'Curso' : 'Grade',
                        value: asignatura.cursoNivel!.trim(),
                      ),
                    ],

                    if (!_esEscolar &&
                        asignatura.sigla?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 15),

                      _buildClassInfoRow(
                        oscuro: oscuro,
                        icon: Icons.tag_outlined,
                        label: _espanol ? 'Sigla' : 'Code',
                        value: asignatura.sigla!.trim(),
                      ),
                    ],

                    if (!_esEscolar &&
                        asignatura.seccion?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 15),

                      _buildClassInfoRow(
                        oscuro: oscuro,
                        icon: Icons.groups_outlined,
                        label: _espanol ? 'Sección' : 'Section',
                        value: asignatura.seccion!.trim(),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || accion == null) {
      return;
    }

    if (accion == 'details') {
      await _abrirAsignatura(clase.asignatura);

      return;
    }

    if (accion == 'edit') {
      final BloqueHorario? bloqueEditado = await showScheduleClassEditSheet(
        context: context,
        block: clase.bloque,
        spanish: _espanol,
        school: _esEscolar,
      );

      if (!mounted || bloqueEditado == null) {
        return;
      }

      await _guardarBloqueEditado(clase, bloqueEditado);
    }
  }

  Widget _buildClassInfoRow({
    required bool oscuro,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primaryColor, size: 19),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFF8993A2)
                      : const Color(0xFF6B7280),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                value,
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF1F2937),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // =========================================================
  // GESTIONAR HORARIOS
  // =========================================================

  Future<void> _gestionarHorarios() async {
    HapticFeedback.selectionClick();

    if (_asignaturas.isEmpty) {
      await _abrirAsignaturas();
      return;
    }

    final Asignatura? seleccion = await showModalBottomSheet<Asignatura>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (sheetContext) {
        final bool oscuro =
            Theme.of(sheetContext).brightness == Brightness.dark;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
          ),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF18181D) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(
              top: BorderSide(
                color: oscuro
                    ? const Color(0xFF303038)
                    : const Color(0xFFE7EAF0),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF4B4B53)
                      : const Color(0xFFD5D9E0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 20, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _espanol ? 'HORARIOS' : 'SCHEDULES',
                            style: const TextStyle(
                              color: _primaryColor,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            _espanol
                                ? 'Gestionar horarios'
                                : 'Manage schedules',
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF111827),
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),

                          const SizedBox(height: 5),

                          Text(
                            _espanol
                                ? 'Selecciona una asignatura para revisar o completar su horario.'
                                : 'Select a subject to review or complete its schedule.',
                            style: TextStyle(
                              color: oscuro
                                  ? const Color(0xFFA9B1BF)
                                  : const Color(0xFF6B7280),
                              fontSize: 12.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),

                    AppPressable(
                      scale: 0.88,
                      child: IconButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: oscuro
                              ? const Color(0xFF24242A)
                              : const Color(0xFFF3F4F7),
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 22),
                  itemCount: _asignaturas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) {
                    final Asignatura asignatura = _asignaturas[index];

                    final int bloques = asignatura.horario.length;

                    final bool pendiente = bloques == 0;

                    return AppPressable(
                      scale: 0.985,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          HapticFeedback.selectionClick();

                          Navigator.of(sheetContext).pop(asignatura);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: oscuro
                                ? const Color(0xFF222229)
                                : const Color(0xFFFAFBFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: pendiente
                                  ? const Color(0xFF5B5FEF)
                                  : (oscuro
                                        ? const Color(0xFF34343C)
                                        : const Color(0xFFE7EAF0)),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: oscuro
                                      ? const Color(0xFF292936)
                                      : const Color(0xFFEEF0FF),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  pendiente
                                      ? Icons.schedule_outlined
                                      : Icons.event_available_outlined,
                                  color: _primaryColor,
                                ),
                              ),

                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      asignatura.nombre,
                                      style: TextStyle(
                                        color: oscuro
                                            ? const Color(0xFFF8FAFC)
                                            : const Color(0xFF1F2937),
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),

                                    const SizedBox(height: 4),

                                    Text(
                                      pendiente
                                          ? (_espanol
                                                ? 'Sin horario configurado'
                                                : 'No schedule configured')
                                          : (_espanol
                                                ? '$bloques ${bloques == 1 ? 'bloque configurado' : 'bloques configurados'}'
                                                : '$bloques ${bloques == 1 ? 'block configured' : 'blocks configured'}'),
                                      style: TextStyle(
                                        color: pendiente
                                            ? _primaryColor
                                            : (oscuro
                                                  ? const Color(0xFFA9B1BF)
                                                  : const Color(0xFF6B7280)),
                                        fontSize: 12,
                                        fontWeight: pendiente
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(width: 8),

                              Text(
                                pendiente
                                    ? (_espanol ? 'Configurar' : 'Set up')
                                    : (_espanol ? 'Revisar' : 'Review'),
                                style: const TextStyle(
                                  color: _primaryColor,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              const SizedBox(width: 3),

                              const Icon(
                                Icons.chevron_right_rounded,
                                color: _primaryColor,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted || seleccion == null) {
      return;
    }

    final bool pendiente = seleccion.horario.isEmpty;

    await _abrirAsignatura(seleccion, editar: pendiente);
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
                  padding: const EdgeInsets.fromLTRB(8, 22, 8, 112),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 820),
                        child: _buildHeader(oscuro),
                      ),
                    ),

                    const SizedBox(height: 25),

                    if (_cargando)
                      _buildLoading(oscuro)
                    else if (_error || _perfil == null)
                      _buildError(oscuro)
                    else
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 820),
                          child: _buildContent(oscuro),
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
              title: _espanol ? 'Horario' : 'Schedule',
              trailing: _buildCompactManageButton(oscuro),
            ),
          ),

          MainBottomNav(
            currentIndex: 1,

            onHome: _volverInicio,

            onSchedule: () {},

            onAi: _abrirIA,

            onCalendar: _abrirCalendario,

            onNotifications: _abrirNotificaciones,
          ),
        ],
      ),
    );
  }

  Widget _buildContent(bool oscuro) {
    if (!_tieneAsignaturas) {
      return AppReveal(child: _buildNoSubjects(oscuro));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppReveal(child: _buildWeekSelector(oscuro)),

        if (_asignaturasPendientes.isNotEmpty) ...[
          const SizedBox(height: 17),

          AppReveal(
            delay: const Duration(milliseconds: 60),
            child: _buildPendingCard(oscuro),
          ),
        ],

        const SizedBox(height: 23),

        AppReveal(
          delay: const Duration(milliseconds: 100),
          child: _buildDaySummary(oscuro),
        ),

        const SizedBox(height: 14),

        AppReveal(
          delay: const Duration(milliseconds: 140),
          child: _clasesDiaSeleccionado.isEmpty
              ? _buildEmptyDay(oscuro)
              : _buildClassesList(oscuro),
        ),
      ],
    );
  }

  // =========================================================
  // HEADER
  // =========================================================

  Widget _buildHeader(bool oscuro) {
    return Transform.translate(
      offset: Offset(0, -10 * _progresoHeader),
      child: Transform.scale(
        alignment: Alignment.topLeft,
        scale: 1 - (0.015 * _progresoHeader),
        child: Opacity(
          opacity: 1 - _progresoHeader,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'EDUCFLOW AI',
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _espanol ? 'Horario' : 'Schedule',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 32,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _espanol
                          ? 'Consulta tus clases y mantén organizada tu semana académica.'
                          : 'View your classes and keep your academic week organized.',
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

              const SizedBox(width: 12),

              AppPressable(
                scale: 0.90,
                child: IconButton(
                  onPressed: _gestionarHorarios,
                  tooltip: _espanol ? 'Gestionar horarios' : 'Manage schedules',
                  style: IconButton.styleFrom(
                    backgroundColor: _primaryColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(48, 48),
                    maximumSize: const Size(48, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  icon: const Icon(Ionicons.addOutline, size: 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactManageButton(bool oscuro) {
    return AppPressable(
      scale: 0.90,
      child: IconButton(
        onPressed: _gestionarHorarios,
        tooltip: '',
        style: IconButton.styleFrom(
          backgroundColor: _primaryColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(38, 38),
          maximumSize: const Size(38, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        icon: const Icon(Icons.add_rounded, size: 20),
      ),
    );
  }

  // =========================================================
  // SELECTOR SEMANAL
  // =========================================================

  Widget _buildWeekSelector(bool oscuro) {
    final List<_ScheduleDay> dias = _diasVisibles;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF18181D) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          for (int index = 0; index < dias.length; index++)
            Expanded(
              child: _buildDayButton(
                oscuro: oscuro,
                day: dias[index],
                index: index,
                selected: _diaSeleccionado == index,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayButton({
    required bool oscuro,
    required _ScheduleDay day,
    required int index,
    required bool selected,
  }) {
    final DateTime fecha = _lunesSemana.add(Duration(days: index));

    return AppPressable(
      scale: 0.94,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _seleccionarDia(index);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.22, 1, 0.36, 1),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? _primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _nombreDiaCorto(day.day),
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (oscuro
                            ? const Color(0xFFB8BEC9)
                            : const Color(0xFF6B7280)),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                _fechaTexto(fecha),
                maxLines: 1,
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : (oscuro
                            ? const Color(0xFFF1F4F8)
                            : const Color(0xFF374151)),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // =========================================================
  // PENDIENTES
  // =========================================================

  Widget _buildPendingCard(bool oscuro) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF1D1D27) : const Color(0xFFF7F7FF),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: oscuro ? const Color(0xFF3A3A56) : const Color(0xFFDFE2FF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF29293A) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_outlined,
              color: _primaryColor,
              size: 23,
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol
                      ? 'Tienes horarios pendientes'
                      : 'You have pending schedules',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _descripcionPendientes,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12.5,
                    height: 1.35,
                  ),
                ),

                const SizedBox(height: 9),

                AppPressable(
                  child: TextButton(
                    onPressed: _gestionarHorarios,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _espanol ? 'Completar horarios' : 'Complete schedules',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // RESUMEN DEL DÍA
  // =========================================================

  Widget _buildDaySummary(bool oscuro) {
    final int cantidad = _clasesDiaSeleccionado.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _espanol ? 'DÍA SELECCIONADO' : 'SELECTED DAY',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFF8993A2)
                        : const Color(0xFF6B7280),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  _nombreDia(_diaActual.day),
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF111827),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              _espanol
                  ? '$cantidad ${cantidad == 1 ? 'clase' : 'clases'}'
                  : '$cantidad ${cantidad == 1 ? 'class' : 'classes'}',
              style: const TextStyle(
                color: _primaryColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CLASES
  // =========================================================

  Widget _buildClassesList(bool oscuro) {
    final List<_ScheduleClass> clases = _clasesDiaSeleccionado;

    return Column(
      children: [
        for (int index = 0; index < clases.length; index++) ...[
          _buildClassCard(clases[index], oscuro),

          if (index != clases.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildClassCard(_ScheduleClass clase, bool oscuro) {
    return AppPressable(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _mostrarResumenClase(clase);
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF18181D) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 62,
                decoration: BoxDecoration(
                  color: clase.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              const SizedBox(width: 13),

              SizedBox(
                width: 62,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _mostrarHora(clase.bloque.horaInicio),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _mostrarHora(clase.bloque.horaFin),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFF8F98A8)
                            : const Color(0xFF9CA3AF),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ASIGNATURA',
                      style: TextStyle(
                        color: _primaryColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      clase.asignatura.nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        _buildClassMeta(
                          icon: Ionicons.locationOutline,
                          text: clase.room,
                          oscuro: oscuro,
                        ),

                        _buildClassMeta(
                          icon: Ionicons.personOutline,
                          text: clase.professor,
                          oscuro: oscuro,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 5),

              Icon(
                Icons.chevron_right_rounded,
                color: oscuro
                    ? const Color(0xFF737B8A)
                    : const Color(0xFF9CA3AF),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClassMeta({
    required IconData icon,
    required String text,
    required bool oscuro,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: oscuro ? const Color(0xFF9099A8) : const Color(0xFF6B7280),
        ),

        const SizedBox(width: 4),

        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // ESTADOS VACÍOS
  // =========================================================

  Widget _buildNoSubjects(bool oscuro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 38),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF18181D) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.menu_book_outlined,
              color: _primaryColor,
              size: 30,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _espanol
                ? 'Primero agrega tus asignaturas'
                : 'Add your subjects first',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 9),

          Text(
            _espanol
                ? 'Necesitamos saber qué asignaturas estás cursando antes de poder organizar tu horario.'
                : 'We need to know which subjects you are taking before organizing your schedule.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 13.5,
              height: 1.45,
            ),
          ),

          const SizedBox(height: 22),

          SizedBox(
            width: double.infinity,
            height: 49,
            child: ElevatedButton.icon(
              onPressed: _abrirAsignaturas,
              icon: const Icon(Icons.add_rounded),
              label: Text(_espanol ? 'Agregar asignaturas' : 'Add subjects'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyDay(bool oscuro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF18181D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: oscuro ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292936) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(19),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              color: _primaryColor,
              size: 28,
            ),
          ),

          const SizedBox(height: 16),

          Text(
            !_tieneAlgunHorario
                ? (_espanol
                      ? 'Aún no has configurado tu horario'
                      : 'Your schedule is not set up yet')
                : (_espanol ? 'Sin clases este día' : 'No classes this day'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 8),

          Text(
            !_tieneAlgunHorario
                ? (_espanol
                      ? 'Completa los horarios de tus asignaturas para comenzar a organizar tu semana.'
                      : 'Complete your subject schedules to start organizing your week.')
                : (_espanol
                      ? 'No tienes bloques programados para ${_nombreDia(_diaActual.day).toLowerCase()}.'
                      : 'You have no blocks scheduled for ${_nombreDia(_diaActual.day)}.'),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 13,
              height: 1.45,
            ),
          ),

          if (_asignaturasPendientes.isNotEmpty) ...[
            const SizedBox(height: 19),

            TextButton.icon(
              onPressed: _gestionarHorarios,
              icon: const Icon(Icons.edit_calendar_outlined),
              label: Text(_espanol ? 'Gestionar horarios' : 'Manage schedules'),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // CARGA / ERROR
  // =========================================================

  Widget _buildLoading(bool oscuro) {
    return SizedBox(
      height: 360,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              color: _primaryColor,
              strokeWidth: 3,
            ),

            const SizedBox(height: 14),

            Text(
              _espanol ? 'Cargando tu horario...' : 'Loading your schedule...',
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFA9B1BF)
                    : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(bool oscuro) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF321D22) : const Color(0xFFFFF1F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: oscuro ? const Color(0xFF5F2B31) : const Color(0xFFFECACA),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),

              const SizedBox(width: 14),

              Expanded(
                child: Text(
                  _espanol
                      ? 'No pudimos cargar tu horario. Desliza hacia abajo para intentarlo nuevamente.'
                      : 'We could not load your schedule. Pull down to try again.',
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
        ),
      ),
    );
  }
}

// ===========================================================
// MODELOS VISUALES
// ===========================================================

class _ScheduleDay {
  const _ScheduleDay({required this.day});

  final DiaSemana day;
}

class _ScheduleClass {
  const _ScheduleClass({
    required this.asignatura,
    required this.bloque,
    required this.blockIndex,
    required this.professor,
    required this.room,
    required this.accent,
  });

  final Asignatura asignatura;
  final BloqueHorario bloque;

  /// Posición real de este bloque dentro de
  /// asignatura.horario.
  ///
  /// Esto nos permite editar exactamente
  /// la clase que el usuario tocó.
  final int blockIndex;

  final String professor;
  final String room;

  final Color accent;
}

class _WeekSelection {
  const _WeekSelection({required this.monday, required this.selectedIndex});

  final DateTime monday;

  final int selectedIndex;
}
