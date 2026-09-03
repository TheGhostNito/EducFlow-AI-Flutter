import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

enum EstadoNotificaciones {
  noSolicitadas,
  activadas,
  bloqueadas,
  noCompatibles,
}

enum TipoNotificacionLocal { general, clase, tarea, evaluacion }

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _permisoSolicitadoKey =
      'educflow-notifications-permission-requested';

  bool _inicializado = false;
  bool _zonaHorariaLista = false;

  /// Payload de la última notificación del sistema pulsada.
  ///
  /// MainNavigation escucha este notifier al montarse tras la autenticación,
  /// para seleccionar Notificaciones sin apilar secciones principales.
  final ValueNotifier<String?> notificationPayload = ValueNotifier<String?>(
    null,
  );

  // =========================================================
  // INICIALIZACIÓN
  // =========================================================

  Future<void> inicializar() async {
    if (_inicializado) {
      return;
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _publicarPayload(response.payload);
      },
    );

    // Si Android/iOS abrió EduFlow desde una notificación
    // cuando el proceso estaba completamente cerrado, aquí
    // recuperamos ese payload para procesarlo después del login.
    final NotificationAppLaunchDetails? launchDetails = await _plugin
        .getNotificationAppLaunchDetails();

    if (launchDetails?.didNotificationLaunchApp == true) {
      _publicarPayload(launchDetails?.notificationResponse?.payload);
    }

    await _inicializarZonaHoraria();

    _inicializado = true;
  }

  Future<void> _inicializarZonaHoraria() async {
    if (kIsWeb) {
      return;
    }

    try {
      tz.initializeTimeZones();

      final TimezoneInfo timezoneInfo =
          await FlutterTimezone.getLocalTimezone();

      final tz.Location location = tz.getLocation(timezoneInfo.identifier);

      tz.setLocalLocation(location);

      _zonaHorariaLista = true;

      debugPrint(
        'Zona horaria de notificaciones: '
        '${timezoneInfo.identifier}',
      );
    } catch (error) {
      _zonaHorariaLista = false;

      debugPrint(
        'No se pudo inicializar la zona horaria '
        'para notificaciones: $error',
      );
    }
  }

  // =========================================================
  // APERTURA DESDE NOTIFICACIONES DEL SISTEMA
  // =========================================================

  void _publicarPayload(String? value) {
    final String payload = value?.trim() ?? '';

    if (payload.isEmpty) {
      return;
    }

    debugPrint('Notificación pulsada. Payload: $payload');

    notificationPayload.value = payload;
  }

  void consumirPayload(String payload) {
    if (notificationPayload.value == payload) {
      notificationPayload.value = null;
    }
  }

  // =========================================================
  // PERMISOS
  // =========================================================

  Future<EstadoNotificaciones> obtenerEstado() async {
    await inicializar();

    if (kIsWeb) {
      return EstadoNotificaciones.noCompatibles;
    }

    final SharedPreferences preferences = await SharedPreferences.getInstance();

    final bool permisoSolicitado =
        preferences.getBool(_permisoSolicitadoKey) ?? false;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        if (androidPlugin == null) {
          return EstadoNotificaciones.noCompatibles;
        }

        final bool activadas =
            await androidPlugin.areNotificationsEnabled() ?? false;

        if (activadas) {
          return EstadoNotificaciones.activadas;
        }

        return permisoSolicitado
            ? EstadoNotificaciones.bloqueadas
            : EstadoNotificaciones.noSolicitadas;

      case TargetPlatform.iOS:
        final IOSFlutterLocalNotificationsPlugin? iosPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

        if (iosPlugin == null) {
          return EstadoNotificaciones.noCompatibles;
        }

        final NotificationsEnabledOptions? permisos = await iosPlugin
            .checkPermissions();

        if (permisos?.isEnabled == true) {
          return EstadoNotificaciones.activadas;
        }

        return permisoSolicitado
            ? EstadoNotificaciones.bloqueadas
            : EstadoNotificaciones.noSolicitadas;

      default:
        return EstadoNotificaciones.noCompatibles;
    }
  }

  Future<EstadoNotificaciones> solicitarPermiso() async {
    await inicializar();

    if (kIsWeb) {
      return EstadoNotificaciones.noCompatibles;
    }

    bool? autorizado;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();

        autorizado = await androidPlugin?.requestNotificationsPermission();

        break;

      case TargetPlatform.iOS:
        final IOSFlutterLocalNotificationsPlugin? iosPlugin = _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >();

        autorizado = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

        break;

      default:
        return EstadoNotificaciones.noCompatibles;
    }

    final SharedPreferences preferences = await SharedPreferences.getInstance();

    await preferences.setBool(_permisoSolicitadoKey, true);

    if (autorizado == true) {
      return EstadoNotificaciones.activadas;
    }

    return obtenerEstado();
  }

  Future<void> abrirAjustesDelSistema() async {
    await inicializar();

    await _plugin.openAppNotificationSettings();
  }

  // =========================================================
  // NOTIFICACIÓN INMEDIATA
  // =========================================================

  Future<void> mostrarNotificacionPrueba({required bool espanol}) async {
    await inicializar();

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'educflow_general',
        'EducFlow AI',
        channelDescription: 'Avisos generales de EducFlow AI',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    await _plugin.show(
      id: 9001,
      title: 'EducFlow AI',
      body: espanol
          ? 'Las notificaciones están funcionando correctamente 🎉'
          : 'Notifications are working correctly 🎉',
      notificationDetails: details,
    );
  }

  // =========================================================
  // PROGRAMACIÓN LOCAL
  // =========================================================

  Future<bool> programarNotificacion({
    required int id,
    required String titulo,
    required String cuerpo,
    required DateTime fechaHora,
    required TipoNotificacionLocal tipo,
    String? payload,
  }) async {
    await inicializar();

    if (kIsWeb || !_esPlataformaMovil || !_zonaHorariaLista) {
      return false;
    }

    final EstadoNotificaciones estado = await obtenerEstado();

    if (estado != EstadoNotificaciones.activadas) {
      return false;
    }

    final tz.TZDateTime programada = tz.TZDateTime(
      tz.local,
      fechaHora.year,
      fechaHora.month,
      fechaHora.day,
      fechaHora.hour,
      fechaHora.minute,
      fechaHora.second,
    );

    final tz.TZDateTime ahora = tz.TZDateTime.now(tz.local);

    if (!programada.isAfter(ahora)) {
      return false;
    }

    final NotificationDetails details = _detallesParaTipo(tipo);

    await _plugin.zonedSchedule(
      id: id,
      title: titulo,
      body: cuerpo,
      scheduledDate: programada,
      notificationDetails: details,

      // Para recordatorios académicos no necesitamos
      // pedir el permiso especial de "alarma exacta".
      // El sistema puede entregarla aproximadamente
      // alrededor de la hora indicada incluso en reposo.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,

      payload: payload,
    );

    return true;
  }

  Future<bool> programarPruebaEnSegundos({
    required bool espanol,
    int segundos = 20,
  }) async {
    final DateTime fecha = DateTime.now().add(Duration(seconds: segundos));

    return programarNotificacion(
      id: 9002,
      titulo: 'EducFlow AI',
      cuerpo: espanol
          ? 'Esta es una notificación programada 🎉'
          : 'This is a scheduled notification 🎉',
      fechaHora: fecha,
      tipo: TipoNotificacionLocal.general,
      payload: 'test',
    );
  }

  NotificationDetails _detallesParaTipo(TipoNotificacionLocal tipo) {
    switch (tipo) {
      case TipoNotificacionLocal.clase:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'educflow_classes',
            'Clases',
            channelDescription: 'Recordatorios de clases de EducFlow AI',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );

      case TipoNotificacionLocal.tarea:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'educflow_tasks',
            'Tareas',
            channelDescription: 'Recordatorios de tareas de EducFlow AI',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );

      case TipoNotificacionLocal.evaluacion:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'educflow_evaluations',
            'Evaluaciones',
            channelDescription: 'Recordatorios de evaluaciones de EducFlow AI',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );

      case TipoNotificacionLocal.general:
        return const NotificationDetails(
          android: AndroidNotificationDetails(
            'educflow_general',
            'EducFlow AI',
            channelDescription: 'Avisos generales de EducFlow AI',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );
    }
  }

  // =========================================================
  // CANCELACIÓN / CONSULTA
  // =========================================================

  Future<void> cancelarNotificacion(int id) async {
    await inicializar();

    await _plugin.cancel(id: id);
  }

  Future<void> cancelarTodasLasProgramadas() async {
    await inicializar();

    await _plugin.cancelAllPendingNotifications();
  }

  Future<List<PendingNotificationRequest>> obtenerProgramadas() async {
    await inicializar();

    return _plugin.pendingNotificationRequests();
  }

  bool get _esPlataformaMovil {
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
