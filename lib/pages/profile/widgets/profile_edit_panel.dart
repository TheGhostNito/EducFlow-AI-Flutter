import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../../models/perfil_usuario.dart';
import '../../../widgets/app_pressable.dart';
import 'profile_education_level_sheet.dart';
import 'profile_option_sheet.dart';

class ProfileEditData {
  const ProfileEditData({
    required this.nombre,
    required this.nivelEducativo,
    required this.nombreEstablecimiento,
    required this.tipoEstablecimiento,
    required this.cursoActual,
    required this.carrera,
    required this.semestreActual,
    required this.anioIngreso,
    required this.sede,
    required this.jornada,
    required this.correoInstitucional,
    required this.estadoAcademico,
  });

  final String nombre;
  final NivelEducativoPerfil nivelEducativo;

  final String nombreEstablecimiento;
  final String tipoEstablecimiento;

  final String cursoActual;
  final String carrera;
  final int? semestreActual;

  final int? anioIngreso;

  final String sede;
  final String jornada;

  final String correoInstitucional;
  final String estadoAcademico;
}

class ProfileEditPanel extends StatefulWidget {
  const ProfileEditPanel({
    super.key,
    required this.profile,
    required this.accessEmail,
    required this.initialEducationLevel,
    required this.spanish,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final PerfilUsuario profile;

  final String accessEmail;

  final NivelEducativoPerfil initialEducationLevel;

  final bool spanish;
  final bool saving;

  final VoidCallback onCancel;

  final Future<void> Function(ProfileEditData data) onSave;

  @override
  State<ProfileEditPanel> createState() => _ProfileEditPanelState();
}

class _ProfileEditPanelState extends State<ProfileEditPanel> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  late final TextEditingController _nombreController;

  late final TextEditingController _establecimientoController;

  late final TextEditingController _tipoEstablecimientoController;

  late final TextEditingController _cursoController;

  late final TextEditingController _carreraController;

  late final TextEditingController _anioController;

  late final TextEditingController _sedeController;

  late final TextEditingController _correoInstitucionalController;

  late NivelEducativoPerfil _nivel;

  int? _semestre;
  String _jornada = '';
  String _estadoAcademico = '';

  bool _mostrarErrores = false;

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

    _nivel = widget.initialEducationLevel != NivelEducativoPerfil.vacio
        ? widget.initialEducationLevel
        : widget.profile.nivelEducativo;

    _semestre = widget.profile.semestreActual;
    _jornada = widget.profile.jornada;
    _estadoAcademico = widget.profile.estadoAcademico;

    _nombreController = TextEditingController(text: widget.profile.nombre);

    _establecimientoController = TextEditingController(
      text: widget.profile.nombreEstablecimiento,
    );

    _tipoEstablecimientoController = TextEditingController(
      text: widget.profile.tipoEstablecimiento,
    );

    _cursoController = TextEditingController(text: widget.profile.cursoActual);

    _carreraController = TextEditingController(text: widget.profile.carrera);

    _anioController = TextEditingController(
      text: widget.profile.anioIngreso?.toString() ?? '',
    );

    _sedeController = TextEditingController(text: widget.profile.sede);

    _correoInstitucionalController = TextEditingController(
      text: widget.profile.correoInstitucional,
    );
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _establecimientoController.dispose();
    _tipoEstablecimientoController.dispose();
    _cursoController.dispose();
    _carreraController.dispose();
    _anioController.dispose();
    _sedeController.dispose();
    _correoInstitucionalController.dispose();

    super.dispose();
  }

  // =========================================================
  // TRADUCCIONES / ETIQUETAS
  // =========================================================

  String get _seleccionar => widget.spanish ? 'Seleccionar' : 'Select';

  String _nombreNivel(NivelEducativoPerfil nivel) {
    switch (nivel) {
      case NivelEducativoPerfil.basica:
        return widget.spanish ? 'Educación básica' : 'Primary education';

      case NivelEducativoPerfil.media:
        return widget.spanish ? 'Educación media' : 'Secondary education';

      case NivelEducativoPerfil.tecnico:
        return widget.spanish ? 'Educación técnica' : 'Technical education';

      case NivelEducativoPerfil.superior:
        return widget.spanish ? 'Educación superior' : 'Higher education';

      case NivelEducativoPerfil.curso:
        return widget.spanish ? 'Curso o capacitación' : 'Course or training';

      case NivelEducativoPerfil.otro:
        return widget.spanish ? 'Otro tipo de estudio' : 'Other type of study';

      case NivelEducativoPerfil.vacio:
        return _seleccionar;
    }
  }

  String get _etiquetaEstablecimiento {
    switch (_nivel) {
      case NivelEducativoPerfil.basica:
        return widget.spanish ? 'Colegio' : 'School';

      case NivelEducativoPerfil.media:
        return widget.spanish ? 'Colegio o liceo' : 'School or high school';

      case NivelEducativoPerfil.tecnico:
        return widget.spanish ? 'Instituto' : 'Institute';

      case NivelEducativoPerfil.superior:
        return widget.spanish ? 'Institución' : 'Institution';

      case NivelEducativoPerfil.curso:
        return widget.spanish
            ? 'Institución o academia'
            : 'Institution or academy';

      default:
        return widget.spanish ? 'Establecimiento' : 'Institution';
    }
  }

  String _nombreJornada(String valor) {
    if (widget.spanish) {
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
    if (widget.spanish) {
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

  String _nombreSemestre(int semestre) {
    return widget.spanish ? '$semestre° semestre' : 'Semester $semestre';
  }

  // =========================================================
  // OPCIONES
  // =========================================================

  List<ProfileOption<String>> get _opcionesJornada {
    final List<String> valores;

    if (_esEscolar) {
      valores = ['Mañana', 'Tarde', 'Completa'];
    } else {
      valores = ['Diurna', 'Vespertina', 'Completa', 'Online', 'Otra'];
    }

    return valores
        .map(
          (valor) =>
              ProfileOption<String>(value: valor, label: _nombreJornada(valor)),
        )
        .toList();
  }

  List<ProfileOption<int>> get _opcionesSemestre {
    return List<ProfileOption<int>>.generate(12, (index) {
      final int semestre = index + 1;

      return ProfileOption<int>(
        value: semestre,
        label: _nombreSemestre(semestre),
      );
    });
  }

  List<ProfileOption<String>> get _opcionesEstadoAcademico {
    List<String> valores;

    if (_esSuperior) {
      valores = ['Estudiante regular', 'Suspendido', 'Egresado', 'Titulado'];
    } else {
      valores = ['Estudiante regular', 'Suspendido', 'Finalizado'];
    }

    return valores
        .map(
          (valor) =>
              ProfileOption<String>(value: valor, label: _nombreEstado(valor)),
        )
        .toList();
  }

  List<ProfileOption<String>> get _opcionesCursoEscolar {
    if (_nivel == NivelEducativoPerfil.basica) {
      return List<ProfileOption<String>>.generate(8, (index) {
        final int curso = index + 1;
        final String valor = '$curso° básico';

        return ProfileOption<String>(
          value: valor,
          label: widget.spanish ? valor : 'Primary grade $curso',
        );
      });
    }

    if (_nivel == NivelEducativoPerfil.media) {
      return List<ProfileOption<String>>.generate(4, (index) {
        final int curso = index + 1;
        final String valor = '$curso° medio';

        return ProfileOption<String>(
          value: valor,
          label: widget.spanish ? valor : 'Secondary year $curso',
        );
      });
    }

    return [];
  }

  // =========================================================
  // SELECTORES
  // =========================================================

  Future<void> _cambiarNivel() async {
    FocusScope.of(context).unfocus();

    final NivelEducativoPerfil? nuevoNivel =
        await showProfileEducationLevelSheet(
          context: context,
          spanish: widget.spanish,
          selectedLevel: _nivel,
        );

    if (!mounted || nuevoNivel == null || nuevoNivel == _nivel) {
      return;
    }

    setState(() {
      _nivel = nuevoNivel;

      if (_esEscolar) {
        if (_jornada != 'Mañana' &&
            _jornada != 'Tarde' &&
            _jornada != 'Completa') {
          _jornada = '';
        }
      } else {
        if (_jornada == 'Mañana' || _jornada == 'Tarde') {
          _jornada = '';
        }
      }

      _cursoController.clear();

      if (_esEscolar) {
        _carreraController.clear();
        _sedeController.clear();
        _semestre = null;
      }

      if (_esSuperior) {
        _cursoController.clear();
      }

      if (_esCursoOtro) {
        _carreraController.clear();
        _sedeController.clear();
        _semestre = null;
      }
    });
  }

  Future<void> _cambiarJornada() async {
    FocusScope.of(context).unfocus();

    final String? valor = await showProfileOptionSheet<String>(
      context: context,
      title: widget.spanish
          ? (_esEscolar ? 'Jornada escolar' : 'Jornada o modalidad')
          : (_esEscolar ? 'School schedule' : 'Schedule or modality'),
      options: _opcionesJornada,
      selectedValue: _jornada.isEmpty ? null : _jornada,
    );

    if (!mounted || valor == null) {
      return;
    }

    setState(() {
      _jornada = valor;
    });
  }

  Future<void> _cambiarSemestre() async {
    FocusScope.of(context).unfocus();

    final int? valor = await showProfileOptionSheet<int>(
      context: context,
      title: widget.spanish ? 'Semestre actual' : 'Current semester',
      options: _opcionesSemestre,
      selectedValue: _semestre,
    );

    if (!mounted || valor == null) {
      return;
    }

    setState(() {
      _semestre = valor;
    });
  }

  Future<void> _cambiarEstado() async {
    FocusScope.of(context).unfocus();

    final String? valor = await showProfileOptionSheet<String>(
      context: context,
      title: widget.spanish ? 'Estado académico' : 'Academic status',
      options: _opcionesEstadoAcademico,
      selectedValue: _estadoAcademico.isEmpty ? null : _estadoAcademico,
    );

    if (!mounted || valor == null) {
      return;
    }

    setState(() {
      _estadoAcademico = valor;
    });
  }

  Future<void> _cambiarCursoEscolar() async {
    FocusScope.of(context).unfocus();

    final String? valor = await showProfileOptionSheet<String>(
      context: context,
      title: widget.spanish ? 'Curso actual' : 'Current grade',
      options: _opcionesCursoEscolar,
      selectedValue: _cursoController.text.trim().isEmpty
          ? null
          : _cursoController.text.trim(),
    );

    if (!mounted || valor == null) {
      return;
    }

    setState(() {
      _cursoController.text = valor;
    });
  }

  // =========================================================
  // VALIDACIÓN
  // =========================================================

  bool get _nombreInvalido => _nombreController.text.trim().isEmpty;

  bool get _nivelInvalido => _nivel == NivelEducativoPerfil.vacio;

  bool get _institucionInvalida =>
      _establecimientoController.text.trim().isEmpty;

  bool get _anioInvalido {
    final int? anio = int.tryParse(_anioController.text.trim());

    return anio == null || anio < 1900 || anio > 2100;
  }

  bool get _cursoInvalido {
    if (_esEscolar || _esCursoOtro) {
      return _cursoController.text.trim().isEmpty;
    }

    return false;
  }

  bool get _carreraInvalida {
    if (!_esSuperior) {
      return false;
    }

    return _carreraController.text.trim().isEmpty;
  }

  bool get _semestreInvalido => _esSuperior && _semestre == null;

  bool get _correoInstitucionalInvalido {
    final String correo = _correoInstitucionalController.text.trim();

    if (correo.isEmpty) {
      return false;
    }

    return !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(correo);
  }

  bool get _formularioValido {
    return !_nombreInvalido &&
        !_nivelInvalido &&
        !_institucionInvalida &&
        !_anioInvalido &&
        !_cursoInvalido &&
        !_carreraInvalida &&
        !_semestreInvalido &&
        !_correoInstitucionalInvalido;
  }

  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _mostrarErrores = true;
    });

    if (!_formularioValido) {
      HapticFeedback.mediumImpact();

      return;
    }

    HapticFeedback.selectionClick();

    await widget.onSave(
      ProfileEditData(
        nombre: _nombreController.text.trim(),
        nivelEducativo: _nivel,
        nombreEstablecimiento: _establecimientoController.text.trim(),
        tipoEstablecimiento: _tipoEstablecimientoController.text.trim(),
        cursoActual: _cursoController.text.trim(),
        carrera: _carreraController.text.trim(),
        semestreActual: _esSuperior ? _semestre : null,
        anioIngreso: int.tryParse(_anioController.text.trim()),
        sede: _esSuperior ? _sedeController.text.trim() : '',
        jornada: _jornada,
        correoInstitucional: _correoInstitucionalController.text
            .trim()
            .toLowerCase(),
        estadoAcademico: _estadoAcademico,
      ),
    );
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(19),
      decoration: BoxDecoration(
        color: oscuro ? const Color(0xFF18181D) : Colors.white,
        borderRadius: BorderRadius.circular(20),
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
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(oscuro),

          const SizedBox(height: 22),

          _buildForm(oscuro),

          const SizedBox(height: 15),

          Text(
            widget.spanish
                ? 'Los campos marcados con * son necesarios para completar tu perfil.'
                : 'Fields marked with * are required to complete your profile.',
            style: TextStyle(
              color: oscuro ? const Color(0xFF7F899A) : const Color(0xFF7B8492),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 20),

          _buildActions(oscuro),
        ],
      ),
    );
  }

  Widget _buildHeader(bool oscuro) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.spanish ? 'INFORMACIÓN' : 'INFORMATION',
                style: const TextStyle(
                  color: _primaryColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                ),
              ),

              const SizedBox(height: 4),

              Text(
                widget.spanish
                    ? 'Editar perfil académico'
                    : 'Edit academic profile',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFF8FAFC)
                      : const Color(0xFF111827),
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 6),

              Text(
                widget.spanish
                    ? 'EduFlow AI adaptará tu experiencia según el nivel educativo que selecciones.'
                    : 'EduFlow AI will adapt your experience based on the education level you select.',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        AppPressable(
          scale: 0.88,
          child: IconButton(
            onPressed: widget.saving ? null : widget.onCancel,
            tooltip: '',
            style: IconButton.styleFrom(
              backgroundColor: oscuro
                  ? const Color(0xFF202631)
                  : const Color(0xFFF7F8FA),
              foregroundColor: oscuro
                  ? const Color(0xFFCBD1DB)
                  : const Color(0xFF6B7280),
              side: BorderSide(
                color: oscuro
                    ? const Color(0xFF343C48)
                    : const Color(0xFFE2E6ED),
              ),
              minimumSize: const Size(42, 42),
              maximumSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.close_rounded, size: 20),
          ),
        ),
      ],
    );
  }

  Widget _buildForm(bool oscuro) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool dosColumnas = constraints.maxWidth >= 720;

        final List<Widget> fields = [
          _buildTextField(
            oscuro: oscuro,
            icon: Ionicons.personOutline,
            label: widget.spanish ? 'Nombre *' : 'Name *',
            controller: _nombreController,
            error: _mostrarErrores && _nombreInvalido
                ? (widget.spanish ? 'Ingresa tu nombre.' : 'Enter your name.')
                : null,
            textInputAction: TextInputAction.next,
          ),

          _buildReadonlyField(
            oscuro: oscuro,
            icon: Ionicons.mailOutline,
            label: widget.spanish ? 'Correo de acceso' : 'Access email',
            value: widget.accessEmail,
            hint: widget.spanish
                ? 'Este correo corresponde a tu cuenta y no se modifica desde aquí.'
                : 'This email belongs to your account and cannot be changed here.',
          ),

          _buildSelectField(
            oscuro: oscuro,
            icon: Ionicons.schoolOutline,
            label: widget.spanish ? 'Nivel educativo *' : 'Education level *',
            value: _nombreNivel(_nivel),
            placeholder: _nivel == NivelEducativoPerfil.vacio,
            error: _mostrarErrores && _nivelInvalido
                ? (widget.spanish
                      ? 'Selecciona tu nivel educativo.'
                      : 'Select your education level.')
                : null,
            onTap: _cambiarNivel,
          ),

          _buildSelectField(
            oscuro: oscuro,
            icon: Ionicons.timeOutline,
            label: widget.spanish
                ? (_esEscolar ? 'Jornada escolar' : 'Jornada o modalidad')
                : (_esEscolar ? 'School schedule' : 'Schedule or modality'),
            value: _jornada.isEmpty ? _seleccionar : _nombreJornada(_jornada),
            placeholder: _jornada.isEmpty,
            onTap: _cambiarJornada,
          ),

          _buildTextField(
            oscuro: oscuro,
            icon: Ionicons.businessOutline,
            label: '$_etiquetaEstablecimiento *',
            controller: _establecimientoController,
            error: _mostrarErrores && _institucionInvalida
                ? (widget.spanish
                      ? 'Ingresa tu institución.'
                      : 'Enter your institution.')
                : null,
            textInputAction: TextInputAction.next,
          ),

          _buildTextField(
            oscuro: oscuro,
            icon: Icons.apartment_outlined,
            label: widget.spanish
                ? 'Tipo de establecimiento'
                : 'Institution type',
            controller: _tipoEstablecimientoController,
            hint: widget.spanish ? 'Opcional' : 'Optional',
            textInputAction: TextInputAction.next,
          ),

          if (_esEscolar)
            _buildSelectField(
              oscuro: oscuro,
              icon: Ionicons.bookOutline,
              label: widget.spanish ? 'Curso actual *' : 'Current grade *',
              value: _cursoController.text.trim().isEmpty
                  ? _seleccionar
                  : _cursoController.text.trim(),
              placeholder: _cursoController.text.trim().isEmpty,
              error: _mostrarErrores && _cursoInvalido
                  ? (widget.spanish
                        ? 'Selecciona tu curso actual.'
                        : 'Select your current grade.')
                  : null,
              onTap: _cambiarCursoEscolar,
            ),

          if (_esCursoOtro)
            _buildTextField(
              oscuro: oscuro,
              icon: Ionicons.bookOutline,
              label: _nivel == NivelEducativoPerfil.curso
                  ? (widget.spanish
                        ? 'Nombre o nivel del curso *'
                        : 'Course name or level *')
                  : (widget.spanish
                        ? 'Estudio o nivel actual *'
                        : 'Current study or level *'),
              controller: _cursoController,
              error: _mostrarErrores && _cursoInvalido
                  ? (widget.spanish
                        ? 'Completa este campo.'
                        : 'Complete this field.')
                  : null,
              textInputAction: TextInputAction.next,
            ),

          if (_esSuperior)
            _buildTextField(
              oscuro: oscuro,
              icon: Ionicons.briefcaseOutline,
              label: widget.spanish ? 'Carrera *' : 'Program *',
              controller: _carreraController,
              error: _mostrarErrores && _carreraInvalida
                  ? (widget.spanish
                        ? 'Ingresa tu carrera.'
                        : 'Enter your program.')
                  : null,
              textInputAction: TextInputAction.next,
            ),

          if (_esSuperior)
            _buildSelectField(
              oscuro: oscuro,
              icon: Ionicons.layersOutline,
              label: widget.spanish
                  ? 'Semestre actual *'
                  : 'Current semester *',
              value: _semestre == null
                  ? (widget.spanish
                        ? 'Seleccionar semestre'
                        : 'Select semester')
                  : _nombreSemestre(_semestre!),
              placeholder: _semestre == null,
              error: _mostrarErrores && _semestreInvalido
                  ? (widget.spanish
                        ? 'Selecciona tu semestre.'
                        : 'Select your semester.')
                  : null,
              onTap: _cambiarSemestre,
            ),

          if (_esSuperior)
            _buildTextField(
              oscuro: oscuro,
              icon: Icons.location_on_outlined,
              label: widget.spanish ? 'Sede' : 'Campus',
              controller: _sedeController,
              hint: widget.spanish ? 'Opcional' : 'Optional',
              textInputAction: TextInputAction.next,
            ),

          _buildTextField(
            oscuro: oscuro,
            icon: Ionicons.calendarOutline,
            label: widget.spanish ? 'Año de ingreso *' : 'Entry year *',
            controller: _anioController,
            hint: '2026',
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            error: _mostrarErrores && _anioInvalido
                ? (widget.spanish
                      ? 'Ingresa un año válido.'
                      : 'Enter a valid year.')
                : null,
            textInputAction: TextInputAction.next,
          ),

          _buildTextField(
            oscuro: oscuro,
            icon: Ionicons.mailUnreadOutline,
            label: widget.spanish
                ? 'Correo institucional'
                : 'Institutional email',
            controller: _correoInstitucionalController,
            hint: widget.spanish ? 'Opcional' : 'Optional',
            keyboardType: TextInputType.emailAddress,
            error: _mostrarErrores && _correoInstitucionalInvalido
                ? (widget.spanish
                      ? 'Ingresa un correo válido.'
                      : 'Enter a valid email.')
                : null,
            textInputAction: TextInputAction.next,
          ),

          _buildSelectField(
            oscuro: oscuro,
            icon: Ionicons.checkmarkCircleOutline,
            label: widget.spanish ? 'Estado académico' : 'Academic status',
            value: _estadoAcademico.isEmpty
                ? _seleccionar
                : _nombreEstado(_estadoAcademico),
            placeholder: _estadoAcademico.isEmpty,
            onTap: _cambiarEstado,
          ),
        ];

        if (!dosColumnas) {
          return Column(
            children: [
              for (int i = 0; i < fields.length; i++) ...[
                fields[i],
                if (i != fields.length - 1) const SizedBox(height: 15),
              ],
            ],
          );
        }

        return Wrap(
          spacing: 14,
          runSpacing: 15,
          children: fields
              .map(
                (field) => SizedBox(
                  width: (constraints.maxWidth - 14) / 2,
                  child: field,
                ),
              )
              .toList(),
        );
      },
    );
  }

  Widget _buildTextField({
    required bool oscuro,
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    String? error,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, oscuro),

        const SizedBox(height: 7),

        TextField(
          controller: controller,
          enabled: !widget.saving,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          inputFormatters: inputFormatters,
          onChanged: (_) {
            if (_mostrarErrores) {
              setState(() {});
            }
          },
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
          decoration: _inputDecoration(
            oscuro: oscuro,
            icon: icon,
            hint: hint,
            error: error,
          ),
        ),
      ],
    );
  }

  Widget _buildReadonlyField({
    required bool oscuro,
    required IconData icon,
    required String label,
    required String value,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, oscuro),

        const SizedBox(height: 7),

        Container(
          constraints: const BoxConstraints(minHeight: 50),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
          decoration: BoxDecoration(
            color: oscuro ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: oscuro ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
              style: BorderStyle.solid,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: oscuro
                    ? const Color(0xFF7F899A)
                    : const Color(0xFF8B95A6),
                size: 20,
              ),

              const SizedBox(width: 11),

              Expanded(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFF9BA3B2)
                        : const Color(0xFF7B8492),
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 6),

        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            hint,
            style: TextStyle(
              color: oscuro ? const Color(0xFF7F899A) : const Color(0xFF7B8492),
              fontSize: 10.5,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectField({
    required bool oscuro,
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    bool placeholder = false,
    String? error,
  }) {
    final Color borderColor = error != null
        ? const Color(0xFFDC2626)
        : (oscuro ? const Color(0xFF343C48) : const Color(0xFFDFE3EA));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel(label, oscuro),

        const SizedBox(height: 7),

        AppPressable(
          scale: 0.98,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.saving ? null : onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
              decoration: BoxDecoration(
                color: oscuro
                    ? const Color(0xFF202631)
                    : const Color(0xFFFAFBFC),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Icon(icon, color: _primaryColor, size: 20),

                  const SizedBox(width: 11),

                  Expanded(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: placeholder
                            ? (oscuro
                                  ? const Color(0xFF747E8D)
                                  : const Color(0xFF9CA3AF))
                            : (oscuro
                                  ? const Color(0xFFF8FAFC)
                                  : const Color(0xFF1F2937)),
                        fontSize: 14,
                        fontWeight: placeholder
                            ? FontWeight.w400
                            : FontWeight.w600,
                      ),
                    ),
                  ),

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
        ),

        if (error != null) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              error,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _inputDecoration({
    required bool oscuro,
    required IconData icon,
    String? hint,
    String? error,
  }) {
    final Color normalBorder = oscuro
        ? const Color(0xFF343C48)
        : const Color(0xFFDFE3EA);

    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(
        color: oscuro ? const Color(0xFF747E8D) : const Color(0xFF9CA3AF),
      ),
      prefixIcon: Icon(icon, size: 20, color: _primaryColor),
      filled: true,
      fillColor: oscuro ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(
          color: error != null ? const Color(0xFFDC2626) : normalBorder,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: _primaryColor, width: 1.3),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: BorderSide(color: normalBorder),
      ),
      errorText: error,
      errorStyle: const TextStyle(color: Color(0xFFDC2626), fontSize: 11),
    );
  }

  Widget _buildFieldLabel(String label, bool oscuro) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        label,
        style: TextStyle(
          color: oscuro ? const Color(0xFFC4CAD4) : const Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildActions(bool oscuro) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed: widget.saving ? null : widget.onCancel,
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
              child: Text(
                widget.spanish ? 'Cancelar' : 'Cancel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: widget.saving ? null : _guardar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _primaryColor.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13),
                ),
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: widget.saving
                    ? const SizedBox(
                        key: ValueKey('saving'),
                        width: 21,
                        height: 21,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        widget.spanish ? 'Guardar cambios' : 'Save changes',
                        key: const ValueKey('save'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
