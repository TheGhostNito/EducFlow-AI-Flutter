import 'package:eduflow_ai/models/malla_entry_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('entrada diferencia plan ausente y confirmado', () {
    expect(MallaEntryStatus.absent.title(true), 'Importar malla');
    expect(MallaEntryStatus.present.title(true), 'Ver tu malla');
    expect(MallaEntryStatus.present.description(true), contains('Consulta'));
  });

  test('carga y error no afirman que la malla está ausente', () {
    expect(MallaEntryStatus.loading.enabled, isFalse);
    expect(MallaEntryStatus.loading.title(true), 'Consultando malla…');
    expect(MallaEntryStatus.error.title(true), 'Malla curricular');
    expect(
      MallaEntryStatus.error.description(true),
      contains('No pudimos comprobar'),
    );
  });
}
