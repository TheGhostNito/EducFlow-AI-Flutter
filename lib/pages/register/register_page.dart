import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../services/translation_service.dart';
import '../../services/validacion_contrasena.dart';
import '../../widgets/app_animated_visibility.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/theme_toggle_button.dart';
import '../dashboard/dashboard_page.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final AuthService _authService = AuthService();

  final TranslationService _translationService = TranslationService.instance;

  final TextEditingController _nombreController = TextEditingController();

  final TextEditingController _correoController = TextEditingController();

  final TextEditingController _contrasenaController = TextEditingController();

  final TextEditingController _confirmarContrasenaController =
      TextEditingController();

  final FocusNode _nombreFocusNode = FocusNode();
  final FocusNode _correoFocusNode = FocusNode();
  final FocusNode _contrasenaFocusNode = FocusNode();
  final FocusNode _confirmarContrasenaFocusNode = FocusNode();

  bool _mostrarContrasena = false;
  bool _mostrarConfirmacion = false;
  bool _cargando = false;
  bool _requisitosOcultos = false;
  Timer? _ocultarRequisitosTimer;
  String _ultimaContrasena = '';
  String _ultimaConfirmacion = '';

  String _errorMessage = '';

  bool get _espanol => _translationService.isSpanish;

  // =========================================================
  // COLORES
  // =========================================================

  static const Color _primaryColor = Color(0xFF5B5FEF);

  static const Color _successColor = Color(0xFF16A36A);

  static const Color _errorColor = Color(0xFFE05252);

  static const Color _darkCard = Color(0xFF191F29);

  static const Color _darkBorder = Color(0xFF2B323E);

  static const Color _darkInput = Color(0xFF202631);

  static const Color _darkInputFocus = Color(0xFF242B37);

  static const Color _darkInputBorder = Color(0xFF343C48);

  static const Color _darkInputFocusBorder = Color(0xFF777BF4);

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_actualizarIdioma);

    _nombreFocusNode.addListener(_actualizarFoco);

    _correoFocusNode.addListener(_actualizarFoco);

    _contrasenaFocusNode.addListener(_actualizarFoco);

    _confirmarContrasenaFocusNode.addListener(_actualizarFoco);
    _contrasenaController.addListener(_actualizarContrasenas);
    _confirmarContrasenaController.addListener(_actualizarContrasenas);
  }

  void _actualizarFoco() {
    if (mounted) {
      setState(() {});
    }
  }

  void _actualizarIdioma() {
    if (mounted) {
      setState(() {});
    }
  }

  void _actualizarCampos() {
    if (mounted) {
      setState(() {
        _errorMessage = '';
      });
    }
  }

  void _actualizarContrasenas() {
    final String contrasena = _contrasenaController.text;
    final String confirmacion = _confirmarContrasenaController.text;
    // Cambiar la selección o mostrar la contraseña no reinicia los avisos.
    if (contrasena == _ultimaContrasena &&
        confirmacion == _ultimaConfirmacion) {
      return;
    }
    _ultimaContrasena = contrasena;
    _ultimaConfirmacion = confirmacion;
    _ocultarRequisitosTimer?.cancel();
    setState(() {
      _errorMessage = '';
      _requisitosOcultos = false;
    });
    if (_contrasenaValida() && _confirmacionValida()) {
      _ocultarRequisitosTimer = Timer(const Duration(milliseconds: 1200), () {
        if (mounted) {
          setState(() {
            _requisitosOcultos = true;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _ocultarRequisitosTimer?.cancel();
    _contrasenaController.removeListener(_actualizarContrasenas);
    _confirmarContrasenaController.removeListener(_actualizarContrasenas);
    _translationService.removeListener(_actualizarIdioma);

    _nombreFocusNode.dispose();
    _correoFocusNode.dispose();
    _contrasenaFocusNode.dispose();
    _confirmarContrasenaFocusNode.dispose();

    _nombreController.dispose();
    _correoController.dispose();
    _contrasenaController.dispose();
    _confirmarContrasenaController.dispose();

    super.dispose();
  }

  // =========================================================
  // VALIDACIONES
  // =========================================================

  bool _correoValido(String correo) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correo);
  }

  bool _nombreValido() {
    return _nombreController.text.trim().isNotEmpty;
  }

  bool _contrasenaValida() {
    return ValidacionContrasena(_contrasenaController.text).esValida;
  }

  bool _confirmacionValida() {
    final String contrasena = _contrasenaController.text;

    final String confirmacion = _confirmarContrasenaController.text;

    return contrasena.isNotEmpty && confirmacion == contrasena;
  }

  Color? _colorValidacionNombre() {
    final String nombre = _nombreController.text.trim();

    if (nombre.isEmpty) {
      return null;
    }

    if (_nombreFocusNode.hasFocus) {
      return _primaryColor;
    }

    return _nombreValido() ? _successColor : _errorColor;
  }

  Color? _colorValidacionCorreo() {
    final String correo = _correoController.text.trim();

    if (correo.isEmpty) {
      return null;
    }

    if (_correoFocusNode.hasFocus) {
      return _primaryColor;
    }

    return _correoValido(correo) ? _successColor : _errorColor;
  }

  Color? _colorValidacionContrasena() {
    final String contrasena = _contrasenaController.text;

    if (contrasena.isEmpty) {
      return null;
    }

    if (_contrasenaValida()) {
      return _successColor;
    }
    return _contrasenaFocusNode.hasFocus ? _primaryColor : null;
  }

  Color? _colorValidacionConfirmacion() {
    final String confirmacion = _confirmarContrasenaController.text;

    if (confirmacion.isEmpty) {
      return null;
    }

    if (_confirmacionValida()) {
      return _successColor;
    }
    return _confirmarContrasenaFocusNode.hasFocus ? _primaryColor : null;
  }

  // =========================================================
  // REGISTRO
  // =========================================================

  Future<void> _registrar() async {
    if (_cargando) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String nombre = _nombreController.text.trim();

    final String correo = _correoController.text.trim().toLowerCase();

    final String contrasena = _contrasenaController.text;

    final String confirmarContrasena = _confirmarContrasenaController.text;

    setState(() {
      _errorMessage = '';
    });

    if (nombre.isEmpty ||
        correo.isEmpty ||
        contrasena.isEmpty ||
        confirmarContrasena.isEmpty) {
      setState(() {
        _errorMessage = _espanol
            ? 'Completa todos los campos para continuar.'
            : 'Complete all fields to continue.';
      });

      return;
    }

    if (!_correoValido(correo)) {
      setState(() {
        _errorMessage = _espanol
            ? 'Ingresa un correo electrónico válido.'
            : 'Enter a valid email address.';
      });

      return;
    }

    if (!_contrasenaValida()) {
      setState(() {
        _errorMessage = _espanol
            ? 'La contraseña debe tener al menos 8 caracteres, 1 número y 1 carácter especial.'
            : 'The password must contain at least 8 characters, 1 number and 1 special character.';
      });

      return;
    }

    if (contrasena != confirmarContrasena) {
      setState(() {
        _errorMessage = _espanol
            ? 'Las contraseñas no coinciden.'
            : 'The passwords do not match.';
      });

      return;
    }

    setState(() {
      _cargando = true;
      _errorMessage = '';
    });

    try {
      await _authService.registrar(
        nombre: nombre,
        correo: correo,
        contrasena: contrasena,
        idioma: _espanol ? 'es' : 'en',
      );

      if (!mounted) {
        return;
      }

      await Navigator.of(context)
          .pushReplacement(MaterialPageRoute(builder: (_) => DashboardPage()));
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        switch (error.code) {
          case 'email-already-in-use':
            _errorMessage = _espanol
                ? 'Ya existe una cuenta asociada a ese correo.'
                : 'An account already exists for that email.';
            break;

          case 'invalid-email':
            _errorMessage = _espanol
                ? 'El correo electrónico no es válido.'
                : 'The email address is not valid.';
            break;

          case 'weak-password':
            _errorMessage = _espanol
                ? 'La contraseña es demasiado débil.'
                : 'The password is too weak.';
            break;

          case 'network-request-failed':
            _errorMessage = _espanol
                ? 'No se pudo conectar con Firebase. Revisa tu conexión a internet.'
                : 'Firebase could not be reached. Check your internet connection.';
            break;

          case 'operation-not-allowed':
            _errorMessage = _espanol
                ? 'El registro con correo y contraseña no está habilitado.'
                : 'Email and password registration is not enabled.';
            break;

          case 'too-many-requests':
            _errorMessage = _espanol
                ? 'Se realizaron demasiados intentos. Espera unos minutos.'
                : 'Too many attempts were made. Wait a few minutes.';
            break;

          default:
            _errorMessage = _espanol
                ? 'No fue posible crear la cuenta. Inténtalo nuevamente.'
                : 'The account could not be created. Please try again.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _errorMessage = _espanol
            ? 'No fue posible crear la cuenta. Inténtalo nuevamente.'
            : 'The account could not be created. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _cargando = false;
        });
      }
    }
  }

  void _volverAlLogin() {
    if (_cargando) {
      return;
    }

    Navigator.of(context).pop();
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final double alturaPantalla = MediaQuery.sizeOf(context).height;

    final bool modoCompacto = alturaPantalla < 900;

    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () {
                  FocusScope.of(context).unfocus();
                },
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    modoCompacto ? 12 : 24,
                    16,
                    modoCompacto ? 12 : 28,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(height: modoCompacto ? 46 : 62),

                      _buildBrandSection(modoCompacto, oscuro),

                      SizedBox(height: modoCompacto ? 8 : 22),

                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 430),
                          child: _buildRegisterCard(modoCompacto, oscuro),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            Positioned(
              top: 8,
              left: 16,
              child: ThemeToggleButton(disabled: _cargando),
            ),

            Positioned(
              top: 8,
              right: 16,
              child: LanguageSelector(
                disabled: _cargando,
                onLanguageChanged: () {
                  setState(() {
                    _errorMessage = '';
                  });
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // MARCA
  // =========================================================

  Widget _buildBrandSection(bool modoCompacto, bool oscuro) {
    return Column(
      children: [
        _buildLogo(modoCompacto, oscuro),

        SizedBox(height: modoCompacto ? 7 : 14),

        Text(
          'EducFlow AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
            fontSize: modoCompacto ? 28 : 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
          ),
        ),

        SizedBox(height: modoCompacto ? 4 : 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _espanol
                ? 'Crea tu cuenta y comienza a organizar tu trayectoria académica.'
                : 'Create your account and start organizing your academic journey.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: modoCompacto ? 13.5 : 15,
              height: modoCompacto ? 1.30 : 1.45,
            ),
          ),
        ),
      ],
    );
  }

  // =========================================================
  // LOGO
  // =========================================================

  Widget _buildLogo(bool modoCompacto, bool oscuro) {
    final double size = modoCompacto ? 50 : 58;

    final double radius = modoCompacto ? 16 : 18;

    final double iconSize = modoCompacto ? 26 : 27;

    if (oscuro) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: ColoredBox(
            color: _primaryColor,
            child: Center(
              child: Icon(
                Icons.school_outlined,
                color: Colors.white,
                size: iconSize,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: const [
          BoxShadow(
            color: Color(0x385B5FEF),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Icon(Icons.school_outlined, color: Colors.white, size: iconSize),
    );
  }

  // =========================================================
  // TARJETA
  // =========================================================

  Widget _buildRegisterCard(bool modoCompacto, bool oscuro) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        modoCompacto ? 20 : 22,
        modoCompacto ? 18 : 22,
        modoCompacto ? 20 : 22,
        modoCompacto ? 18 : 22,
      ),
      decoration: BoxDecoration(
        color: oscuro ? _darkCard : Colors.white,
        borderRadius: BorderRadius.circular(modoCompacto ? 19 : 21),
        border: Border.all(
          color: oscuro ? _darkBorder : const Color(0xFFE7EAF0),
        ),
        boxShadow: oscuro
            ? const []
            : const [
                BoxShadow(
                  color: Color(0x140F172A),
                  blurRadius: 40,
                  offset: Offset(0, 16),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _espanol ? 'NUEVA CUENTA' : 'NEW ACCOUNT',
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),

          SizedBox(height: modoCompacto ? 4 : 6),

          Text(
            _espanol ? 'Crear cuenta' : 'Create account',
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: modoCompacto ? 23 : 25,
              fontWeight: FontWeight.w700,
            ),
          ),

          SizedBox(height: modoCompacto ? 4 : 7),

          Text(
            _espanol
                ? 'Ingresa tus datos para comenzar.'
                : 'Enter your details to get started.',
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: modoCompacto ? 13.5 : 14,
            ),
          ),

          SizedBox(height: modoCompacto ? 16 : 24),

          // ===================================================
          // NOMBRE
          // ===================================================
          _buildLabel(_espanol ? 'Nombre completo' : 'Full name', oscuro),

          SizedBox(height: modoCompacto ? 6 : 8),

          _buildValidatedField(
            focusNode: _nombreFocusNode,
            validationColor: _colorValidacionNombre(),
            child: TextField(
              controller: _nombreController,
              focusNode: _nombreFocusNode,
              enabled: !_cargando,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              onChanged: (_) {
                _actualizarCampos();
              },
              decoration: _inputDecoration(
                hintText: _espanol ? 'Tu nombre' : 'Your name',
                icon: Icons.person_outline,
                modoCompacto: modoCompacto,
                oscuro: oscuro,
                validationColor: _colorValidacionNombre(),
              ),
            ),
          ),

          SizedBox(height: modoCompacto ? 11 : 17),

          // ===================================================
          // CORREO
          // ===================================================
          _buildLabel(
            _espanol ? 'Correo electrónico' : 'Email address',
            oscuro,
          ),

          SizedBox(height: modoCompacto ? 6 : 8),

          _buildValidatedField(
            focusNode: _correoFocusNode,
            validationColor: _colorValidacionCorreo(),
            child: TextField(
              controller: _correoController,
              focusNode: _correoFocusNode,
              enabled: !_cargando,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              onChanged: (_) {
                _actualizarCampos();
              },
              decoration: _inputDecoration(
                hintText: 'correo@ejemplo.com',
                icon: Icons.mail_outline,
                modoCompacto: modoCompacto,
                oscuro: oscuro,
                validationColor: _colorValidacionCorreo(),
              ),
            ),
          ),

          SizedBox(height: modoCompacto ? 11 : 17),

          // ===================================================
          // CONTRASEÑA
          // ===================================================
          _buildLabel(_espanol ? 'Contraseña' : 'Password', oscuro),

          SizedBox(height: modoCompacto ? 6 : 8),

          _buildValidatedField(
            focusNode: _contrasenaFocusNode,
            validationColor: _colorValidacionContrasena(),
            child: TextField(
              controller: _contrasenaController,
              focusNode: _contrasenaFocusNode,
              enabled: !_cargando,
              obscureText: !_mostrarContrasena,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              decoration: _inputDecoration(
                hintText: _espanol
                    ? 'Crea tu contraseña'
                    : 'Create your password',
                icon: Icons.lock_outline,
                modoCompacto: modoCompacto,
                oscuro: oscuro,
                validationColor: _colorValidacionContrasena(),
                suffixIcon: PasswordVisibilityButton(
                  visible: _mostrarContrasena,
                  onPressed: _cargando
                      ? null
                      : () {
                          setState(() {
                            _mostrarContrasena = !_mostrarContrasena;
                          });
                        },
                ),
              ),
            ),
          ),

          _buildPasswordRequirements(oscuro),

          SizedBox(height: modoCompacto ? 11 : 17),

          // ===================================================
          // CONFIRMAR CONTRASEÑA
          // ===================================================
          _buildLabel(
            _espanol ? 'Confirmar contraseña' : 'Confirm password',
            oscuro,
          ),

          SizedBox(height: modoCompacto ? 6 : 8),

          _buildValidatedField(
            focusNode: _confirmarContrasenaFocusNode,
            validationColor: _colorValidacionConfirmacion(),
            child: TextField(
              controller: _confirmarContrasenaController,
              focusNode: _confirmarContrasenaFocusNode,
              enabled: !_cargando,
              obscureText: !_mostrarConfirmacion,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              onSubmitted: (_) {
                if (!_cargando) {
                  _registrar();
                }
              },
              decoration: _inputDecoration(
                hintText: _espanol
                    ? 'Repite tu contraseña'
                    : 'Repeat your password',
                icon: Icons.shield_outlined,
                modoCompacto: modoCompacto,
                oscuro: oscuro,
                validationColor: _colorValidacionConfirmacion(),
                suffixIcon: PasswordVisibilityButton(
                  visible: _mostrarConfirmacion,
                  onPressed: _cargando
                      ? null
                      : () {
                          setState(() {
                            _mostrarConfirmacion = !_mostrarConfirmacion;
                          });
                        },
                ),
              ),
            ),
          ),

          _buildConfirmationFeedback(oscuro),

          SizedBox(height: modoCompacto ? 8 : 14),

          // ===================================================
          // ERROR
          // ===================================================
          AuthStatusMessage(
            message: _errorMessage,
            padding: const EdgeInsets.only(bottom: 6),
          ),
          SizedBox(height: modoCompacto ? 4 : 8),

          // ===================================================
          // BOTÓN CREAR CUENTA
          // ===================================================
          SizedBox(
            height: modoCompacto ? 50 : 52,
            child: ElevatedButton(
              onPressed: _cargando ? null : _registrar,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _primaryColor.withValues(alpha: 0.55),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
                elevation: 0,
                shadowColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: AuthButtonContent(
                loading: _cargando,
                label: _espanol ? 'Crear cuenta' : 'Create account',
                loadingLabel: _espanol
                    ? 'Creando cuenta...'
                    : 'Creating account...',
              ),
            ),
          ),

          SizedBox(height: modoCompacto ? 14 : 20),

          // ===================================================
          // VOLVER AL LOGIN
          // ===================================================
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _espanol
                    ? '¿Ya tienes una cuenta? '
                    : 'Already have an account? ',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: modoCompacto ? 13.5 : 14,
                ),
              ),
              TextButton(
                onPressed: _cargando ? null : _volverAlLogin,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _espanol ? 'Iniciar sesión' : 'Sign in',
                  style: TextStyle(
                    color: _primaryColor,
                    fontSize: modoCompacto ? 13.5 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================
  // CONTENEDOR DE VALIDACIÓN
  // =========================================================

  Widget _buildValidatedField({
    required FocusNode focusNode,
    required Color? validationColor,
    required Widget child,
  }) {
    final Color haloColor = validationColor ?? _primaryColor;

    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: focusNode.hasFocus
            ? [
                BoxShadow(
                  color: haloColor.withValues(alpha: 0.11),
                  blurRadius: 0,
                  spreadRadius: 4,
                ),
              ]
            : const [],
      ),
      child: child,
    );
  }

  // =========================================================
  // TEXTO DEL INPUT
  // =========================================================

  TextStyle _inputTextStyle(bool oscuro) {
    return TextStyle(
      color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
      fontSize: 15,
    );
  }

  // =========================================================
  // REQUISITOS Y CONFIRMACIÓN
  // =========================================================

  Widget _buildPasswordRequirements(bool oscuro) {
    final validacion = ValidacionContrasena(_contrasenaController.text);
    return AppAnimatedVisibility(
      visible: !_requisitosOcultos,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 10, 2, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPasswordStatus(
              text: _espanol ? 'Mínimo 8 caracteres' : 'At least 8 characters',
              cumplido: validacion.longitudValida,
              oscuro: oscuro,
            ),
            const SizedBox(height: 5),
            _buildPasswordStatus(
              text: _espanol ? 'Al menos 1 número' : 'At least 1 number',
              cumplido: validacion.tieneNumero,
              oscuro: oscuro,
            ),
            const SizedBox(height: 5),
            _buildPasswordStatus(
              text: _espanol
                  ? 'Al menos 1 carácter especial'
                  : 'At least 1 special character',
              cumplido: validacion.tieneCaracterEspecial,
              oscuro: oscuro,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationFeedback(bool oscuro) {
    final String contrasena = _contrasenaController.text;
    final String confirmacion = _confirmarContrasenaController.text;
    final bool coinciden = _confirmacionValida();
    final bool comparar =
        contrasena.isNotEmpty &&
        confirmacion.isNotEmpty &&
        (coinciden ||
            confirmacion.runes.length >= 3 ||
            confirmacion.length >= contrasena.length ||
            !_confirmarContrasenaFocusNode.hasFocus);

    return AppAnimatedVisibility(
      visible: comparar && !_requisitosOcultos,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 9, 2, 0),
        child: Semantics(
          liveRegion: true,
          child: _buildPasswordStatus(
            text: coinciden
                ? (_espanol ? 'Las contraseñas coinciden' : 'Passwords match')
                : (_espanol
                      ? 'Las contraseñas aún no coinciden'
                      : 'Passwords do not match yet'),
            cumplido: coinciden,
            oscuro: oscuro,
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordStatus({
    required String text,
    required bool cumplido,
    required bool oscuro,
  }) {
    final Color color = cumplido
        ? (oscuro ? const Color(0xFF6EE7B7) : const Color(0xFF047857))
        : (oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280));
    final Duration duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    return Semantics(
      label:
          '$text. ${cumplido ? (_espanol ? 'Cumplido' : 'Met') : (_espanol ? 'Pendiente' : 'Pending')}',
      excludeSemantics: true,
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(begin: color, end: color),
        duration: duration,
        builder: (context, color, child) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedSwitcher(
              duration: duration,
              child: Icon(
                cumplido
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                key: ValueKey(cumplido),
                size: 17,
                color: color,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================
  // LABEL
  // =========================================================

  Widget _buildLabel(String text, bool oscuro) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        text,
        style: TextStyle(
          color: oscuro ? const Color(0xFFC4CAD4) : const Color(0xFF374151),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  // =========================================================
  // INPUTS
  // =========================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
    required bool modoCompacto,
    required bool oscuro,
    Widget? suffixIcon,
    Color? validationColor,
  }) {
    return InputDecoration(
      hintText: hintText,

      hintStyle: TextStyle(
        color: oscuro ? const Color(0xFF747E8D) : const Color(0xFF9CA3AF),
        fontSize: 15,
      ),

      prefixIcon: Icon(icon, size: 20),

      prefixIconColor: WidgetStateColor.resolveWith((states) {
        if (validationColor != null) {
          return validationColor;
        }

        if (states.contains(WidgetState.focused)) {
          return _primaryColor;
        }

        if (states.contains(WidgetState.disabled)) {
          return oscuro ? const Color(0xFF636C79) : const Color(0xFFB6BCC6);
        }

        return oscuro ? const Color(0xFF8C96A5) : const Color(0xFF9CA3AF);
      }),

      suffixIcon: suffixIcon,

      filled: true,

      fillColor: WidgetStateColor.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return oscuro ? _darkInputFocus : Colors.white;
        }

        return oscuro ? _darkInput : const Color(0xFFFAFBFC);
      }),

      isDense: modoCompacto,

      contentPadding: EdgeInsets.symmetric(
        vertical: modoCompacto ? 13 : 16,
        horizontal: 15,
      ),

      constraints: BoxConstraints(minHeight: modoCompacto ? 48 : 52),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color:
              validationColor ??
              (oscuro ? _darkInputBorder : const Color(0xFFDFE3EA)),
          width: validationColor == null ? 1 : 1.5,
        ),
      ),

      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color:
              validationColor ??
              (oscuro ? _darkInputFocusBorder : const Color(0xFF8B8FF4)),
          width: 1.5,
        ),
      ),

      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: oscuro ? const Color(0xFF2D3540) : const Color(0xFFDFE3EA),
        ),
      ),
    );
  }
}
