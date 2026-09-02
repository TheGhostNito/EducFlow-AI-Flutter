import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/perfil_usuario.dart';
import '../../../widgets/app_pressable.dart';

Future<NivelEducativoPerfil?> showProfileEducationLevelSheet({
  required BuildContext context,
  required bool spanish,
  NivelEducativoPerfil? selectedLevel,
}) {
  return showModalBottomSheet<NivelEducativoPerfil>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (context) {
      return _EducationLevelSheet(
        spanish: spanish,
        selectedLevel: selectedLevel,
      );
    },
  );
}

class _EducationLevelSheet extends StatelessWidget {
  const _EducationLevelSheet({
    required this.spanish,
    required this.selectedLevel,
  });

  final bool spanish;
  final NivelEducativoPerfil? selectedLevel;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final List<_EducationOption> options = [
      _EducationOption(
        value: NivelEducativoPerfil.basica,
        icon: Icons.school_outlined,
        title: spanish ? 'Educación básica' : 'Primary education',
        description: spanish
            ? 'Organiza tus cursos, asignaturas y horario escolar.'
            : 'Organize your grades, subjects and school schedule.',
      ),
      _EducationOption(
        value: NivelEducativoPerfil.media,
        icon: Icons.menu_book_outlined,
        title: spanish ? 'Educación media' : 'Secondary education',
        description: spanish
            ? 'Gestiona tus asignaturas, profesores y horario.'
            : 'Manage your subjects, teachers and schedule.',
      ),
      _EducationOption(
        value: NivelEducativoPerfil.tecnico,
        icon: Icons.build_outlined,
        title: spanish ? 'Educación técnica' : 'Technical education',
        description: spanish
            ? 'Configura tu carrera, semestre y plan académico.'
            : 'Set up your program, semester and academic plan.',
      ),
      _EducationOption(
        value: NivelEducativoPerfil.superior,
        icon: Icons.account_balance_outlined,
        title: spanish ? 'Educación superior' : 'Higher education',
        description: spanish
            ? 'Gestiona tu carrera, semestre, malla y asignaturas.'
            : 'Manage your program, semester, curriculum and subjects.',
      ),
      _EducationOption(
        value: NivelEducativoPerfil.curso,
        icon: Icons.auto_stories_outlined,
        title: spanish ? 'Curso o capacitación' : 'Course or training',
        description: spanish
            ? 'Organiza un curso, capacitación o certificación.'
            : 'Organize a course, training program or certification.',
      ),
      _EducationOption(
        value: NivelEducativoPerfil.otro,
        icon: Icons.more_horiz_rounded,
        title: spanish ? 'Otro tipo de estudio' : 'Other type of study',
        description: spanish
            ? 'Utiliza una configuración académica más flexible.'
            : 'Use a more flexible academic setup.',
      ),
    ];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF191F29) : const Color(0xFFFDFDFE),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(
          top: BorderSide(
            color: dark ? const Color(0xFF303844) : const Color(0xFFE7EAF0),
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
              color: dark ? const Color(0xFF48505E) : const Color(0xFFD5D9E0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 15),
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
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),

                      const SizedBox(height: 7),

                      Text(
                        spanish
                            ? 'Cuéntanos sobre tus estudios'
                            : 'Tell us about your studies',
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF111827),
                          fontSize: 23,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),

                      const SizedBox(height: 8),

                      Text(
                        spanish
                            ? 'Esto nos permite adaptar EduFlow AI a tu etapa académica y mostrarte solo las herramientas que necesitas.'
                            : 'This helps us adapt EduFlow AI to your academic stage and show only the tools you need.',
                        style: TextStyle(
                          color: dark
                              ? const Color(0xFFA9B1BF)
                              : const Color(0xFF6B7280),
                          fontSize: 13.5,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                AppPressable(
                  scale: 0.88,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();

                      Navigator.of(context).pop();
                    },
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: dark
                            ? const Color(0xFF252C38)
                            : const Color(0xFFF3F4F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: dark
                            ? const Color(0xFFCBD1DB)
                            : const Color(0xFF6B7280),
                        size: 21,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
              child: Column(
                children: [
                  for (final option in options) ...[
                    _buildOption(context: context, dark: dark, option: option),
                    const SizedBox(height: 9),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOption({
    required BuildContext context,
    required bool dark,
    required _EducationOption option,
  }) {
    final bool selected = selectedLevel == option.value;

    return AppPressable(
      scale: 0.975,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();

          Navigator.of(context).pop(option.value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(0.22, 1, 0.36, 1),
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? (dark ? const Color(0xFF2B3047) : const Color(0xFFEEF0FF))
                : (dark ? const Color(0xFF202731) : Colors.white),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? (dark ? const Color(0xFF525A88) : const Color(0xFFC9CCFF))
                  : (dark ? const Color(0xFF303844) : const Color(0xFFE7EAF0)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected
                      ? (dark
                            ? const Color(0xFF383E61)
                            : const Color(0xFFE1E3FF))
                      : (dark
                            ? const Color(0xFF292F47)
                            : const Color(0xFFEEF0FF)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  option.icon,
                  color: dark ? const Color(0xFFB8BBFF) : _primaryColor,
                  size: 23,
                ),
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFF8FAFC)
                            : const Color(0xFF1F2937),
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),

                    const SizedBox(height: 4),

                    Text(
                      option.description,
                      style: TextStyle(
                        color: dark
                            ? const Color(0xFFA9B1BF)
                            : const Color(0xFF6B7280),
                        fontSize: 12.5,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        key: ValueKey('selected'),
                        color: _primaryColor,
                        size: 22,
                      )
                    : Icon(
                        Icons.chevron_right_rounded,
                        key: const ValueKey('arrow'),
                        color: dark
                            ? const Color(0xFF7F899A)
                            : const Color(0xFF9CA3AF),
                        size: 22,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EducationOption {
  const _EducationOption({
    required this.value,
    required this.icon,
    required this.title,
    required this.description,
  });

  final NivelEducativoPerfil value;
  final IconData icon;
  final String title;
  final String description;
}
