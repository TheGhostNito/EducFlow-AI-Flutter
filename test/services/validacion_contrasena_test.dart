import 'package:eduflow_ai/services/validacion_contrasena.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exige simultáneamente las tres reglas de registro', () {
    expect(ValidacionContrasena('Abcde1!').esValida, isFalse);
    expect(ValidacionContrasena('Abcdefgh!').esValida, isFalse);
    expect(ValidacionContrasena('Abcdefg1').esValida, isFalse);
    expect(ValidacionContrasena('Abcdef1!').esValida, isTrue);
    expect(ValidacionContrasena('abcdef1!').esValida, isTrue);
    expect(ValidacionContrasena('1234567!').esValida, isTrue);
  });

  test('no confunde espacios ni letras acentuadas con símbolos', () {
    for (final contrasena in ['abcdef1 ', 'contraseña1', 'cafe\u0301abc1']) {
      expect(ValidacionContrasena(contrasena).tieneCaracterEspecial, isFalse);
      expect(ValidacionContrasena(contrasena).esValida, isFalse);
    }
    for (final simbolo in ['!', '@', '_', '¿', '€', '🔒']) {
      expect(ValidacionContrasena('abcdef1$simbolo').esValida, isTrue);
    }
  });

  test('un símbolo fuera del plano básico no cuenta como dos caracteres', () {
    expect(ValidacionContrasena('abcde1🔒').longitudValida, isFalse);
    expect(ValidacionContrasena('abcdef1🔒').longitudValida, isTrue);
  });

  test('borrar todo devuelve los requisitos al estado pendiente', () {
    final validacion = ValidacionContrasena('');
    expect(validacion.longitudValida, isFalse);
    expect(validacion.tieneNumero, isFalse);
    expect(validacion.tieneCaracterEspecial, isFalse);
  });
}
