import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/asignatura.dart';
import '../models/evaluacion.dart';
import '../models/notificacion_app.dart';
import '../models/tarea.dart';
import 'asignaturas_service.dart';
import 'evaluaciones_service.dart';
import 'notification_feed_service.dart';
import 'notification_state_service.dart';
import 'tareas_service.dart';

class NotificationBadgeService extends ChangeNotifier {
  NotificationBadgeService._();

  static final NotificationBadgeService instance = NotificationBadgeService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final AsignaturasService _asignaturasService = AsignaturasService.instance;
  final TareasService _tareasService = TareasService.instance;
  final EvaluacionesService _evaluacionesService = EvaluacionesService.instance;
  final NotificationFeedService _feedService = NotificationFeedService.instance;
  final NotificationStateService _stateService =
      NotificationStateService.instance;

  StreamSubscription<User?>? _authSubscription;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _dataSubscriptions = [];

  Timer? _debounce;

  bool _started = false;
  bool _refreshing = false;
  bool _refreshPending = false;

  int _unreadCount = 0;

  int get unreadCount => _unreadCount;

  bool get hasUnread => _unreadCount > 0;

  void start() {
    if (_started) {
      return;
    }

    _started = true;

    _authSubscription = _auth.authStateChanges().listen(_watchUser);

    _watchUser(_auth.currentUser);
  }

  Future<void> refresh() async {
    final User? user = _auth.currentUser;

    if (user == null) {
      _setUnreadCount(0);
      return;
    }

    if (_refreshing) {
      _refreshPending = true;
      return;
    }

    _refreshing = true;

    try {
      final List<dynamic> resultados = await Future.wait([
        _asignaturasService.obtenerTodas(),
        _tareasService.obtenerTodas(),
        _evaluacionesService.obtenerTodas(),
        _stateService.obtenerEstados(),
      ]);

      final List<Asignatura> asignaturas = resultados[0] as List<Asignatura>;

      final List<Tarea> tareas = resultados[1] as List<Tarea>;

      final List<Evaluacion> evaluaciones = resultados[2] as List<Evaluacion>;

      final Map<String, EstadoNotificacionApp> estados =
          resultados[3] as Map<String, EstadoNotificacionApp>;

      // El idioma no cambia los IDs ni el estado de lectura.
      // Solo necesitamos generar exactamente el mismo feed académico.
      final List<NotificacionApp> generadas = _feedService.generar(
        asignaturas: asignaturas,
        tareas: tareas,
        evaluaciones: evaluaciones,
        spanish: true,
      );

      final List<NotificacionApp> visibles = _stateService.aplicarEstados(
        notificaciones: generadas,
        estados: estados,
      );

      final int cantidad = visibles.where((n) => !n.leida).length;

      _setUnreadCount(cantidad);
    } catch (_) {
      // Si hay un error temporal de red conservamos el último
      // contador conocido para evitar que el badge parpadee.
    } finally {
      _refreshing = false;

      if (_refreshPending) {
        _refreshPending = false;
        unawaited(refresh());
      }
    }
  }

  void _watchUser(User? user) {
    _debounce?.cancel();

    for (final subscription in _dataSubscriptions) {
      unawaited(subscription.cancel());
    }

    _dataSubscriptions.clear();

    if (user == null) {
      _setUnreadCount(0);
      return;
    }

    final DocumentReference<Map<String, dynamic>> userRef = _firestore
        .collection('usuarios')
        .doc(user.uid);

    _listen(userRef.collection('asignaturas'));
    _listen(userRef.collection('tareas'));
    _listen(userRef.collection('evaluaciones'));
    _listen(userRef.collection('estadoNotificaciones'));

    _scheduleRefresh();
  }

  void _listen(CollectionReference<Map<String, dynamic>> collection) {
    final subscription = collection.snapshots().listen(
      (_) {
        _scheduleRefresh();
      },
      onError: (_) {
        // Un listener puede fallar temporalmente sin invalidar
        // el último contador que ya estaba visible.
      },
    );

    _dataSubscriptions.add(subscription);
  }

  void _scheduleRefresh() {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(refresh());
    });
  }

  void _setUnreadCount(int value) {
    final int limpio = value < 0 ? 0 : value;

    if (_unreadCount == limpio) {
      return;
    }

    _unreadCount = limpio;
    notifyListeners();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    unawaited(_authSubscription?.cancel());

    for (final subscription in _dataSubscriptions) {
      unawaited(subscription.cancel());
    }

    _dataSubscriptions.clear();

    super.dispose();
  }
}
