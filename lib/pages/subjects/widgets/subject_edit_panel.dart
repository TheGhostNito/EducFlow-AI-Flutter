import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/asignatura.dart';
import '../../../models/perfil_usuario.dart';
import '../../../services/time_format_service.dart';

class SubjectEditPanel extends StatefulWidget {
  const SubjectEditPanel({
    super.key,
    required this.subject,
    required this.profile,
    required this.spanish,
    required this.saving,
    required this.creating,
    required this.onCancel,
    required this.onSave,
  });

  final Asignatura subject;
  final PerfilUsuario profile;

  final bool spanish;
  final bool saving;
  final bool creating;

  final VoidCallback onCancel;

  final Future<void> Function(Asignatura subject) onSave;

  @override
  State<SubjectEditPanel> createState() => _SubjectEditPanelState();
}

class _SubjectEditPanelState extends State<SubjectEditPanel> {
  static const Color _primaryColor = Color(0xFF5B5FEF);

  final TimeFormatService _timeFormatService = TimeFormatService.instance;

  late final TextEditingController _nameController;

  late final TextEditingController _teacherController;

  late final TextEditingController _teacherEmailController;

  late final TextEditingController _roomController;

  late final TextEditingController _codeController;

  late final TextEditingController _sectionController;

  late final TextEditingController _creditsController;

  late final TextEditingController _institutionController;

  late final TextEditingController _placeController;

  late int? _curriculumSemester;
  late String? _modality;

  late List<BloqueHorario> _schedule;

  bool _showErrors = false;

  // =========================================================
  // NIVEL EDUCATIVO
  // =========================================================

  NivelEducativoPerfil get _level => widget.profile.nivelEducativo;

  bool get _isSchool =>
      _level == NivelEducativoPerfil.basica ||
      _level == NivelEducativoPerfil.media;

  bool get _isHigher =>
      _level == NivelEducativoPerfil.tecnico ||
      _level == NivelEducativoPerfil.superior;

  bool get _isCourseOther =>
      _level == NivelEducativoPerfil.curso ||
      _level == NivelEducativoPerfil.otro;

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  List<DiaSemana> get _diasPermitidos {
    final NivelEducativoPerfil nivel = widget.profile.nivelEducativo;

    if (nivel == NivelEducativoPerfil.basica ||
        nivel == NivelEducativoPerfil.media) {
      return const [
        DiaSemana.lunes,
        DiaSemana.martes,
        DiaSemana.miercoles,
        DiaSemana.jueves,
        DiaSemana.viernes,
      ];
    }

    return const [
      DiaSemana.lunes,
      DiaSemana.martes,
      DiaSemana.miercoles,
      DiaSemana.jueves,
      DiaSemana.viernes,
      DiaSemana.sabado,
    ];
  }

  @override
  void initState() {
    super.initState();

    _timeFormatService.addListener(_actualizarFormatoHora);

    final Asignatura subject = widget.subject;

    _nameController = TextEditingController(text: subject.nombre);

    _teacherController = TextEditingController(text: subject.profesor ?? '');

    _teacherEmailController = TextEditingController(
      text: subject.correoProfesor ?? '',
    );

    _roomController = TextEditingController(text: subject.sala ?? '');

    _codeController = TextEditingController(text: subject.sigla ?? '');

    _sectionController = TextEditingController(text: subject.seccion ?? '');

    _creditsController = TextEditingController(
      text: subject.creditos?.toString() ?? '',
    );

    _institutionController = TextEditingController(
      text: subject.institucion?.trim().isNotEmpty == true
          ? subject.institucion
          : (_isCourseOther ? widget.profile.nombreEstablecimiento : ''),
    );

    _placeController = TextEditingController(text: subject.lugar ?? '');

    _curriculumSemester =
        subject.semestreMalla ??
        (_isHigher ? widget.profile.semestreActual : null);

    _modality = subject.modalidad;

    _schedule = subject.horario
        .map(
          (block) => BloqueHorario(
            dia: block.dia,
            horaInicio: block.horaInicio,
            horaFin: block.horaFin,
            sala: block.sala,
          ),
        )
        .toList();

    _sortSchedule();
  }

  @override
  void dispose() {
    _timeFormatService.removeListener(_actualizarFormatoHora);
    _nameController.dispose();
    _teacherController.dispose();
    _teacherEmailController.dispose();
    _roomController.dispose();
    _codeController.dispose();
    _sectionController.dispose();
    _creditsController.dispose();
    _institutionController.dispose();
    _placeController.dispose();

    super.dispose();
  }

  void _actualizarFormatoHora() {
    if (!mounted) {
      return;
    }

    setState(() {});
  }

  // =========================================================
  // TRADUCCIONES
  // =========================================================

  String _dayName(DiaSemana day) {
    if (widget.spanish) {
      switch (day) {
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

    switch (day) {
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

  String _semesterName(int semester) {
    return widget.spanish ? '$semester° semestre' : 'Semester $semester';
  }

  String _modalityName(String? modality) {
    if (modality == null || modality.trim().isEmpty) {
      return widget.spanish ? 'Seleccionar' : 'Select';
    }

    if (widget.spanish) {
      switch (modality) {
        case 'presencial':
          return 'Presencial';

        case 'online':
          return 'Online';

        case 'hibrida':
          return 'Híbrida';

        default:
          return modality;
      }
    }

    switch (modality) {
      case 'presencial':
        return 'In person';

      case 'online':
        return 'Online';

      case 'hibrida':
        return 'Hybrid';

      default:
        return modality;
    }
  }

  // =========================================================
  // VALIDACIÓN
  // =========================================================

  bool get _invalidName => _nameController.text.trim().isEmpty;

  bool get _invalidTeacherEmail {
    final String email = _teacherEmailController.text.trim();

    if (email.isEmpty) {
      return false;
    }

    return !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
  }

  bool get _invalidCredits {
    final String value = _creditsController.text.trim();

    if (value.isEmpty) {
      return false;
    }

    final int? credits = int.tryParse(value);

    return credits == null || credits < 0 || credits > 99;
  }

  bool _invalidScheduleBlock(BloqueHorario block) {
    final int start = _timeToMinutes(block.horaInicio);

    final int end = _timeToMinutes(block.horaFin);

    return start < 0 || end < 0 || end <= start;
  }

  bool get _invalidSchedule {
    return _schedule.any(_invalidScheduleBlock);
  }

  bool get _validForm =>
      !_invalidName &&
      !_invalidTeacherEmail &&
      !_invalidCredits &&
      !_invalidSchedule;

  // =========================================================
  // HORARIO
  // =========================================================

  int _dayOrder(DiaSemana day) {
    switch (day) {
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

  void _sortSchedule() {
    _schedule.sort((a, b) {
      final int dayDifference = _dayOrder(a.dia) - _dayOrder(b.dia);

      if (dayDifference != 0) {
        return dayDifference;
      }

      return a.horaInicio.compareTo(b.horaInicio);
    });
  }

  int _timeToMinutes(String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return -1;
    }

    final int? hour = int.tryParse(parts[0]);

    final int? minute = int.tryParse(parts[1]);

    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return -1;
    }

    return (hour * 60) + minute;
  }

  TimeOfDay _parseTime(String value) {
    final List<String> parts = value.split(':');

    if (parts.length != 2) {
      return const TimeOfDay(hour: 8, minute: 0);
    }

    return TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 8,
      minute: int.tryParse(parts[1]) ?? 0,
    );
  }

  String _formatTime(TimeOfDay time) {
    final String hour = time.hour.toString().padLeft(2, '0');

    final String minute = time.minute.toString().padLeft(2, '0');

    return '$hour:$minute';
  }

  String _displayTime(String value) {
    return _timeFormatService.formatStoredTime(context, value);
  }

  void _addScheduleBlock() {
    HapticFeedback.selectionClick();

    setState(() {
      _schedule.add(
        const BloqueHorario(
          dia: DiaSemana.lunes,
          horaInicio: '08:00',
          horaFin: '09:30',
        ),
      );

      _sortSchedule();
    });
  }

  void _deleteScheduleBlock(int index) {
    HapticFeedback.mediumImpact();

    setState(() {
      _schedule.removeAt(index);
    });
  }

  Future<void> _changeDay(int index) async {
    final DiaSemana? selected = await _showPicker<DiaSemana>(
      title: widget.spanish ? 'Día de la semana' : 'Day of the week',
      selectedValue: _schedule[index].dia,
      options: _diasPermitidos
          .map((day) => _PickerOption(value: day, label: _dayName(day)))
          .toList(),
    );

    if (!mounted || selected == null) {
      return;
    }

    final BloqueHorario current = _schedule[index];

    setState(() {
      _schedule[index] = BloqueHorario(
        dia: selected,
        horaInicio: current.horaInicio,
        horaFin: current.horaFin,
        sala: current.sala,
      );

      _sortSchedule();
    });
  }

  Future<void> _changeTime({required int index, required bool start}) async {
    final BloqueHorario current = _schedule[index];

    final String currentValue = start ? current.horaInicio : current.horaFin;

    final bool usar24Horas = _timeFormatService.use24HourFormat(context);

    final TimeOfDay? selected = await showTimePicker(
      context: context,
      initialTime: _parseTime(currentValue),
      helpText: widget.spanish
          ? (start ? 'Hora de inicio' : 'Hora de término')
          : (start ? 'Start time' : 'End time'),
      cancelText: widget.spanish ? 'Cancelar' : 'Cancel',
      confirmText: widget.spanish ? 'Aceptar' : 'OK',
      builder: (pickerContext, child) {
        final MediaQueryData mediaQuery = MediaQuery.of(pickerContext);

        return MediaQuery(
          data: mediaQuery.copyWith(alwaysUse24HourFormat: usar24Horas),
          child: child!,
        );
      },
    );

    if (!mounted || selected == null) {
      return;
    }

    // Sigue almacenándose como HH:mm
    // independientemente de cómo se muestre.
    final String value = _formatTime(selected);

    setState(() {
      _schedule[index] = BloqueHorario(
        dia: current.dia,
        horaInicio: start ? value : current.horaInicio,
        horaFin: start ? current.horaFin : value,
        sala: current.sala,
      );

      _sortSchedule();
    });
  }

  void _changeBlockRoom(int index, String value) {
    final BloqueHorario current = _schedule[index];

    _schedule[index] = BloqueHorario(
      dia: current.dia,
      horaInicio: current.horaInicio,
      horaFin: current.horaFin,
      sala: value,
    );
  }

  // =========================================================
  // SELECTORES
  // =========================================================

  Future<void> _changeCurriculumSemester() async {
    final int? selected = await _showPicker<int>(
      title: widget.spanish ? 'Semestre en la malla' : 'Curriculum semester',
      selectedValue: _curriculumSemester,
      options: List.generate(12, (index) {
        final int semester = index + 1;

        return _PickerOption<int>(
          value: semester,
          label: _semesterName(semester),
        );
      }),
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _curriculumSemester = selected;
    });
  }

  Future<void> _changeModality() async {
    final String? selected = await _showPicker<String>(
      title: widget.spanish ? 'Modalidad' : 'Modality',
      selectedValue: _modality,
      options: [
        _PickerOption(
          value: 'presencial',
          label: widget.spanish ? 'Presencial' : 'In person',
        ),
        const _PickerOption(value: 'online', label: 'Online'),
        _PickerOption(
          value: 'hibrida',
          label: widget.spanish ? 'Híbrida' : 'Hybrid',
        ),
      ],
    );

    if (!mounted || selected == null) {
      return;
    }

    setState(() {
      _modality = selected;
    });
  }

  Future<T?> _showPicker<T>({
    required String title,
    required List<_PickerOption<T>> options,
    T? selectedValue,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (sheetContext) {
        final bool dark = Theme.of(sheetContext).brightness == Brightness.dark;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
          ),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF191F29) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),

              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: dark
                      ? const Color(0xFF48505E)
                      : const Color(0xFFD5D9E0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF111827),
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    IconButton(
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 7),
                  itemBuilder: (context, index) {
                    final option = options[index];

                    final bool selected = option.value == selectedValue;

                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();

                        Navigator.of(sheetContext).pop(option.value);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        constraints: const BoxConstraints(minHeight: 52),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? (dark
                                    ? const Color(0xFF2B3047)
                                    : const Color(0xFFEEF0FF))
                              : (dark ? const Color(0xFF202731) : Colors.white),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF5B5FEF)
                                : (dark
                                      ? const Color(0xFF303844)
                                      : const Color(0xFFE7EAF0)),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  color: dark
                                      ? const Color(0xFFF8FAFC)
                                      : const Color(0xFF1F2937),
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),

                            if (selected)
                              const Icon(
                                Icons.check_circle_rounded,
                                color: _primaryColor,
                                size: 21,
                              ),
                          ],
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
  }

  // =========================================================
  // GUARDAR
  // =========================================================

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    setState(() {
      _showErrors = true;
    });

    if (!_validForm) {
      HapticFeedback.mediumImpact();

      return;
    }

    final int? credits = _creditsController.text.trim().isEmpty
        ? null
        : int.tryParse(_creditsController.text.trim());

    final int academicYear =
        widget.subject.anioAcademico ?? DateTime.now().year;

    final Asignatura updated = Asignatura(
      id: widget.subject.id,

      nombre: _nameController.text.trim(),

      profesor: _nullable(_teacherController.text),

      correoProfesor: _nullable(_teacherEmailController.text),

      sala: (_isSchool || _isHigher)
          ? _nullable(_roomController.text)
          : widget.subject.sala,

      periodo: widget.subject.periodo,

      horario: List.unmodifiable(_schedule),

      estado: widget.subject.estado,

      origen: widget.subject.origen,

      // Superior / técnica.
      sigla: _isHigher ? _nullable(_codeController.text) : null,

      seccion: _isHigher ? _nullable(_sectionController.text) : null,

      creditos: _isHigher ? credits : null,

      semestreMalla: _isHigher ? _curriculumSemester : null,

      // Básica / media.
      cursoNivel: _isSchool
          ? (widget.subject.cursoNivel?.trim().isNotEmpty == true
                ? widget.subject.cursoNivel
                : widget.profile.cursoActual)
          : null,

      anioAcademico: _isSchool ? academicYear : null,

      // Curso / otro.
      modalidad: _isCourseOther ? _modality : null,

      lugar: _isCourseOther ? _nullable(_placeController.text) : null,

      institucion: _isCourseOther
          ? _nullable(_institutionController.text)
          : null,

      prerrequisitosIds: widget.subject.prerrequisitosIds,

      asignaturasSiguientesIds: widget.subject.asignaturasSiguientesIds,
    );

    HapticFeedback.selectionClick();

    await widget.onSave(updated);
  }

  String? _nullable(String value) {
    final String clean = value.trim();

    return clean.isEmpty ? null : clean;
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildIntro(dark),

        const SizedBox(height: 18),

        _buildCommonData(dark),

        if (_isSchool) ...[
          const SizedBox(height: 18),
          _buildSchoolContext(dark),
        ],

        if (_isHigher) ...[const SizedBox(height: 18), _buildHigherData(dark)],

        if (_isCourseOther) ...[
          const SizedBox(height: 18),
          _buildCourseData(dark),
        ],

        const SizedBox(height: 18),

        _buildScheduleEditor(dark),

        if (_showErrors && _invalidSchedule) ...[
          const SizedBox(height: 12),

          _buildErrorMessage(
            widget.spanish
                ? 'Revisa los bloques de horario. La hora de término debe ser posterior a la hora de inicio.'
                : 'Check the schedule blocks. End time must be later than start time.',
          ),
        ],

        const SizedBox(height: 22),

        _buildActions(dark),
      ],
    );
  }

  Widget _buildIntro(bool dark) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: _panelDecoration(dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.creating
                ? (widget.spanish ? 'CONFIGURAR ASIGNATURA' : 'SET UP SUBJECT')
                : (widget.spanish ? 'EDITAR ASIGNATURA' : 'EDIT SUBJECT'),
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            widget.creating
                ? (widget.spanish
                      ? 'Completa los datos principales'
                      : 'Complete the main information')
                : (widget.spanish
                      ? 'Actualiza la información'
                      : 'Update the information'),
            style: TextStyle(
              color: dark ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            widget.spanish
                ? 'Puedes dejar los datos que todavía no conozcas para completarlos más adelante.'
                : 'You can leave unknown information empty and complete it later.',
            style: TextStyle(
              color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 13,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommonData(bool dark) {
    return _buildPanel(
      dark: dark,
      eyebrow: widget.spanish ? 'INFORMACIÓN' : 'INFORMATION',
      title: widget.spanish ? 'Datos principales' : 'Main information',
      child: Column(
        children: [
          _buildTextField(
            dark: dark,
            controller: _nameController,
            label: widget.spanish
                ? (_isHigher
                      ? 'Nombre del ramo *'
                      : _isCourseOther
                      ? 'Nombre de la materia o módulo *'
                      : 'Nombre de la asignatura *')
                : 'Subject name *',
            icon: Icons.menu_book_outlined,
            error: _showErrors && _invalidName
                ? (widget.spanish
                      ? 'El nombre es obligatorio.'
                      : 'Name is required.')
                : null,
          ),

          const SizedBox(height: 14),

          _buildTextField(
            dark: dark,
            controller: _teacherController,
            label: widget.spanish
                ? (_isCourseOther ? 'Profesor/a o relator' : 'Profesor/a')
                : (_isCourseOther ? 'Teacher or instructor' : 'Teacher'),
            icon: Icons.person_outline,
          ),

          const SizedBox(height: 14),

          _buildTextField(
            dark: dark,
            controller: _teacherEmailController,
            label: widget.spanish ? 'Correo del profesor' : 'Teacher email',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            error: _showErrors && _invalidTeacherEmail
                ? (widget.spanish
                      ? 'Ingresa un correo válido.'
                      : 'Enter a valid email.')
                : null,
          ),

          if (_isSchool || _isHigher) ...[
            const SizedBox(height: 14),

            _buildTextField(
              dark: dark,
              controller: _roomController,
              label: widget.spanish
                  ? (_isSchool ? 'Sala habitual' : 'Sala predeterminada')
                  : (_isSchool ? 'Usual classroom' : 'Default room'),
              hint: widget.spanish ? 'Opcional' : 'Optional',
              icon: Icons.meeting_room_outlined,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSchoolContext(bool dark) {
    final String course = widget.subject.cursoNivel?.trim().isNotEmpty == true
        ? widget.subject.cursoNivel!
        : widget.profile.cursoActual;

    final int year = widget.subject.anioAcademico ?? DateTime.now().year;

    return _buildPanel(
      dark: dark,
      eyebrow: widget.spanish ? 'CONTEXTO ESCOLAR' : 'SCHOOL CONTEXT',
      title: widget.spanish ? 'Datos de tu curso' : 'Your grade information',
      child: Row(
        children: [
          Expanded(
            child: _buildContextCard(
              dark: dark,
              icon: Icons.school_outlined,
              label: widget.spanish ? 'Curso' : 'Grade',
              value: course.trim().isEmpty ? '—' : course,
            ),
          ),

          const SizedBox(width: 10),

          Expanded(
            child: _buildContextCard(
              dark: dark,
              icon: Icons.calendar_today_outlined,
              label: widget.spanish ? 'Año académico' : 'Academic year',
              value: '$year',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHigherData(bool dark) {
    return _buildPanel(
      dark: dark,
      eyebrow: widget.spanish ? 'ACADÉMICO' : 'ACADEMIC',
      title: widget.spanish ? 'Información del ramo' : 'Course information',
      child: Column(
        children: [
          _buildTextField(
            dark: dark,
            controller: _codeController,
            label: widget.spanish ? 'Sigla' : 'Code',
            icon: Icons.tag_outlined,
          ),

          const SizedBox(height: 14),

          _buildTextField(
            dark: dark,
            controller: _sectionController,
            label: widget.spanish ? 'Sección' : 'Section',
            icon: Icons.groups_outlined,
          ),

          const SizedBox(height: 14),

          _buildTextField(
            dark: dark,
            controller: _creditsController,
            label: widget.spanish ? 'Créditos' : 'Credits',
            icon: Icons.workspace_premium_outlined,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(2),
            ],
            error: _showErrors && _invalidCredits
                ? (widget.spanish
                      ? 'Ingresa un valor entre 0 y 99.'
                      : 'Enter a value between 0 and 99.')
                : null,
          ),

          const SizedBox(height: 14),

          _buildSelectField(
            dark: dark,
            label: widget.spanish
                ? 'Semestre en la malla'
                : 'Curriculum semester',
            icon: Icons.layers_outlined,
            value: _curriculumSemester == null
                ? (widget.spanish ? 'Seleccionar' : 'Select')
                : _semesterName(_curriculumSemester!),
            placeholder: _curriculumSemester == null,
            onTap: _changeCurriculumSemester,
          ),
        ],
      ),
    );
  }

  Widget _buildCourseData(bool dark) {
    return _buildPanel(
      dark: dark,
      eyebrow: widget.spanish ? 'CURSO O CAPACITACIÓN' : 'COURSE OR TRAINING',
      title: widget.spanish
          ? 'Información adicional'
          : 'Additional information',
      child: Column(
        children: [
          _buildTextField(
            dark: dark,
            controller: _institutionController,
            label: widget.spanish ? 'Institución' : 'Institution',
            icon: Icons.business_outlined,
          ),

          const SizedBox(height: 14),

          _buildSelectField(
            dark: dark,
            label: widget.spanish ? 'Modalidad' : 'Modality',
            icon: Icons.devices_outlined,
            value: _modalityName(_modality),
            placeholder: _modality == null,
            onTap: _changeModality,
          ),

          const SizedBox(height: 14),

          _buildTextField(
            dark: dark,
            controller: _placeController,
            label: widget.spanish ? 'Lugar' : 'Place',
            hint: widget.spanish ? 'Opcional' : 'Optional',
            icon: Icons.location_on_outlined,
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleEditor(bool dark) {
    return _buildPanel(
      dark: dark,
      eyebrow: widget.spanish ? 'HORARIO' : 'SCHEDULE',
      title: widget.spanish ? 'Bloques de clases' : 'Class blocks',
      trailing: TextButton.icon(
        onPressed: widget.saving ? null : _addScheduleBlock,
        icon: const Icon(Icons.add_rounded, size: 19),
        label: Text(widget.spanish ? 'Agregar' : 'Add'),
      ),
      child: _schedule.isEmpty
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.all(17),
              decoration: BoxDecoration(
                color: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: dark
                      ? const Color(0xFF343C48)
                      : const Color(0xFFE7EAF0),
                ),
              ),
              child: Text(
                widget.spanish
                    ? 'Todavía no hay bloques. Puedes guardar la asignatura ahora y agregar el horario más adelante.'
                    : 'There are no class blocks yet. You can save the subject now and add the schedule later.',
                style: TextStyle(
                  color: dark
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
            )
          : Column(
              children: [
                for (int index = 0; index < _schedule.length; index++) ...[
                  _buildScheduleBlock(dark, index),

                  if (index != _schedule.length - 1) const SizedBox(height: 11),
                ],
              ],
            ),
    );
  }

  Widget _buildScheduleBlock(bool dark, int index) {
    final BloqueHorario block = _schedule[index];

    final bool invalid = _showErrors && _invalidScheduleBlock(block);

    final TextEditingController blockRoomController = TextEditingController(
      text: block.sala ?? '',
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: invalid
              ? const Color(0xFFDC2626)
              : (dark ? const Color(0xFF343C48) : const Color(0xFFE7EAF0)),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniSelect(
                  dark: dark,
                  label: widget.spanish ? 'Día' : 'Day',
                  value: _dayName(block.dia),
                  onTap: () {
                    _changeDay(index);
                  },
                ),
              ),

              const SizedBox(width: 10),

              IconButton(
                onPressed: widget.saving
                    ? null
                    : () {
                        _deleteScheduleBlock(index);
                      },
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0x14DC2626),
                  foregroundColor: const Color(0xFFDC2626),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: _buildTimeField(
                  dark: dark,
                  label: widget.spanish ? 'Inicio' : 'Start',
                  value: _displayTime(block.horaInicio),
                  onTap: () {
                    _changeTime(index: index, start: true);
                  },
                ),
              ),

              const SizedBox(width: 10),

              Expanded(
                child: _buildTimeField(
                  dark: dark,
                  label: widget.spanish ? 'Término' : 'End',
                  value: _displayTime(block.horaFin),
                  onTap: () {
                    _changeTime(index: index, start: false);
                  },
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          TextField(
            controller: blockRoomController,
            enabled: !widget.saving,

            onTapOutside: (_) {
              FocusManager.instance.primaryFocus?.unfocus();
            },

            onChanged: (value) {
              _changeBlockRoom(index, value);
            },
            decoration: InputDecoration(
              labelText: widget.spanish
                  ? (_isSchool
                        ? 'Sala de este bloque (solo si cambia)'
                        : 'Sala de este bloque (opcional)')
                  : (_isSchool
                        ? 'Room for this block (only if different)'
                        : 'Room for this block (optional)'),
              prefixIcon: const Icon(Icons.meeting_room_outlined, size: 20),
              filled: true,
              fillColor: dark ? const Color(0xFF191F29) : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),

          if (invalid) ...[
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.spanish
                    ? 'La hora de término debe ser posterior a la de inicio.'
                    : 'End time must be later than start time.',
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =========================================================
  // WIDGETS AUXILIARES
  // =========================================================

  Widget _buildPanel({
    required bool dark,
    required String eyebrow,
    required String title,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(19),
      decoration: _panelDecoration(dark),
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
                        color: dark
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

          const SizedBox(height: 18),

          child,
        ],
      ),
    );
  }

  BoxDecoration _panelDecoration(bool dark) {
    return BoxDecoration(
      color: dark ? const Color(0xFF18181D) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: dark ? const Color(0xFF303038) : const Color(0xFFE7EAF0),
      ),
      boxShadow: dark
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

  Widget _buildContextCard({
    required bool dark,
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF202731) : const Color(0xFFFAFBFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(
          color: dark ? const Color(0xFF303844) : const Color(0xFFEDF0F5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _primaryColor, size: 21),

          const SizedBox(height: 9),

          Text(
            label,
            style: TextStyle(
              color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: dark ? const Color(0xFFF8FAFC) : const Color(0xFF1F2937),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required bool dark,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    String? error,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      enabled: !widget.saving,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,

      onTapOutside: (_) {
        FocusManager.instance.primaryFocus?.unfocus();
      },

      onChanged: (_) {
        if (_showErrors) {
          setState(() {});
        }
      },

      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: error,
        prefixIcon: Icon(icon, color: _primaryColor, size: 20),
        filled: true,
        fillColor: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: BorderSide(
            color: dark ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _primaryColor, width: 1.3),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
      ),
    );
  }

  Widget _buildSelectField({
    required bool dark,
    required String label,
    required IconData icon,
    required String value,
    required bool placeholder,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: widget.saving ? null : onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: _primaryColor, size: 20),
          filled: true,
          fillColor: dark ? const Color(0xFF202631) : const Color(0xFFFAFBFC),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  color: placeholder
                      ? (dark
                            ? const Color(0xFF7F899A)
                            : const Color(0xFF9CA3AF))
                      : (dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937)),
                ),
              ),
            ),

            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniSelect({
    required bool dark,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: widget.saving ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: dark ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
                fontSize: 10.5,
              ),
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

                const Icon(Icons.expand_more_rounded, size: 19),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeField({
    required bool dark,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(13),
      onTap: widget.saving ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF191F29) : Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: dark ? const Color(0xFF343C48) : const Color(0xFFDFE3EA),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: dark ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
                fontSize: 10.5,
              ),
            ),

            const SizedBox(height: 4),

            Row(
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),

                const Icon(
                  Icons.access_time_rounded,
                  size: 18,
                  color: _primaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorMessage(String message) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0x14DC2626),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0x45DC2626)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFDC2626),
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildActions(bool dark) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 49,
            child: OutlinedButton(
              onPressed: widget.saving ? null : widget.onCancel,
              child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
            ),
          ),
        ),

        const SizedBox(width: 10),

        Expanded(
          child: SizedBox(
            height: 49,
            child: ElevatedButton(
              onPressed: widget.saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _primaryColor.withValues(alpha: 0.5),
                elevation: 0,
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
                        widget.creating
                            ? (widget.spanish
                                  ? 'Guardar asignatura'
                                  : 'Save subject')
                            : (widget.spanish
                                  ? 'Guardar cambios'
                                  : 'Save changes'),
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

class _PickerOption<T> {
  const _PickerOption({required this.value, required this.label});

  final T value;
  final String label;
}
