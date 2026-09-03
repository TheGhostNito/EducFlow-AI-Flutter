import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_service.dart';
import '../../services/translation_service.dart';
import '../../widgets/auth_feedback.dart';
import '../../widgets/language_selector.dart';
import '../../widgets/theme_toggle_button.dart';
import '../dashboard/dashboard_page.dart';
import '../register/register_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // =========================================================
  // CONTROLADORES
  // =========================================================

  final TextEditingController _emailController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final FocusNode _emailFocusNode = FocusNode();
  final FocusNode _passwordFocusNode = FocusNode();

  final AuthService _authService = AuthService();

  final TranslationService _translationService = TranslationService.instance;

  // =========================================================
  // ESTADO
  // =========================================================

  bool _isLoading = false;
  bool _isRecoveringPassword = false;
  bool _mostrarContrasena = false;

  bool _credencialesInvalidas = false;

  String _errorMessage = '';
  String _successMessage = '';

  bool get _actionInProgress => _isLoading || _isRecoveringPassword;

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
  // VALIDACIÓN VISUAL
  // =========================================================

  bool _correoValido(String correo) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(correo);
  }

  Color? _colorValidacionCorreo() {
    final String correo = _emailController.text.trim();

    if (correo.isEmpty) {
      return null;
    }

    if (_emailFocusNode.hasFocus) {
      return _primaryColor;
    }

    if (_credencialesInvalidas) {
      return _errorColor;
    }

    return _correoValido(correo) ? _successColor : _errorColor;
  }

  Color? _colorValidacionContrasena() {
    final String contrasena = _passwordController.text;

    if (contrasena.isEmpty) {
      return null;
    }

    if (_passwordFocusNode.hasFocus) {
      return _primaryColor;
    }

    if (_credencialesInvalidas) {
      return _errorColor;
    }

    // En Login no podemos saber localmente
    // si la contraseña es correcta.
    // Firebase es quien debe confirmarlo.
    return _primaryColor;
  }

  void _credencialModificada() {
    if (!mounted) {
      return;
    }

    setState(() {
      _credencialesInvalidas = false;
      _errorMessage = '';
      _successMessage = '';
    });
  }

  // =========================================================
  // INICIAR SESIÓN
  // =========================================================

  Future<void> _iniciarSesion() async {
    if (_actionInProgress) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String correo = _emailController.text.trim().toLowerCase();

    final String contrasena = _passwordController.text;

    if (correo.isEmpty || contrasena.isEmpty) {
      setState(() {
        _credencialesInvalidas = false;

        _errorMessage = _espanol
            ? 'Debes ingresar tu correo y contraseña.'
            : 'You must enter your email and password.';

        _successMessage = '';
      });

      return;
    }

    if (!_correoValido(correo)) {
      setState(() {
        _credencialesInvalidas = false;

        _errorMessage = _espanol
            ? 'Ingresa un correo electrónico válido.'
            : 'Enter a valid email address.';

        _successMessage = '';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _credencialesInvalidas = false;
      _errorMessage = '';
      _successMessage = '';
    });

    try {
      await _authService.iniciarSesion(correo: correo, contrasena: contrasena);

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
          case 'invalid-credential':
          case 'user-not-found':
          case 'wrong-password':
            _credencialesInvalidas = true;

            _errorMessage = _espanol
                ? 'Correo o contraseña incorrectos.'
                : 'Incorrect email or password.';
            break;

          case 'invalid-email':
            _credencialesInvalidas = false;

            _errorMessage = _espanol
                ? 'El correo ingresado no es válido.'
                : 'The email address is not valid.';
            break;

          case 'too-many-requests':
            _credencialesInvalidas = false;

            _errorMessage = _espanol
                ? 'Demasiados intentos. Espera unos minutos e inténtalo nuevamente.'
                : 'Too many attempts. Wait a few minutes and try again.';
            break;

          case 'network-request-failed':
            _credencialesInvalidas = false;

            _errorMessage = _espanol
                ? 'No se pudo conectar con Firebase. Revisa tu conexión a internet.'
                : 'Firebase could not be reached. Check your internet connection.';
            break;

          case 'user-disabled':
            _credencialesInvalidas = false;

            _errorMessage = _espanol
                ? 'Esta cuenta se encuentra deshabilitada.'
                : 'This account has been disabled.';
            break;

          default:
            _credencialesInvalidas = false;

            _errorMessage = _espanol
                ? 'Ocurrió un problema. Inténtalo nuevamente.'
                : 'Something went wrong. Please try again.';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _credencialesInvalidas = false;

        _errorMessage = _espanol
            ? 'Ocurrió un problema. Inténtalo nuevamente.'
            : 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // =========================================================
  // RECUPERAR CONTRASEÑA
  // =========================================================

  Future<void> _recuperarContrasena() async {
    if (_actionInProgress) {
      return;
    }

    FocusScope.of(context).unfocus();

    final String correo = _emailController.text.trim().toLowerCase();

    setState(() {
      _credencialesInvalidas = false;
      _errorMessage = '';
      _successMessage = '';
    });

    if (correo.isEmpty) {
      setState(() {
        _errorMessage = _espanol
            ? 'Ingresa tu correo para enviarte el enlace de recuperación.'
            : 'Enter your email to receive the recovery link.';
      });

      return;
    }

    if (!_correoValido(correo)) {
      setState(() {
        _errorMessage = _espanol
            ? 'El correo ingresado no es válido.'
            : 'The email address is not valid.';
      });

      return;
    }

    setState(() {
      _isRecoveringPassword = true;
    });

    try {
      await _authService.recuperarContrasena(correo: correo);

      if (!mounted) {
        return;
      }

      setState(() {
        _successMessage = _espanol
            ? 'Si existe una cuenta asociada, recibirás un correo para restablecer tu contraseña.'
            : 'If an account is associated with that email, you will receive a password reset message.';
      });
    } on FirebaseAuthException catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        switch (error.code) {
          case 'invalid-email':
            _errorMessage = _espanol
                ? 'El correo ingresado no es válido.'
                : 'The email address is not valid.';
            break;

          case 'network-request-failed':
            _errorMessage = _espanol
                ? 'No fue posible enviar el correo. Revisa tu conexión a internet.'
                : 'The email could not be sent. Check your internet connection.';
            break;

          default:
            _errorMessage = _espanol
                ? 'Ocurrió un problema. Inténtalo nuevamente.'
                : 'Something went wrong. Please try again.';
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _isRecoveringPassword = false;
        });
      }
    }
  }

  // =========================================================
  // CICLO DE VIDA
  // =========================================================

  @override
  void initState() {
    super.initState();

    _translationService.addListener(_actualizarIdioma);

    _emailFocusNode.addListener(_actualizarFoco);

    _passwordFocusNode.addListener(_actualizarFoco);
  }

  void _actualizarIdioma() {
    if (mounted) {
      setState(() {});
    }
  }

  void _actualizarFoco() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _translationService.removeListener(_actualizarIdioma);

    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();

    _emailController.dispose();
    _passwordController.dispose();

    super.dispose();
  }

  // =========================================================
  // BUILD
  // =========================================================

  @override
  Widget build(BuildContext context) {
    final bool oscuro = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // =============================================
                // BOTONES SUPERIORES
                // =============================================

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ThemeToggleButton(disabled: _actionInProgress),
                    LanguageSelector(
                      disabled: _actionInProgress,
                      onLanguageChanged: () {
                        setState(() {
                          _errorMessage = '';
                          _successMessage = '';
                          _credencialesInvalidas = false;
                        });
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 26),

                _buildBrandSection(oscuro),

                const SizedBox(height: 22),

                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: _buildLoginCard(oscuro),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // =========================================================
  // LOGO / MARCA
  // =========================================================

  Widget _buildBrandSection(bool oscuro) {
    return Column(
      children: [
        _buildLogo(oscuro),

        const SizedBox(height: 14),

        Text(
          'EducFlow AI',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.1,
          ),
        ),

        const SizedBox(height: 8),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            _espanol
                ? 'Organiza tu vida académica de forma inteligente.'
                : 'Organize your academic life intelligently.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 15,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo(bool oscuro) {
    if (oscuro) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: const SizedBox(
          width: 58,
          height: 58,
          child: ColoredBox(
            color: _primaryColor,
            child: Center(
              child: Icon(Icons.school_outlined, color: Colors.white, size: 27),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x385B5FEF),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: const Icon(Icons.school_outlined, color: Colors.white, size: 27),
    );
  }

  // =========================================================
  // TARJETA LOGIN
  // =========================================================

  Widget _buildLoginCard(bool oscuro) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: oscuro ? _darkCard : Colors.white,
        borderRadius: BorderRadius.circular(21),
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
            _espanol ? 'BIENVENIDO' : 'WELCOME',
            style: const TextStyle(
              color: _primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            _espanol ? 'Inicia sesión' : 'Sign in',
            style: TextStyle(
              color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
              fontSize: 25,
              fontWeight: FontWeight.w700,
            ),
          ),

          const SizedBox(height: 7),

          Text(
            _espanol
                ? 'Ingresa tus datos para continuar.'
                : 'Enter your details to continue.',
            style: TextStyle(
              color: oscuro ? const Color(0xFFA9B1BF) : const Color(0xFF6B7280),
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 24),

          // ===================================================
          // CORREO
          // ===================================================
          _buildLabel(_espanol ? 'Correo electrónico' : 'Email', oscuro),

          const SizedBox(height: 8),

          _buildValidatedField(
            focusNode: _emailFocusNode,
            validationColor: _colorValidacionCorreo(),
            child: TextField(
              controller: _emailController,
              focusNode: _emailFocusNode,
              enabled: !_actionInProgress,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.email],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              onChanged: (_) {
                _credencialModificada();
              },
              decoration: _inputDecoration(
                hintText: _espanol ? 'nombre@correo.com' : 'name@email.com',
                icon: Icons.mail_outline,
                oscuro: oscuro,
                validationColor: _colorValidacionCorreo(),
              ),
            ),
          ),

          const SizedBox(height: 17),

          // ===================================================
          // CONTRASEÑA
          // ===================================================
          _buildLabel(_espanol ? 'Contraseña' : 'Password', oscuro),

          const SizedBox(height: 8),

          _buildValidatedField(
            focusNode: _passwordFocusNode,
            validationColor: _colorValidacionContrasena(),
            child: TextField(
              controller: _passwordController,
              focusNode: _passwordFocusNode,
              enabled: !_actionInProgress,
              obscureText: !_mostrarContrasena,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              cursorColor: _primaryColor,
              style: _inputTextStyle(oscuro),
              onChanged: (_) {
                _credencialModificada();
              },
              onSubmitted: (_) {
                if (!_actionInProgress) {
                  _iniciarSesion();
                }
              },
              decoration: _inputDecoration(
                hintText: _espanol
                    ? 'Ingresa tu contraseña'
                    : 'Enter your password',
                icon: Icons.lock_outline,
                oscuro: oscuro,
                validationColor: _colorValidacionContrasena(),
                suffixIcon: PasswordVisibilityButton(
                  visible: _mostrarContrasena,
                  onPressed: _actionInProgress
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

          const SizedBox(height: 14),

          // ===================================================
          // ERROR
          // ===================================================
          AuthStatusMessage(
            message: _errorMessage,
            padding: const EdgeInsets.only(bottom: 6),
          ),
          const SizedBox(height: 8),

          // ===================================================
          // BOTÓN INICIAR SESIÓN
          // ===================================================
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _actionInProgress ? null : _iniciarSesion,
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
                loading: _isLoading,
                label: _espanol ? 'Iniciar sesión' : 'Sign in',
                loadingLabel: _espanol ? 'Ingresando...' : 'Signing in...',
              ),
            ),
          ),

          // ===================================================
          // MENSAJE DE ÉXITO
          // ===================================================
          AuthStatusMessage(
            message: _successMessage,
            success: true,
            padding: const EdgeInsets.only(top: 14),
          ),

          const SizedBox(height: 8),

          // ===================================================
          // RECUPERAR CONTRASEÑA
          // ===================================================
          Center(
            child: TextButton(
              onPressed: _actionInProgress ? null : _recuperarContrasena,
              style: TextButton.styleFrom(
                foregroundColor: _primaryColor,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: AuthButtonContent(
                loading: _isRecoveringPassword,
                compact: true,
                label: _espanol
                    ? '¿Olvidaste tu contraseña?'
                    : 'Forgot your password?',
                loadingLabel: _espanol ? 'Enviando...' : 'Sending...',
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ===================================================
          // DIVISOR
          // ===================================================
          Row(
            children: [
              Expanded(
                child: Divider(
                  color: oscuro
                      ? const Color(0xFF303844)
                      : const Color(0xFFE7EAF0),
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  _espanol ? 'o' : 'or',
                  style: TextStyle(
                    color: oscuro
                        ? const Color(0xFF818B99)
                        : const Color(0xFF9CA3AF),
                    fontSize: 13,
                  ),
                ),
              ),

              Expanded(
                child: Divider(
                  color: oscuro
                      ? const Color(0xFF303844)
                      : const Color(0xFFE7EAF0),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ===================================================
          // CREAR CUENTA
          // ===================================================
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _espanol
                    ? '¿No tienes una cuenta? '
                    : 'Don\'t have an account? ',
                style: TextStyle(
                  color: oscuro
                      ? const Color(0xFFA9B1BF)
                      : const Color(0xFF6B7280),
                  fontSize: 14,
                ),
              ),

              TextButton(
                onPressed: _actionInProgress
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const RegisterPage(),
                          ),
                        );
                      },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  _espanol ? 'Crear cuenta' : 'Create account',
                  style: const TextStyle(
                    color: _primaryColor,
                    fontSize: 14,
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
  // ESTILO TEXTO INPUT
  // =========================================================

  TextStyle _inputTextStyle(bool oscuro) {
    return TextStyle(
      color: oscuro ? const Color(0xFFF8FAFC) : const Color(0xFF111827),
      fontSize: 15,
    );
  }

  // =========================================================
  // LABEL DE INPUT
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
  // DECORACIÓN DE INPUTS
  // =========================================================

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData icon,
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

      prefixIcon: Icon(icon),

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

      contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 15),

      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color:
              validationColor ??
              (oscuro ? _darkInputBorder : const Color(0xFFDFE3EA)),
          width: validationColor == null ? 1 : 1.5,
        ),
      ),

      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: oscuro ? const Color(0xFF2D3540) : const Color(0xFFE5E7EB),
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
    );
  }
}
