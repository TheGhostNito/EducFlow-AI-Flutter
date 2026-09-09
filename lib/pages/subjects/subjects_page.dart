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
import '../../widgets/app_status_snackbar.dart';
import 'subject_detail_page.dart';

import '../../widgets/app_swipe_delete.dart';

class SubjectsPage extends StatefulWidget {
  const SubjectsPage({super.key});

  static String? swipeTutorialKeyForUid(String? uid) {
    final String cleanUid = uid?.trim() ?? '';
    return cleanUid.isEmpty
        ? null
        : 'educflow-swipe-delete-subjects-v2-$cleanUid';
  }

  @override
  State<SubjectsPage> createState() => _SubjectsPageState();
}

class _SubjectsPageState extends State<SubjectsPage> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final AsignaturasService _asignaturasService = AsignaturasService.instance;

  final TranslationService _translationService = TranslationService.instance;

  final ScrollController _scrollController = ScrollController();

  PerfilUsuario? _perfil;

  List<Asignatura> _asignaturas = [];

  bool _cargando = true;
  bool _error = false;

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

    _translationService.addListener(_actualizarIdioma);

    _scrollController.addListener(_escucharScroll);

    _cargarDatos();
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarIdioma);

    _scrollController.removeListener(_escucharScroll);

    _scrollController.dispose();

    super.dispose();
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

      if (!mounted) {
        return;
      }

      final PerfilUsuario? perfil = resultados[0] as PerfilUsuario?;

      final List<Asignatura> asignaturas = resultados[1] as List<Asignatura>;

      asignaturas.sort(
        (a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()),
      );

      setState(() {
        _perfil = perfil;
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

  void _volver() {
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  String get _tituloAgregar {
    if (_espanol) {
      if (_esCursoOtro) {
        return 'Agregar materia o módulo';
      }

      return 'Agregar asignatura';
    }

    if (_esCursoOtro) {
      return 'Add subject or module';
    }

    return 'Add subject';
  }

  String get _descripcionAgregar {
    if (_espanol) {
      if (_esEscolar) {
        return 'Registra manualmente una asignatura de tu curso.';
      }

      if (_esSuperior) {
        return 'Agrega manualmente un ramo que estés cursando.';
      }

      return 'Registra manualmente una materia o módulo.';
    }

    if (_esEscolar) {
      return 'Manually add a subject from your grade.';
    }

    if (_esSuperior) {
      return 'Manually add a course you are taking.';
    }

    return 'Manually add a subject or module.';
  }

  String get _tituloLista {
    if (_espanol) {
      if (_esSuperior) {
        return 'MIS RAMOS';
      }

      if (_esCursoOtro) {
        return 'MIS MATERIAS';
      }

      return 'MIS ASIGNATURAS';
    }

    return 'MY SUBJECTS';
  }

  String get _tituloVacio {
    if (_espanol) {
      if (_esSuperior) {
        return 'Aún no tienes ramos';
      }

      if (_esCursoOtro) {
        return 'Aún no tienes materias';
      }

      return 'Aún no tienes asignaturas';
    }

    return 'No subjects yet';
  }

  String get _descripcionVacio {
    if (_espanol) {
      if (_esEscolar) {
        return 'Agrega las asignaturas que tienes este año para comenzar a organizar tus clases, tareas y horario.';
      }

      if (_esSuperior) {
        return 'Agrega los ramos que cursas actualmente para comenzar a organizar tu período académico.';
      }

      return 'Agrega tus materias o módulos para comenzar a organizar tu información académica.';
    }

    if (_esEscolar) {
      return 'Add the subjects you have this year to start organizing your classes, tasks and schedule.';
    }

    if (_esSuperior) {
      return 'Add the courses you are currently taking to start organizing your academic term.';
    }

    return 'Add your subjects or modules to start organizing your academic information.';
  }

  Future<void> _abrirFormulario() async {
    HapticFeedback.selectionClick();

    final String? nombre = await _mostrarFormularioAsignatura();

    if (!mounted || nombre == null || nombre.trim().isEmpty) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectDetailPage(initialName: nombre.trim()),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refrescar();
  }

  Future<String?> _mostrarFormularioAsignatura() {
    final TextEditingController controller = TextEditingController();

    return showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.72),

      builder: (sheetContext) {
        final bool oscuro =
            Theme.of(sheetContext).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bool valido = controller.text.trim().isNotEmpty;

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                decoration: BoxDecoration(
                  color: oscuro ? const Color(0xFF191F29) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                  border: Border(
                    top: BorderSide(
                      color: oscuro
                          ? const Color(0xFF303844)
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
                              ? const Color(0xFF48505E)
                              : const Color(0xFFD5D9E0),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _espanol ? 'NUEVA ASIGNATURA' : 'NEW SUBJECT',
                                style: const TextStyle(
                                  color: _primaryColor,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1,
                                ),
                              ),

                              const SizedBox(height: 5),

                              Text(
                                _tituloAgregar,
                                style: TextStyle(
                                  color: oscuro
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF111827),
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),

                        AppPressable(
                          scale: 0.88,
                          child: IconButton(
                            onPressed: () {
                              HapticFeedback.selectionClick();

                              Navigator.of(sheetContext).pop();
                            },
                            style: IconButton.styleFrom(
                              backgroundColor: oscuro
                                  ? const Color(0xFF252C38)
                                  : const Color(0xFFF3F4F7),
                              minimumSize: const Size(40, 40),
                            ),
                            icon: const Icon(Icons.close_rounded, size: 21),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 21),

                    Text(
                      _espanol
                          ? (_esCursoOtro
                                ? 'Nombre de la materia o módulo'
                                : 'Nombre de la asignatura')
                          : (_esCursoOtro
                                ? 'Subject or module name'
                                : 'Subject name'),
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFC4CAD4)
                            : const Color(0xFF4B5563),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 8),

                    TextField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 100,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) {
                        setSheetState(() {});
                      },
                      onSubmitted: (_) {
                        if (!valido) {
                          return;
                        }

                        Navigator.of(sheetContext).pop(controller.text.trim());
                      },
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _espanol
                            ? 'Ej: Matemáticas'
                            : 'E.g. Mathematics',
                        prefixIcon: const Icon(
                          Ionicons.bookOutline,
                          color: _primaryColor,
                        ),
                        filled: true,
                        fillColor: oscuro
                            ? const Color(0xFF202631)
                            : const Color(0xFFFAFBFC),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: oscuro
                                ? const Color(0xFF343C48)
                                : const Color(0xFFDFE3EA),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _primaryColor,
                            width: 1.3,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 18),

                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: oscuro
                                    ? const Color(0xFFE5E9F0)
                                    : const Color(0xFF4B5563),
                                side: BorderSide(
                                  color: oscuro
                                      ? const Color(0xFF343C48)
                                      : const Color(0xFFDFE3EA),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: Text(_espanol ? 'Cancelar' : 'Cancel'),
                            ),
                          ),
                        ),

                        const SizedBox(width: 10),

                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: ElevatedButton(
                              onPressed: valido
                                  ? () {
                                      Navigator.of(sheetContext)
                                          .pop(controller.text.trim());
                                    }
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _primaryColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: _primaryColor
                                    .withValues(alpha: 0.35),
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13),
                                ),
                              ),
                              child: Text(
                                _espanol ? 'Continuar' : 'Continue',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.dispose();
      });
    });
  }

  void _importarMalla() {
    HapticFeedback.selectionClick();

    showAppStatusSnackBar(
      context,
      message: _espanol
          ? 'La importación de malla se conectará cuando migremos Gemini.'
          : 'Curriculum import will be connected when Gemini is migrated.',
      type: AppStatusType.info,
    );
  }

  void _importarHorario() {
    HapticFeedback.selectionClick();

    showAppStatusSnackBar(
      context,
      message: _espanol
          ? 'La importación de horario se conectará cuando migremos Gemini.'
          : 'Schedule import will be connected when Gemini is migrated.',
      type: AppStatusType.info,
    );
  }

  Future<void> _abrirDetalle(Asignatura asignatura) async {
    HapticFeedback.selectionClick();

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectDetailPage(subjectId: asignatura.id),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refrescar();
  }

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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double ancho = constraints.maxWidth;

                    final double horizontal = ancho <= 600
                        ? 10
                        : ancho <= 900
                        ? 24
                        : 40;

                    return ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(
                        horizontal,
                        ancho <= 600 ? 24 : 32,
                        horizontal,
                        60,
                      ),
                      children: [
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 760),
                            child: _buildHeader(oscuro),
                          ),
                        ),

                        const SizedBox(height: 28),

                        if (_cargando)
                          _buildLoading(oscuro)
                        else if (_error)
                          _buildError(oscuro)
                        else ...[
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: AppReveal(child: _buildActions(oscuro)),
                            ),
                          ),

                          const SizedBox(height: 28),

                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 760),
                              child: AppReveal(
                                delay: const Duration(milliseconds: 80),
                                child: _asignaturas.isEmpty
                                    ? _buildEmpty(oscuro)
                                    : _buildList(oscuro),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
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
              title: _espanol ? 'Asignaturas' : 'Subjects',
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmarEliminarAsignatura(Asignatura asignatura) async {
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

    return confirmar == true;
  }

  Future<void> _eliminarAsignatura(Asignatura asignatura) async {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: const Center(child: CircularProgressIndicator()),
        );
      },
    );

    try {
      await _asignaturasService.eliminar(asignatura.id);

      if (!mounted) {
        return;
      }

      Navigator.of(context, rootNavigator: true).pop();

      setState(() {
        _asignaturas.removeWhere((item) => item.id == asignatura.id);
      });

      HapticFeedback.mediumImpact();

      showAppStatusSnackBar(
        context,
        message: _espanol
            ? 'Asignatura eliminada correctamente.'
            : 'Subject deleted successfully.',
        type: AppStatusType.success,
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
            ? 'No pudimos eliminar la asignatura.'
            : 'We could not delete the subject.',
        type: AppStatusType.error,
      );
    }
  }

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
                      _espanol ? 'Asignaturas' : 'Subjects',
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
                          ? 'Administra tus asignaturas y mantén organizada tu información académica.'
                          : 'Manage your subjects and keep your academic information organized.',
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

  Widget _buildActions(bool oscuro) {
    final List<Widget> acciones = [
      _buildActionCard(
        oscuro: oscuro,
        icon: Ionicons.addOutline,
        title: _tituloAgregar,
        description: _descripcionAgregar,
        onTap: _abrirFormulario,
      ),

      if (_esSuperior)
        _buildActionCard(
          oscuro: oscuro,
          icon: Ionicons.documentTextOutline,
          title: _espanol ? 'Importar malla' : 'Import curriculum',
          description: _espanol
              ? 'Analiza tu malla académica para preparar tus ramos.'
              : 'Analyze your curriculum to prepare your courses.',
          onTap: _importarMalla,
        ),

      _buildActionCard(
        oscuro: oscuro,
        icon: Ionicons.calendarOutline,
        title: _espanol ? 'Importar horario' : 'Import schedule',
        description: _espanol
            ? (_esEscolar
                  ? 'Carga una imagen de tu horario escolar para detectar tus asignaturas y bloques.'
                  : 'Carga tu horario para detectar asignaturas y bloques automáticamente.')
            : (_esEscolar
                  ? 'Upload your school schedule to detect subjects and class blocks.'
                  : 'Upload your schedule to detect subjects and class blocks automatically.'),
        onTap: _importarHorario,
      ),
    ];

    return Column(
      children: [
        for (int index = 0; index < acciones.length; index++) ...[
          acciones[index],
          if (index != acciones.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildActionCard({
    required bool oscuro,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return AppPressable(
      scale: 0.985,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 76),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF191F29) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: oscuro
                      ? const Color(0xFF292F47)
                      : const Color(0xFFEEF0FF),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: oscuro ? const Color(0xFFB8BBFF) : _primaryColor,
                  size: 23,
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      description,
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              Icon(
                Icons.chevron_right_rounded,
                color: oscuro
                    ? const Color(0xFF7F899A)
                    : const Color(0xFF9CA3AF),
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(bool oscuro) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _tituloLista,
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),

            Container(
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: oscuro
                    ? const Color(0xFF292F47)
                    : const Color(0xFFEEF0FF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_asignaturas.length}',
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        Column(
          children: [
            for (int index = 0; index < _asignaturas.length; index++) ...[
              _buildSubjectCard(
                _asignaturas[index],
                oscuro,
                showSwipeTutorial: index == 0,
              ),

              if (index != _asignaturas.length - 1) const SizedBox(height: 10),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildSubjectCard(
    Asignatura asignatura,
    bool oscuro, {
    required bool showSwipeTutorial,
  }) {
    final String detalle = asignatura.origen == OrigenAsignatura.manual
        ? (_espanol ? 'Agregada manualmente' : 'Added manually')
        : (_espanol ? 'Importada' : 'Imported');

    final String? tutorialKey = SubjectsPage.swipeTutorialKeyForUid(
      _authService.usuarioActual?.uid,
    );

    return AppSwipeDelete(
      key: ValueKey('swipe-asignatura-${asignatura.id}'),

      borderRadius: 18,

      deleteLabel: _espanol ? 'Eliminar' : 'Delete',

      tutorialKey: showSwipeTutorial ? tutorialKey : null,

      tutorialTitle: _espanol ? 'Elimina deslizando' : 'Swipe to delete',

      tutorialMessage: _espanol
          ? 'Desliza una asignatura hacia la izquierda para eliminarla rápidamente. Antes de borrarla, siempre te pediremos confirmación.'
          : 'Swipe a subject to the left to quickly delete it. We will always ask for confirmation before deleting it.',

      tutorialButtonLabel: _espanol ? 'Entendido' : 'Got it',

      onConfirmDelete: () {
        return _confirmarEliminarAsignatura(asignatura);
      },

      onDelete: () {
        return _eliminarAsignatura(asignatura);
      },

      child: AppPressable(
        scale: 0.985,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _abrirDetalle(asignatura);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF191F29) : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: oscuro
                    ? const Color(0xFF2B323E)
                    : const Color(0xFFE7EAF0),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF292F47)
                        : const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Ionicons.bookOutline,
                    color: oscuro ? const Color(0xFFB8BBFF) : _primaryColor,
                    size: 22,
                  ),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        asignatura.nombre,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: oscuro
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF1F2937),
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 4),

                      Text(
                        detalle,
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

                const SizedBox(width: 10),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: oscuro
                        ? const Color(0xFF292F47)
                        : const Color(0xFFEEF0FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _espanol ? 'Registrada' : 'Registered',
                    style: const TextStyle(
                      color: _primaryColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(bool oscuro) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 30),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF191F29) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: oscuro ? const Color(0xFF2B323E) : const Color(0xFFE7EAF0),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292F47) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Ionicons.libraryOutline,
              color: oscuro ? const Color(0xFFB8BBFF) : _primaryColor,
              size: 30,
            ),
          ),

          const SizedBox(height: 18),

          Text(
            _tituloVacio,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            _descripcionVacio,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading(bool oscuro) {
    return const SizedBox(
      height: 360,
      child: Center(
        child: CircularProgressIndicator(strokeWidth: 3, color: _primaryColor),
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
                      ? 'No pudimos cargar tus asignaturas. Desliza hacia abajo para intentarlo nuevamente.'
                      : 'We could not load your subjects. Pull down to try again.',
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
