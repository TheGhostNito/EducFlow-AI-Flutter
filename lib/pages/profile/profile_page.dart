import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/auth/auth_service.dart';
import '../../models/perfil_usuario.dart';
import '../../services/perfil_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/app_pressable.dart';
import '../../widgets/app_reveal.dart';
import '../../widgets/app_scroll_header.dart';
import 'widgets/profile_education_level_sheet.dart';
import 'widgets/profile_edit_panel.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({
    super.key,
    this.startInEditMode = false,
    this.initialEducationLevel,
  });

  final bool startInEditMode;
  final NivelEducativoPerfil? initialEducationLevel;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final AuthService _authService = AuthService();

  final PerfilService _perfilService = PerfilService();

  final TranslationService _translationService = TranslationService.instance;

  final ScrollController _scrollController = ScrollController();

  static const Color _primaryColor = Color(0xFF5B5FEF);

  PerfilUsuario? _perfil;

  NivelEducativoPerfil? _nivelTemporal;

  bool _modoEdicion = false;
  bool _resolviendoNivelInicial = false;
  bool _guardando = false;

  bool _cargando = true;
  bool _error = false;

  double _progresoHeader = 0;

  bool get _espanol => _translationService.isSpanish;

  NivelEducativoPerfil get _nivelActual {
    final NivelEducativoPerfil guardado =
        _perfil?.nivelEducativo ?? NivelEducativoPerfil.vacio;

    if (guardado != NivelEducativoPerfil.vacio) {
      return guardado;
    }

    return _nivelTemporal ??
        widget.initialEducationLevel ??
        NivelEducativoPerfil.vacio;
  }

  bool get _esEscolar =>
      _nivelActual == NivelEducativoPerfil.basica ||
      _nivelActual == NivelEducativoPerfil.media;

  bool get _esSuperior =>
      _nivelActual == NivelEducativoPerfil.superior ||
      _nivelActual == NivelEducativoPerfil.tecnico;

  bool get _esCursoOtro =>
      _nivelActual == NivelEducativoPerfil.curso ||
      _nivelActual == NivelEducativoPerfil.otro;

  String get _nombre {
    final String nombre = _perfil?.nombre.trim() ?? '';

    if (nombre.isNotEmpty) {
      return nombre;
    }

    final String authName =
        _authService.usuarioActual?.displayName?.trim() ?? '';

    if (authName.isNotEmpty) {
      return authName;
    }

    return _espanol ? 'Estudiante' : 'Student';
  }

  String get _correoPrincipal {
    final String correo = _perfil?.correoPrincipal.trim() ?? '';

    if (correo.isNotEmpty) {
      return correo;
    }

    return _authService.usuarioActual?.email ?? '';
  }

  String get _iniciales {
    final List<String> partes = _nombre
        .split(RegExp(r'\s+'))
        .where((String parte) => parte.trim().isNotEmpty)
        .toList();

    if (partes.isEmpty) {
      return 'EF';
    }

    if (partes.length == 1) {
      final String nombre = partes.first;

      if (nombre.length == 1) {
        return nombre.toUpperCase();
      }

      return nombre.substring(0, 2).toUpperCase();
    }

    return '${partes.first[0]}${partes.last[0]}'.toUpperCase();
  }

  String get _resumenPrincipal {
    final PerfilUsuario? perfil = _perfil;

    if (perfil == null) {
      return _sinDefinir;
    }

    if (_esEscolar) {
      return perfil.cursoActual.trim().isNotEmpty
          ? perfil.cursoActual
          : (_espanol ? 'Curso sin definir' : 'Grade not defined');
    }

    if (_esSuperior) {
      return perfil.carrera.trim().isNotEmpty
          ? perfil.carrera
          : (_espanol ? 'Carrera sin definir' : 'Program not defined');
    }

    return perfil.cursoActual.trim().isNotEmpty
        ? perfil.cursoActual
        : (_espanol ? 'Estudio sin definir' : 'Study not defined');
  }

  String get _sinDefinir => _espanol ? 'Sin definir' : 'Not defined';

  @override
  void initState() {
    super.initState();

    _modoEdicion = widget.startInEditMode;
    _nivelTemporal = widget.initialEducationLevel;

    _translationService.addListener(_actualizarIdioma);

    _scrollController.addListener(_escucharScroll);

    _cargarPerfil();
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

  Future<void> _resolverNivelInicial() async {
    if (!mounted || _resolviendoNivelInicial || _perfil == null) {
      return;
    }

    if (_perfil!.nivelEducativo != NivelEducativoPerfil.vacio) {
      return;
    }

    if (_nivelTemporal != null &&
        _nivelTemporal != NivelEducativoPerfil.vacio) {
      setState(() {
        _modoEdicion = true;
      });

      return;
    }

    _resolviendoNivelInicial = true;

    await Future<void>.delayed(Duration.zero);

    if (!mounted) {
      return;
    }

    final NivelEducativoPerfil? nivel = await showProfileEducationLevelSheet(
      context: context,
      spanish: _espanol,
    );

    if (!mounted) {
      return;
    }

    _resolviendoNivelInicial = false;

    if (nivel == null) {
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _nivelTemporal = nivel;
      _modoEdicion = true;
    });
  }

  Future<void> _cargarPerfil() async {
    setState(() {
      _cargando = true;
      _error = false;
    });

    try {
      final usuario = _authService.usuarioActual;

      if (usuario == null) {
        if (!mounted) {
          return;
        }

        Navigator.of(context).maybePop();

        return;
      }

      final PerfilUsuario? perfil = await _perfilService.obtenerPerfil(
        usuario.uid,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _perfil = perfil;
        _error = perfil == null;
      });

      if (perfil != null) {
        await _resolverNivelInicial();
      }
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

  void _volver() {
    HapticFeedback.selectionClick();

    Navigator.of(context).maybePop();
  }

  void _iniciarEdicion() {
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

    final bool perfilSinNivel =
        _perfil?.nivelEducativo == NivelEducativoPerfil.vacio;

    if (perfilSinNivel) {
      _nivelTemporal = null;
      Navigator.of(context).maybePop();
      return;
    }

    setState(() {
      _modoEdicion = false;
      _nivelTemporal = null;
    });
  }

  Future<void> _guardarPerfil(ProfileEditData datos) async {
    if (_guardando) {
      return;
    }

    final usuario = _authService.usuarioActual;

    if (usuario == null) {
      return;
    }

    setState(() {
      _guardando = true;
    });

    bool nombreAuthSincronizado = true;

    try {
      await _perfilService.actualizarPerfil(
        usuario.uid,
        ActualizarPerfilUsuario(
          nombre: datos.nombre,
          correoInstitucional: datos.correoInstitucional,
          nivelEducativo: datos.nivelEducativo,
          nombreEstablecimiento: datos.nombreEstablecimiento,
          tipoEstablecimiento: datos.tipoEstablecimiento,
          cursoActual: datos.cursoActual,
          carrera: datos.carrera,
          semestreActual: datos.semestreActual,
          anioIngreso: datos.anioIngreso,
          sede: datos.sede,
          jornada: datos.jornada,
          estadoAcademico: datos.estadoAcademico,
          idioma: _espanol ? 'es' : 'en',
        ),
      );

      if (usuario.displayName?.trim() != datos.nombre.trim()) {
        try {
          await usuario.updateDisplayName(datos.nombre.trim());

          await usuario.reload();
        } catch (_) {
          nombreAuthSincronizado = false;
        }
      }

      final PerfilUsuario? perfilActualizado = await _perfilService
          .obtenerPerfil(usuario.uid);

      if (!mounted) {
        return;
      }

      if (perfilActualizado == null) {
        throw Exception('No se pudo recargar el perfil.');
      }

      setState(() {
        _perfil = perfilActualizado;
        _nivelTemporal = null;
        _modoEdicion = false;
      });

      HapticFeedback.mediumImpact();

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: nombreAuthSincronizado
                ? const Color(0xFF158A5B)
                : const Color(0xFFB7791F),
            content: Text(
              nombreAuthSincronizado
                  ? (_espanol
                        ? 'Perfil actualizado correctamente.'
                        : 'Profile updated successfully.')
                  : (_espanol
                        ? 'Perfil guardado. El nombre de la cuenta se sincronizará más adelante.'
                        : 'Profile saved. The account name will sync later.'),
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
                  ? 'No pudimos guardar los cambios. Inténtalo nuevamente.'
                  : 'We could not save your changes. Please try again.',
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

  String _nombreNivel(NivelEducativoPerfil nivel) {
    switch (nivel) {
      case NivelEducativoPerfil.basica:
        return _espanol ? 'Educación básica' : 'Primary education';

      case NivelEducativoPerfil.media:
        return _espanol ? 'Educación media' : 'Secondary education';

      case NivelEducativoPerfil.tecnico:
        return _espanol ? 'Educación técnica' : 'Technical education';

      case NivelEducativoPerfil.superior:
        return _espanol ? 'Educación superior' : 'Higher education';

      case NivelEducativoPerfil.curso:
        return _espanol ? 'Curso o capacitación' : 'Course or training';

      case NivelEducativoPerfil.otro:
        return _espanol ? 'Otro tipo de estudio' : 'Other type of study';

      case NivelEducativoPerfil.vacio:
        return _sinDefinir;
    }
  }

  String _nombreJornada(String valor) {
    if (_espanol) {
      switch (valor) {
        case 'Mañana':
          return 'Jornada de mañana';

        case 'Tarde':
          return 'Jornada de tarde';

        case 'Completa':
          return 'Jornada completa';

        default:
          return valor;
      }
    }

    switch (valor) {
      case 'Mañana':
        return 'Morning shift';

      case 'Tarde':
        return 'Afternoon shift';

      case 'Diurna':
        return 'Daytime';

      case 'Vespertina':
        return 'Evening';

      case 'Completa':
        return 'Full-time';

      case 'Online':
        return 'Online';

      case 'Otra':
        return 'Other';

      default:
        return valor;
    }
  }

  String _nombreEstado(String valor) {
    if (_espanol) {
      return valor;
    }

    switch (valor) {
      case 'Estudiante regular':
        return 'Regular student';

      case 'Suspendido':
        return 'Suspended';

      case 'Egresado':
        return 'Program completed';

      case 'Titulado':
        return 'Graduated';

      case 'Finalizado':
        return 'Completed';

      default:
        return valor;
    }
  }

  String _nombreSemestre(int? semestre) {
    if (semestre == null) {
      return _sinDefinir;
    }

    return _espanol ? '$semestre° semestre' : 'Semester $semestre';
  }

  Widget _buildEditor(bool oscuro) {
    final PerfilUsuario perfil = _perfil!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1050),
        child: AppReveal(
          child: ProfileEditPanel(
            profile: perfil,
            accessEmail: _correoPrincipal,
            initialEducationLevel: _nivelActual,
            spanish: _espanol,
            saving: _guardando,
            onCancel: _cancelarEdicion,
            onSave: _guardarPerfil,
          ),
        ),
      ),
    );
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
                onRefresh: _cargarPerfil,
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
                            constraints: const BoxConstraints(maxWidth: 1050),
                            child: _buildHeader(oscuro),
                          ),
                        ),

                        const SizedBox(height: 28),

                        if (_cargando)
                          _buildLoading(oscuro)
                        else if (_error)
                          _buildError(oscuro)
                        else if (_modoEdicion)
                          _buildEditor(oscuro)
                        else ...[
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1050),
                              child: AppReveal(
                                child: _buildStudentCard(oscuro),
                              ),
                            ),
                          ),

                          const SizedBox(height: 22),

                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1050),
                              child: AppReveal(
                                delay: const Duration(milliseconds: 70),
                                child: _buildAcademicPanel(oscuro),
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
              title: _espanol ? 'Perfil académico' : 'Academic profile',
              leading: _buildCompactBackButton(oscuro),
            ),
          ),
        ],
      ),
    );
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
                      _espanol ? 'Perfil académico' : 'Academic profile',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 34,
                        height: 1.08,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      _espanol
                          ? 'Administra tu información y tu identidad académica en EducFlow AI.'
                          : 'Manage your information and academic identity in EducFlow AI.',
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
          boxShadow: oscuro
              ? const []
              : const [
                  BoxShadow(
                    color: Color(0x0E0F172A),
                    blurRadius: 17,
                    offset: Offset(0, 6),
                  ),
                ],
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

  Widget _buildLoading(bool oscuro) {
    return SizedBox(
      height: 360,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(
              strokeWidth: 3,
              color: _primaryColor,
            ),

            const SizedBox(height: 15),

            Text(
              _espanol ? 'Cargando tu perfil...' : 'Loading your profile...',
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
        constraints: const BoxConstraints(maxWidth: 1050),
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
                      ? 'No pudimos cargar tu perfil. Desliza hacia abajo para intentarlo nuevamente.'
                      : 'We could not load your profile. Pull down to try again.',
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

  Widget _buildStudentCard(bool oscuro) {
    final PerfilUsuario perfil = _perfil!;

    return LayoutBuilder(
      builder: (context, constraints) {
        final bool movil = constraints.maxWidth <= 600;

        final double avatar = movil ? 62 : 82;

        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: movil ? 17 : 25,
            vertical: movil ? 20 : 25,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5B5FEF), Color(0xFF7650DF)],
            ),
            boxShadow: oscuro
                ? const []
                : const [
                    BoxShadow(
                      color: Color(0x3D5B5FEF),
                      blurRadius: 34,
                      offset: Offset(0, 14),
                    ),
                  ],
          ),
          child: Row(
            children: [
              Container(
                width: avatar,
                height: avatar,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(movil ? 19 : 24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
                ),
                child: Text(
                  _iniciales,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: movil ? 17 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              SizedBox(width: movil ? 15 : 20),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _espanol ? 'ESTUDIANTE' : 'STUDENT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                      ),
                    ),

                    const SizedBox(height: 5),

                    Text(
                      _nombre,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: movil ? 22 : 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _resumenPrincipal,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(height: 14),

                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_nivelActual != NivelEducativoPerfil.vacio)
                          _buildBadge(
                            Ionicons.schoolOutline,
                            _nombreNivel(_nivelActual),
                          ),

                        if (perfil.nombreEstablecimiento.trim().isNotEmpty)
                          _buildBadge(
                            Ionicons.businessOutline,
                            perfil.nombreEstablecimiento,
                          ),

                        if (perfil.jornada.trim().isNotEmpty)
                          _buildBadge(
                            Ionicons.timeOutline,
                            _nombreJornada(perfil.jornada),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),

          const SizedBox(width: 6),

          Flexible(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicPanel(bool oscuro) {
    final PerfilUsuario perfil = _perfil!;

    final List<_AcademicEntry> datos = [
      _AcademicEntry(
        icon: Ionicons.schoolOutline,
        label: _espanol ? 'Nivel educativo' : 'Education level',
        value: _nombreNivel(_nivelActual),
      ),

      _AcademicEntry(
        icon: Ionicons.businessOutline,
        label: _espanol ? 'Institución' : 'Institution',
        value: perfil.nombreEstablecimiento.trim().isNotEmpty
            ? perfil.nombreEstablecimiento
            : _sinDefinir,
      ),

      if (_esEscolar || _esCursoOtro)
        _AcademicEntry(
          icon: Ionicons.bookOutline,
          label: _espanol
              ? (_esEscolar ? 'Curso actual' : 'Curso o nivel actual')
              : (_esEscolar ? 'Current grade' : 'Current course or level'),
          value: perfil.cursoActual.trim().isNotEmpty
              ? perfil.cursoActual
              : _sinDefinir,
        ),

      if (_esSuperior)
        _AcademicEntry(
          icon: Ionicons.briefcaseOutline,
          label: _espanol ? 'Carrera' : 'Program',
          value: perfil.carrera.trim().isNotEmpty
              ? perfil.carrera
              : _sinDefinir,
        ),

      if (_esSuperior)
        _AcademicEntry(
          icon: Ionicons.layersOutline,
          label: _espanol ? 'Semestre actual' : 'Current semester',
          value: _nombreSemestre(perfil.semestreActual),
        ),

      _AcademicEntry(
        icon: Ionicons.calendarOutline,
        label: _espanol ? 'Año de ingreso' : 'Entry year',
        value: perfil.anioIngreso?.toString() ?? _sinDefinir,
      ),

      _AcademicEntry(
        icon: Ionicons.timeOutline,
        label: _espanol ? 'Jornada' : 'Schedule',
        value: perfil.jornada.trim().isNotEmpty
            ? _nombreJornada(perfil.jornada)
            : _sinDefinir,
      ),

      _AcademicEntry(
        icon: Ionicons.checkmarkCircleOutline,
        label: _espanol ? 'Estado académico' : 'Academic status',
        value: perfil.estadoAcademico.trim().isNotEmpty
            ? _nombreEstado(perfil.estadoAcademico)
            : _sinDefinir,
      ),

      _AcademicEntry(
        icon: Ionicons.mailOutline,
        label: _espanol ? 'Correo de acceso' : 'Access email',
        value: _correoPrincipal.trim().isNotEmpty
            ? _correoPrincipal
            : _sinDefinir,
      ),

      if (perfil.correoInstitucional.trim().isNotEmpty)
        _AcademicEntry(
          icon: Ionicons.mailUnreadOutline,
          label: _espanol ? 'Correo institucional' : 'Institutional email',
          value: perfil.correoInstitucional,
        ),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
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
                      _espanol ? 'INFORMACIÓN' : 'INFORMATION',
                      style: const TextStyle(
                        color: _primaryColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.9,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      _espanol ? 'Datos académicos' : 'Academic information',
                      style: TextStyle(
                        color: oscuro
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF111827),
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              AppPressable(
                scale: 0.94,
                child: TextButton.icon(
                  onPressed: _iniciarEdicion,
                  icon: const Icon(Ionicons.createOutline, size: 17),
                  label: Text(_espanol ? 'Editar' : 'Edit'),
                  style: TextButton.styleFrom(
                    foregroundColor: _primaryColor,
                    backgroundColor: oscuro
                        ? const Color(0xFF252B40)
                        : const Color(0xFFF7F7FF),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(13),
                      side: BorderSide(
                        color: oscuro
                            ? const Color(0xFF3A4161)
                            : const Color(0xFFDFE2FF),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          LayoutBuilder(
            builder: (context, constraints) {
              final int columnas = constraints.maxWidth < 680 ? 1 : 2;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: datos.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columnas,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 82,
                ),
                itemBuilder: (context, index) {
                  return _buildAcademicItem(datos[index], oscuro);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAcademicItem(_AcademicEntry item, bool oscuro) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF202731) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: oscuro ? const Color(0xFF303844) : const Color(0xFFEDF0F5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: oscuro ? const Color(0xFF292F47) : const Color(0xFFEEF0FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              item.icon,
              color: oscuro ? const Color(0xFFB8BBFF) : _primaryColor,
              size: 23,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFA9B1BF)
                        : const Color(0xFF6B7280),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  item.value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFFF8FAFC)
                        : const Color(0xFF1F2937),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcademicEntry {
  const _AcademicEntry({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}
