// Configuración pública de la app Android registrada en Firebase Testing.
// No reemplaza las opciones de producción generadas por FlutterFire.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

class TestingFirebaseOptions {
  const TestingFirebaseOptions._();

  static const android = FirebaseOptions(
    apiKey: 'AIzaSyBedlMAStTLAJ0tAykp4_GTJVhoGU3Lrbc',
    appId: '1:495312343955:android:3ca51a17095d2702f9ce66',
    messagingSenderId: '495312343955',
    projectId: 'eduflow-ai-testing',
    storageBucket: 'eduflow-ai-testing.firebasestorage.app',
  );
}
