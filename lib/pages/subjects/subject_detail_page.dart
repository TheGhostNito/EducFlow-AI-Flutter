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
import 'widgets/subject_edit_panel.dart';
import '../../services/horario_conflict_service.dart';
import '../../services/time_format_service.dart';

class SubjectDetailPage extends StatefulWidget {
  const SubjectDetailPage({
    super.key,
    this.subjectId,
    this.initialName,
    this.startInEditMode = false,
  }) : assert(
         subjectId != null || initialName != null,
         'Debes indicar subjectId o initialName.',
       );

  final String? subjectId;

  final String? initialName;

  final bool startInEditMode;

  bool get creating => subjectId == null && initialName != null;

  @override
  State<SubjectDetailPage> createState() => _SubjectDetailPageState();
}

class _SubjectDetailPageState extends State<SubjectDetailPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  final ScrollController _scrollController = ScrollController();

  final HorarioConflictService _horarioConflictService =
      HorarioConflictService.instance;

  PerfilUsuario? _perfil;
  Asignatura? _asignatura;

  bool _cargando = true;
  bool _error = false;
  bool _modoEdicion = false;
  bool _guardando = false;

  /// Permite saber si el documento todavía
  /// no existe en Firestore.
  bool _creando = false;

  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  NivelEducativoPerfil get _nivel =>
      _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

  bool get _esEscolar =>
      _nivel == NivelEducativoPerfil.basica ||
      _nivel == NivelEducativoPerfil.media;

  bool get _esSuperior =>
      _nivel == NivelEducativoPerfil.tecnico ||
      _nivel == NivelEducativoPerfil.superior;

  bool get _esCursoOtro =>
      _nivel == NivelEducativoPerfil.curso ||
      _nivel == NivelEducativoPerfil.otro;

  @override
  void initState() {
    super.initState();

    _creando = widget.creating;

    _modoEdicion = widget.creating || widget.startInEditMode;

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
  // CICLO / HEADER
  // =========================================================

  void _actualizarIdioma() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  void _actualizarFormatoHora() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  String _mostrarHora(String hora) {
    return _timeFormatService.formatStoredTime(context, hora);
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

  Future<void> _cargarDatos() async {
    setState(() {
      _cargando = true;
      _error = false;
    });

    try {
      final usuario = _authService.usuarioActual;

      if (usuario == null) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }

        return;
      }

      final PerfilUsuario? perfil = await _perfilService.obtenerPerfil(
        usuario.uid,
      );

      if (perfil == null) {
        throw StateError('No existe el perfil del usuario.');
      }

      Asignatura? asignatura;

      if (_creando) {
        asignatura = Asignatura(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          nombre: widget.initialName?.trim() ?? '',
          estado: EstadoAsignatura.registrada,
          origen: OrigenAsignatura.manual,

          // Contexto escolar conocido.
          cursoNivel: _esNivelEscolar(perfil.nivelEducativo)
              ? perfil.cursoActual
              : null,

          anioAcademico: _esNivelEscolar(perfil.nivelEducativo)
              ? DateTime.now().year
              : null,

          // Para cursos/capacitaciones
          // podemos reutilizar la institución
          // del perfil como valor inicial.
          institucion: _esNivelCursoOtro(perfil.nivelEducativo)
              ? perfil.nombreEstablecimiento
              : null,

          // Para educación superior sugerimos
          // el semestre actual.
          semestreMalla: _esNivelSuperior(perfil.nivelEducativo)
              ? perfil.semestreActual
              : null,
        );
      } else {
        final String? id = widget.subjectId;

        if (id == null) {
          throw StateError('No existe un identificador.');
        }

        asignatura = await _asignaturasService.obtenerPorId(id);

        if (asignatura == null) {
          throw StateError('La asignatura no existe.');
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = perfil;
        _asignatura = asignatura;
        _error = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  bool _esNivelEscolar(NivelEducativoPerfil nivel) {
    return nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media;
  }

  bool _esNivelSuperior(NivelEducativoPerfil nivel) {
    return nivel == NivelEducativoPerfil.tecnico ||
        nivel == NivelEducativoPerfil.superior;
  }

  bool _esNivelCursoOtro(NivelEducativoPerfil nivel) {
    return nivel == NivelEducativoPerfil.curso ||
        nivel == NivelEducativoPerfil.otro;
  }

  // =========================================================
  // NAVEGACIÓN / EDICIÓN
  // =========================================================

  void _volver() {
    if (_guardando) {
      return;
    }

    // Si estamos editando, la flecha vuelve
    // primero al detalle de la asignatura.
    if (_modoEdicion) {
      _cancelarEdicion();
      return;
    }

    // Si ya estamos en el detalle, entonces
    // volvemos a la pantalla de asignaturas.
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  void _iniciarEdicion() {
    if (_guardando || _asignatura == null) {
      return;
    }

    HapticFeedback.selectionClick();

    setState(() {
      _modoEdicion = true;
    });
  }

  void _cancelarEdicion() {
    if (_guardando) {
      return;
    }

    HapticFeedback.selectionClick();

    if (_creando) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _modoEdicion = false;
    });
  }

  Future<void> _solicitarEliminarAsignatura() async {
    final Asignatura? asignatura = _asignatura;

    if (asignatura == null || _guardando) {
      return;
    }

    HapticFeedback.mediumImpact();

    final bool? confirmar = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      builder: (dialogContext) {
        final bool oscuro =
            Theme.of(dialogContext).brightness == Brightness.dark;

        return AlertDialog(
          backgroundColor: oscuro ? const Color(0xFF171C25) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(_espanol ? '¿Eliminar asignatura?' : 'Delete subject?'),
          content: Text(
            _espanol
                ? '¿Seguro que quieres eliminar "${asignatura.nombre}"?\n\nTambién se eliminarán los bloques de horario asociados a esta asignatura.'
                : 'Are you sure you want to delete "${asignatura.nombre}"?\n\nIts associated schedule blocks will also be deleted.',
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

    if (confirmar != true || !mounted) {
      return;
    }

    await _eliminarAsignatura();
  }

  Future<void> _eliminarAsignatura() async {
    final Asignatura? asignatura = _asignatura;

    if (asignatura == null || _guardando) {
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      await _asignaturasService.eliminar(asignatura.id);

      if (!mounted) {
        return;
      }

      HapticFeedback.mediumImpact();

      Navigator.of(context).pop(true);
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
                  ? 'No pudimos eliminar la asignatura.'
                  : 'We could not delete the subject.',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // =========================================================
  // GUARDAR
  // =========================================================

  Future<List<_ConflictoAsignaturaDetectado>> _buscarConflictosAntesDeGuardar(
    Asignatura propuesta,
  ) async {
    if (propuesta.horario.isEmpty) {
      return const [];
    }

    final List<Asignatura> actuales = await _asignaturasService.obtenerTodas();

    // Quitamos la versión antigua de esta misma
    // asignatura y agregamos la versión que el
    // usuario está intentando guardar.
    final List<Asignatura> universo = [
      ...actuales.where((asignatura) => asignatura.id != propuesta.id),
      propuesta,
    ];

    final List<_ConflictoAsignaturaDetectado> detectados = [];

    final Set<String> claves = {};

    for (int index = 0; index < propuesta.horario.length; index++) {
      final BloqueHorario bloquePropuesto = propuesta.horario[index];

      final List<ConflictoHorario> conflictos = _horarioConflictService
          .buscarConflictos(
            asignaturas: universo,
            asignaturaId: propuesta.id,
            bloquePropuesto: bloquePropuesto,
            bloqueIndexIgnorar: index,
          );

      for (final ConflictoHorario conflicto in conflictos) {
        // Si dos bloques de la propia asignatura
        // chocan entre sí, el detector los encuentra
        // desde ambos lados. Evitamos mostrar el
        // mismo conflicto dos veces.
        if (conflicto.asignatura.id == propuesta.id &&
            conflicto.bloqueIndex < index) {
          continue;
        }

        final String clave =
            '$index|'
            '${conflicto.asignatura.id}|'
            '${conflicto.bloqueIndex}';

        if (!claves.add(clave)) {
          continue;
        }

        detectados.add(
          _ConflictoAsignaturaDetectado(
            bloquePropuestoIndex: index,
            bloquePropuesto: bloquePropuesto,
            conflicto: conflicto,
          ),
        );
      }
    }

    return detectados;
  }

  Future<bool> _confirmarConflictosAntesDeGuardar({
    required Asignatura propuesta,
    required List<_ConflictoAsignaturaDetectado> conflictos,
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
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _espanol
                      ? 'Encontramos ${conflictos.length == 1 ? 'un horario que se superpone' : '${conflictos.length} horarios que se superponen'} antes de guardar "${propuesta.nombre}".'
                      : 'We found ${conflictos.length == 1 ? 'an overlapping schedule' : '${conflictos.length} overlapping schedules'} before saving "${propuesta.nombre}".',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFB8BEC9)
                        : const Color(0xFF6B7280),
                    height: 1.45,
                  ),
                ),

                const SizedBox(height: 15),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final item in conflictos) ...[
                          Container(
                            width: double.infinity,
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
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.edit_calendar_outlined,
                                      color: _primaryColor,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${_nombreDia(item.bloquePropuesto.dia)} · '
                                        '${_mostrarHora(item.bloquePropuesto.horaInicio)} – '
                                        '${_mostrarHora(item.bloquePropuesto.horaFin)}',
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

                                const SizedBox(height: 10),

                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(11),
                                  decoration: BoxDecoration(
                                    color: oscuro
                                        ? const Color(0xFF2A2020)
                                        : const Color(0xFFFFF5F5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.schedule_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 18,
                                      ),

                                      const SizedBox(width: 9),

                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.conflicto.asignatura.id ==
                                                      propuesta.id
                                                  ? (_espanol
                                                        ? '${propuesta.nombre} · otro bloque'
                                                        : '${propuesta.nombre} · another block')
                                                  : item
                                                        .conflicto
                                                        .asignatura
                                                        .nombre,
                                              style: TextStyle(
                                                color: oscuro
                                                    ? const Color(0xFFF8FAFC)
                                                    : const Color(0xFF1F2937),
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),

                                            const SizedBox(height: 3),

                                            Text(
                                              '${_mostrarHora(item.conflicto.bloque.horaInicio)} – '
                                              '${_mostrarHora(item.conflicto.bloque.horaFin)}',
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
                              ],
                            ),
                          ),

                          const SizedBox(height: 9),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
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

  Future<void> _guardarAsignatura(Asignatura asignatura) async {
    if (_guardando) {
      return;
    }

    setState(() {
      _guardando = true;
    });

    try {
      final List<_ConflictoAsignaturaDetectado> conflictos =
          await _buscarConflictosAntesDeGuardar(asignatura);

      if (!mounted) {
        return;
      }

      if (conflictos.isNotEmpty) {
        final bool guardarIgual = await _confirmarConflictosAntesDeGuardar(
          propuesta: asignatura,
          conflictos: conflictos,
        );

        if (!mounted || !guardarIgual) {
          return;
        }
      }

      if (_creando) {
        await _asignaturasService.agregar(asignatura);
      } else {
        await _asignaturasService.actualizar(asignatura);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _asignatura = asignatura;
        _creando = false;
        _modoEdicion = false;
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
                  ? 'Asignatura guardada correctamente.'
                  : 'Subject saved successfully.',
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
                  ? 'No pudimos guardar la asignatura. Inténtalo nuevamente.'
                  : 'We could not save the subject. Please try again.',
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _guardando = false;
        });
      }
    }
  }

  // =========================================================
  // NOMBRES
  // =========================================================

  String _nombreEstado(EstadoAsignatura estado) {
    if (_espanol) {
      switch (estado) {
        case EstadoAsignatura.registrada:
          return 'Registrada';

        case EstadoAsignatura.pendiente:
          return 'Pendiente';

        case EstadoAsignatura.enCurso:
          return 'En curso';

        case EstadoAsignatura.aprobada:
          return 'Aprobada';

        case EstadoAsignatura.reprobada:
          return 'Reprobada';

        case EstadoAsignatura.convalidada:
          return 'Convalidada';
      }
    }

    switch (estado) {
      case EstadoAsignatura.registrada:
        return 'Registered';

      case EstadoAsignatura.pendiente:
        return 'Pending';

      case EstadoAsignatura.enCurso:
        return 'In progress';

      case EstadoAsignatura.aprobada:
        return 'Passed';

      case EstadoAsignatura.reprobada:
        return 'Failed';

      case EstadoAsignatura.convalidada:
        return 'Validated';
    }
  }

  String _nombreOrigen(OrigenAsignatura origen) {
    if (_espanol) {
      switch (origen) {
        case OrigenAsignatura.manual:
          return 'Manual';

        case OrigenAsignatura.malla:
          return 'Malla';

        case OrigenAsignatura.horario:
          return 'Horario';
      }
    }

    switch (origen) {
      case OrigenAsignatura.manual:
        return 'Manual';

      case OrigenAsignatura.malla:
        return 'Curriculum';

      case OrigenAsignatura.horario:
        return 'Schedule';
    }
  }

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

  String _nombreModalidad(String valor) {
    if (_espanol) {
      switch (valor) {
        case 'presencial':
          return 'Presencial';

        case 'online':
          return 'Online';

        case 'hibrida':
          return 'Híbrida';

        default:
          return valor;
      }
    }

    switch (valor) {
      case 'presencial':
        return 'In person';

      case 'online':
        return 'Online';

      case 'hibrida':
        return 'Hybrid';

      default:
        return valor;
    }
  }

  String get _sinDefinir => _espanol ? 'Sin definir' : 'Not defined';

  // =========================================================
  // HORARIO ORDENADO
  // =========================================================

  List<BloqueHorario> get _horarioOrdenado {
    final List<BloqueHorario> bloques = [...?_asignatura?.horario];

    bloques.sort((a, b) {
      final int diferenciaDia = _ordenDia(a.dia) - _ordenDia(b.dia);

      if (diferenciaDia != 0) {
        return diferenciaDia;
      }

      return a.horaInicio.compareTo(b.horaInicio);
    });

    return bloques;
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

  String _salaParaBloque(BloqueHorario bloque) {
    final String salaBloque = bloque.sala?.trim() ?? '';

    if (salaBloque.isNotEmpty) {
      return salaBloque;
    }

    final String salaGeneral = _asignatura?.sala?.trim() ?? '';

    if (salaGeneral.isNotEmpty) {
      return salaGeneral;
    }

    return _espanol ? 'Sin sala' : 'No room';
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
            child: ColoredBox(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                bottom: false,
                child: ListView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(10, 24, 10, 60),
                  children: [
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _buildHeader(oscuro),
                      ),
                    ),

                    const SizedBox(height: 28),

                    if (_cargando)
                      _buildLoading()
                    else if (_error || _perfil == null || _asignatura == null)
                      _buildError(oscuro)
                    else if (_modoEdicion)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: AppReveal(
                            child: SubjectEditPanel(
                              subject: _asignatura!,
                              profile: _perfil!,
                              spanish: _espanol,
                              saving: _guardando,
                              creating: _creando,
                              onCancel: _cancelarEdicion,
                              onSave: _guardarAsignatura,
                            ),
                          ),
                        ),
                      )
                    else
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Column(
                            children: [
                              AppReveal(child: _buildHero(oscuro)),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 70),
                                child: _buildInformation(oscuro),
                              ),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 120),
                                child: _buildAcademic(oscuro),
                              ),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 170),
                                child: _buildSchedule(oscuro),
                              ),

                              const SizedBox(height: 26),

                              AppReveal(
                                delay: const Duration(milliseconds: 220),
                                child: _buildFutureTools(oscuro),
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
              title: _modoEdicion
                  ? (_espanol ? 'Configurar asignatura' : 'Set up subject')
                  : (_espanol ? 'Detalle de asignatura' : 'Subject details'),
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
        ],
      ),
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
                      _modoEdicion
                          ? (_espanol
                                ? 'Configurar asignatura'
                                : 'Set up subject')
                          : (_espanol
                                ? 'Detalle de asignatura'
                                : 'Subject details'),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 31,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _modoEdicion
                          ? (_espanol
                                ? 'Completa la información que conozcas. Podrás modificarla más adelante.'
                                : 'Complete the information you know. You can change it later.')
                          : (_espanol
                                ? 'Consulta y administra la información de esta asignatura.'
                                : 'View and manage the information for this subject.'),
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
      ),
    );
  }

  Widget _buildBackButton(bool oscuro) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _volver,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: oscuro ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE2E6ED),
          ),
        ),
        child: Icon(
          Ionicons.chevronBackOutline,
          color: oscuro ? const Color(0xFFE5E9F0) : const Color(0xFF374151),
          size: 21,
        ),
      ),
    );
  }

  Widget _buildCompactBackButton(bool oscuro) {
    return AppPressable(
      scale: 0.86,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _volver,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF202631) : const Color(0xFFF4F5F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: oscuro ? const Color(0xFF343C48) : const Color(0xFFE2E6ED),
            ),
          ),
          child: Icon(
            Ionicons.chevronBackOutline,
            color: oscuro ? const Color(0xFFE5E9F0) : const Color(0xFF374151),
            size: 19,
          ),
        ),
      ),
    );
  }

  // =========================================================
  // HERO
  // =========================================================

  Widget _buildHero(bool oscuro) {
    final Asignatura asignatura = _asignatura!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF191F29) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppPressable(
                scale: 0.94,
                child: TextButton.icon(
                  onPressed: _guardando ? null : _iniciarEdicion,
                  icon: const Icon(Ionicons.createOutline, size: 17),
                  label: Text(_espanol ? 'Editar' : 'Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryColor,
                    backgroundColor: oscuro
                        ? const Color(0xFF252B40)
                        : const Color(0xFFF7F7FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              PopupMenuButton<String>(
                enabled: !_guardando,
                tooltip: _espanol ? 'Más opciones' : 'More options',
                color: oscuro ? const Color(0xFF202631) : Colors.white,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                onSelected: (value) {
                  if (value == 'delete') {
                    _solicitarEliminarAsignatura();
                  }
                },
                itemBuilder: (context) {
                  return [
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(
                            Icons.delete_outline_rounded,
                            color: Color(0xFFDC2626),
                            size: 20,
                          ),

                          const SizedBox(width: 10),

                          Text(
                            _espanol ? 'Eliminar asignatura' : 'Delete subject',
                            style: const TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ];
                },
                child: Container(
                  width: 42,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF252B40)
                        : const Color(0xFFF7F7FF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: _primaryColor,
                    size: 21,
                  ),
                ),
              ),
            ],
          ),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 66,
                height: 66,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF6869F5), Color(0xFF4E51DF)],
                  ),
                  borderRadius: BorderRadius.circular(19),
                ),
                child: const Icon(
                  Ionicons.bookOutline,
                  color: Colors.white,
                  size: 30,
                ),
              ),

              const SizedBox(width: 16),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _espanol
                          ? (_esSuperior
                                ? 'RAMO'
                                : _esCursoOtro
                                ? 'MATERIA'
                                : 'ASIGNATURA')
                          : 'SUBJECT',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      asignatura.nombre,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBadge(_nombreEstado(asignatura.estado), oscuro),

              _buildBadge(
                _nombreOrigen(asignatura.origen),
                oscuro,
                secondary: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, bool oscuro, {bool secondary = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: secondary
            ? (oscuro ? const Color(0xFF202631) : const Color(0xFFF3F4F7))
            : (oscuro ? const Color(0xFF292F47) : const Color(0xFFEEF0FF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: secondary
              ? (oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280))
              : _primaryColor,
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // =========================================================
  // INFORMACIÓN
  // =========================================================

  Widget _buildInformation(bool oscuro) {
    final Asignatura asignatura = _asignatura!;

    final List<_DetailItem> items = [
      _DetailItem(
        icon: Icons.menu_book_outlined,
        label: _espanol
            ? (_esSuperior
                  ? 'Nombre del ramo'
                  : _esCursoOtro
                  ? 'Materia o módulo'
                  : 'Asignatura')
            : 'Subject',
        value: asignatura.nombre,
      ),

      _DetailItem(
        icon: Icons.person_outline,
        label: _espanol
            ? (_esCursoOtro ? 'Profesor/a o relator' : 'Profesor/a')
            : (_esCursoOtro ? 'Teacher or instructor' : 'Teacher'),
        value: _valor(asignatura.profesor),
      ),

      _DetailItem(
        icon: Icons.mail_outline,
        label: _espanol ? 'Correo del profesor' : 'Teacher email',
        value: _valor(asignatura.correoProfesor),
      ),

      if (_esEscolar)
        _DetailItem(
          icon: Icons.meeting_room_outlined,
          label: _espanol ? 'Sala habitual' : 'Usual classroom',
          value: _valor(asignatura.sala),
        ),

      if (_esSuperior) ...[
        _DetailItem(
          icon: Icons.tag_outlined,
          label: _espanol ? 'Sigla' : 'Code',
          value: _valor(asignatura.sigla),
        ),

        _DetailItem(
          icon: Icons.groups_outlined,
          label: _espanol ? 'Sección' : 'Section',
          value: _valor(asignatura.seccion),
        ),

        _DetailItem(
          icon: Icons.workspace_premium_outlined,
          label: _espanol ? 'Créditos' : 'Credits',
          value: asignatura.creditos?.toString() ?? _sinDefinir,
        ),

        _DetailItem(
          icon: Icons.meeting_room_outlined,
          label: _espanol ? 'Sala predeterminada' : 'Default room',
          value: _valor(asignatura.sala),
        ),
      ],

      if (_esCursoOtro) ...[
        _DetailItem(
          icon: Icons.business_outlined,
          label: _espanol ? 'Institución' : 'Institution',
          value: _valor(asignatura.institucion),
        ),

        _DetailItem(
          icon: Icons.devices_outlined,
          label: _espanol ? 'Modalidad' : 'Modality',
          value: asignatura.modalidad?.trim().isNotEmpty == true
              ? _nombreModalidad(asignatura.modalidad!)
              : _sinDefinir,
        ),

        _DetailItem(
          icon: Icons.location_on_outlined,
          label: _espanol ? 'Lugar' : 'Place',
          value: _valor(asignatura.lugar),
        ),
      ],
    ];

    return _buildSection(
      oscuro: oscuro,
      eyebrow: _espanol ? 'INFORMACIÓN' : 'INFORMATION',
      title: _espanol ? 'Datos principales' : 'Main information',
      child: _buildDetailGrid(items, oscuro),
    );
  }

  // =========================================================
  // ACADÉMICO
  // =========================================================

  Widget _buildAcademic(bool oscuro) {
    final Asignatura asignatura = _asignatura!;

    final List<_DetailItem> items = [];

    if (_esEscolar) {
      items.addAll([
        _DetailItem(
          icon: Icons.school_outlined,
          label: _espanol ? 'Curso' : 'Grade',
          value: _valor(asignatura.cursoNivel),
        ),

        _DetailItem(
          icon: Icons.calendar_today_outlined,
          label: _espanol ? 'Año académico' : 'Academic year',
          value: asignatura.anioAcademico?.toString() ?? _sinDefinir,
        ),
      ]);
    }

    if (_esSuperior) {
      items.add(
        _DetailItem(
          icon: Icons.layers_outlined,
          label: _espanol ? 'Semestre en la malla' : 'Curriculum semester',
          value: asignatura.semestreMalla == null
              ? _sinDefinir
              : (_espanol
                    ? '${asignatura.semestreMalla}° semestre'
                    : 'Semester ${asignatura.semestreMalla}'),
        ),
      );
    }

    if (asignatura.periodo?.trim().isNotEmpty == true) {
      items.add(
        _DetailItem(
          icon: Icons.date_range_outlined,
          label: _espanol ? 'Período' : 'Period',
          value: asignatura.periodo!,
        ),
      );
    }

    items.addAll([
      _DetailItem(
        icon: Icons.check_circle_outline,
        label: _espanol ? 'Estado' : 'Status',
        value: _nombreEstado(asignatura.estado),
      ),

      _DetailItem(
        icon: Icons.auto_awesome_outlined,
        label: _espanol ? 'Origen' : 'Origin',
        value: _nombreOrigen(asignatura.origen),
      ),
    ]);

    return _buildSection(
      oscuro: oscuro,
      eyebrow: _espanol ? 'ACADÉMICO' : 'ACADEMIC',
      title: _espanol ? 'Contexto académico' : 'Academic context',
      child: _buildDetailGrid(items, oscuro),
    );
  }

  String _valor(String? value) {
    final String clean = value?.trim() ?? '';

    return clean.isEmpty ? _sinDefinir : clean;
  }

  // =========================================================
  // HORARIO
  // =========================================================

  Widget _buildSchedule(bool oscuro) {
    final List<BloqueHorario> bloques = _horarioOrdenado;

    return _buildSection(
      oscuro: oscuro,
      eyebrow: _espanol ? 'HORARIO' : 'SCHEDULE',
      title: _espanol ? 'Bloques de clases' : 'Class blocks',
      trailing: TextButton.icon(
        onPressed: _iniciarEdicion,
        icon: const Icon(Icons.edit_calendar_outlined, size: 18),
        label: Text(_espanol ? 'Editar' : 'Edit'),
      ),
      child: bloques.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: oscuro
                    ? const Color(0xFF202631)
                    : const Color(0xFFFAFBFC),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: oscuro
                      ? const Color(0xFF343C48)
                      : const Color(0xFFE7EAF0),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.calendar_today_outlined,
                    color: _primaryColor,
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Text(
                      _espanol
                          ? 'Esta asignatura todavía no tiene horario configurado.'
                          : 'This subject does not have a schedule yet.',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : Column(
              children: [
                for (int index = 0; index < bloques.length; index++) ...[
                  _buildScheduleItem(bloques[index], oscuro),

                  if (index != bloques.length - 1) const SizedBox(height: 10),
                ],
              ],
            ),
    );
  }

  Widget _buildScheduleItem(BloqueHorario bloque, bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: oscuro ? const Color(0xFF343C48) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292F47) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              color: _primaryColor,
              size: 22,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nombreDia(bloque.dia),
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  '${_mostrarHora(bloque.horaInicio)} – '
                  '${_mostrarHora(bloque.horaFin)}',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  _salaParaBloque(bloque),
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 12,
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
  // HERRAMIENTAS FUTURAS
  // =========================================================

  Widget _buildFutureTools(bool oscuro) {
    return _buildSection(
      oscuro: oscuro,
      eyebrow: _espanol ? 'HERRAMIENTAS' : 'TOOLS',
      title: _espanol ? 'Para esta asignatura' : 'For this subject',
      child: Column(
        children: [
          _buildFutureTool(
            oscuro: oscuro,
            icon: Icons.assignment_outlined,
            title: _espanol ? 'Evaluaciones' : 'Assessments',
          ),

          const SizedBox(height: 10),

          _buildFutureTool(
            oscuro: oscuro,
            icon: Icons.check_box_outlined,
            title: _espanol ? 'Tareas' : 'Tasks',
          ),

          if (_esSuperior) ...[
            const SizedBox(height: 10),

            _buildFutureTool(
              oscuro: oscuro,
              icon: Icons.account_tree_outlined,
              title: _espanol ? 'Prerrequisitos' : 'Prerequisites',
            ),
          ],

          const SizedBox(height: 10),

          _buildFutureTool(
            oscuro: oscuro,
            icon: Icons.auto_awesome_outlined,
            title: 'EduFlow AI',
          ),
        ],
      ),
    );
  }

  Widget _buildFutureTool({
    required bool oscuro,
    required IconData icon,
    required String title,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: oscuro ? const Color(0xFF343C48) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: _primaryColor, size: 21),

          const SizedBox(width: 12),

          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: oscuro
                    ? const Color(0xFFF8FAFC)
                    : const Color(0xFF1F2937),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          Text(
            _espanol ? 'Próximamente' : 'Coming soon',
            style: TextStyle(
              color: oscuro ? const Color(0xFF7F899A) : const Color(0xFF9CA3AF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================
  // COMPONENTES BASE
  // =========================================================

  Widget _buildSection({
    required bool oscuro,
    required String eyebrow,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF191F29) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      eyebrow,
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      title,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              ?trailing,
            ],
          ),

          const SizedBox(height: 17),

          child,
        ],
      ),
    );
  }

  Widget _buildDetailGrid(List<_DetailItem> items, bool oscuro) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool dosColumnas = constraints.maxWidth >= 600;

        if (!dosColumnas) {
          return Column(
            children: [
              for (int index = 0; index < items.length; index++) ...[
                _buildDetailItem(items[index], oscuro),

                if (index != items.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => SizedBox(
                  width: (constraints.maxWidth - 10) / 2,
                  child: _buildDetailItem(item, oscuro),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildDetailItem(_DetailItem item, bool oscuro) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: oscuro ? const Color(0xFF343C48) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 43,
            height: 43,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292F47) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(item.icon, color: _primaryColor, size: 20),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  item.value,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const SizedBox(
      height: 360,
      child: Center(
        child: CircularProgressIndicator(color: _primaryColor, strokeWidth: 3),
      ),
    );
  }

  Widget _buildError(bool oscuro) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
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
                      ? 'No pudimos cargar la asignatura.'
                      : 'We could not load the subject.',
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

class _DetailItem {
  const _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _ConflictoAsignaturaDetectado {
  const _ConflictoAsignaturaDetectado({
    required this.bloquePropuestoIndex,
    required this.bloquePropuesto,
    required this.conflicto,
  });

  final int bloquePropuestoIndex;

  final BloqueHorario bloquePropuesto;

  final ConflictoHorario conflicto;
}
