enum MallaEntryStatus { loading, absent, present, error }

extension MallaEntryStatusText on MallaEntryStatus {
  bool get enabled => this != MallaEntryStatus.loading;

  String title(bool spanish) => switch (this) {
    MallaEntryStatus.present => spanish ? 'Ver tu malla' : 'View curriculum',
    MallaEntryStatus.absent => spanish ? 'Importar malla' : 'Import curriculum',
    MallaEntryStatus.loading =>
      spanish ? 'Consultando malla…' : 'Checking curriculum…',
    MallaEntryStatus.error => spanish ? 'Malla curricular' : 'Curriculum',
  };

  String description(bool spanish) => switch (this) {
    MallaEntryStatus.present =>
      spanish
          ? 'Consulta y corrige tu plan de estudios.'
          : 'View and edit your curriculum.',
    MallaEntryStatus.absent =>
      spanish
          ? 'Analiza tu malla académica para preparar tus ramos.'
          : 'Analyze your curriculum to prepare your courses.',
    MallaEntryStatus.loading =>
      spanish
          ? 'Verificando tu plan de estudios.'
          : 'Checking your curriculum.',
    MallaEntryStatus.error =>
      spanish
          ? 'No pudimos comprobar si tienes una malla guardada.'
          : 'Could not check whether you have a saved curriculum.',
  };
}
