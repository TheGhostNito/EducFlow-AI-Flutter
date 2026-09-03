/// Reglas locales para crear contraseñas. No se aplican al inicio de sesión.
class ValidacionContrasena {
  ValidacionContrasena(String contrasena)
    : longitudValida = contrasena.runes.length >= 8,
      tieneNumero = _numero.hasMatch(contrasena),
      tieneCaracterEspecial = _especial.hasMatch(contrasena);

  static final RegExp _numero = RegExp(r'\p{Nd}', unicode: true);

  // Letras acentuadas y espacios no cuentan como caracteres especiales.
  static final RegExp _especial = RegExp(r'[\p{P}\p{S}]', unicode: true);

  final bool longitudValida;
  final bool tieneNumero;
  final bool tieneCaracterEspecial;

  bool get esValida => longitudValida && tieneNumero && tieneCaracterEspecial;
}
