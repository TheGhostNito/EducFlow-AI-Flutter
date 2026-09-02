import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/app_pressable.dart';

class ProfileOption<T> {
  const ProfileOption({required this.value, required this.label});

  final T value;
  final String label;
}

Future<T?> showProfileOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<ProfileOption<T>> options,
  T? selectedValue,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    builder: (context) {
      return _ProfileOptionSheet<T>(
        title: title,
        options: options,
        selectedValue: selectedValue,
      );
    },
  );
}

class _ProfileOptionSheet<T> extends StatelessWidget {
  const _ProfileOptionSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
  });

  final String title;
  final List<ProfileOption<T>> options;
  final T? selectedValue;

  static const Color _primaryColor = Color(0xFF5B5FEF);

  @override
  Widget build(BuildContext context) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;

    final double maxHeight = MediaQuery.sizeOf(context).height * 0.72;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF191F29) : const Color(0xFFFDFDFE),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
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
                      letterSpacing: -0.4,
                    ),
                  ),
                ),

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
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 20),
              itemCount: options.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 7);
              },
              itemBuilder: (context, index) {
                final ProfileOption<T> option = options[index];

                final bool selected = option.value == selectedValue;

                return AppPressable(
                  scale: 0.98,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();

                      Navigator.of(context).pop(option.value);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: const Cubic(0.22, 1, 0.36, 1),
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
                              ? (dark
                                    ? const Color(0xFF525A88)
                                    : const Color(0xFFC9CCFF))
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
                                color: selected
                                    ? (dark
                                          ? const Color(0xFFC7C9FF)
                                          : _primaryColor)
                                    : (dark
                                          ? const Color(0xFFF1F4F8)
                                          : const Color(0xFF374151)),
                                fontSize: 14,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          if (selected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: _primaryColor,
                              size: 21,
                            )
                          else
                            Icon(
                              Icons.chevron_right_rounded,
                              color: dark
                                  ? const Color(0xFF7F899A)
                                  : const Color(0xFF9CA3AF),
                              size: 21,
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
  }
}
