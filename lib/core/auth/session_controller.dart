import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../services/session_preparation_service.dart';
import '../../services/theme_service.dart';
import '../../services/time_format_service.dart';
import '../../services/translation_service.dart';
import '../../services/user_preferences_service.dart';

enum SessionStatus { unauthenticated, preparing, ready, error }

class SessionUserIdentity {
  const SessionUserIdentity({
    required this.uid,
    required this.email,
    required this.displayName,
  });

  factory SessionUserIdentity.fromFirebase(User user) {
    return SessionUserIdentity(
      uid: user.uid,
      email: user.email,
      displayName: user.displayName,
    );
  }

  final String uid;
  final String? email;
  final String? displayName;
}

class RegistrationSessionData {
  const RegistrationSessionData({
    required this.name,
    required this.email,
    required this.language,
    required this.theme,
  });

  final String name;
  final String email;
  final String language;
  final String theme;
}

@immutable
class SessionTicket {
  const SessionTicket({required this.uid, required this.generation});

  final String uid;
  final int generation;
}

typedef SessionValidityGuard = bool Function();
typedef SessionPreparation = Future<void> Function(
  SessionUserIdentity user,
  RegistrationSessionData? registration,
  SessionValidityGuard isValid,
);

class SessionController extends ChangeNotifier {
  SessionController({
    required this.currentUserProvider,
    required Stream<SessionUserIdentity?> authChanges,
    required this.sessionPreparation,
    required this.signOutAction,
    this.afterSignOut,
  }) {
    _authSubscription = authChanges.listen(_handleAuthChange);
    scheduleMicrotask(() => _handleAuthChange(currentUserProvider()));
  }

  static final SessionController instance = SessionController(
    currentUserProvider: () {
      final user = FirebaseAuth.instance.currentUser;
      return user == null ? null : SessionUserIdentity.fromFirebase(user);
    },
    authChanges: FirebaseAuth.instance.authStateChanges().map(
      (user) => user == null ? null : SessionUserIdentity.fromFirebase(user),
    ),
    sessionPreparation: SessionPreparationService.instance.prepare,
    signOutAction: FirebaseAuth.instance.signOut,
    afterSignOut: () async {
      UserPreferencesService.instance.clearMemoryCache();
      ThemeService.instance.resetForSignedOutUser();
      TranslationService.instance.resetForSignedOutUser();
      await TimeFormatService.instance.resetForSignedOutUser();
    },
  );

  @visibleForTesting
  final SessionUserIdentity? Function() currentUserProvider;
  @visibleForTesting
  final SessionPreparation sessionPreparation;
  @visibleForTesting
  final Future<void> Function() signOutAction;
  @visibleForTesting
  final Future<void> Function()? afterSignOut;

  StreamSubscription<SessionUserIdentity?>? _authSubscription;
  SessionStatus _status = SessionStatus.unauthenticated;
  Object? _error;
  String? _activeUid;
  int _generation = 0;
  bool _authenticationInProgress = false;
  RegistrationSessionData? _registrationData;
  String? _registrationUid;
  int? _registrationGeneration;
  void Function(bool ready)? _preparationResultAction;
  String? _preparationResultUid;
  int? _preparationResultGeneration;
  Future<void>? _activePreparation;
  String? _activePreparationUid;
  int? _activePreparationGeneration;

  SessionStatus get status => _status;
  Object? get error => _error;
  String? get activeUid => _activeUid;
  bool get isReady => _status == SessionStatus.ready;

  SessionTicket? captureTicket({bool requireReady = true}) {
    final uid = _activeUid;
    if (uid == null || (requireReady && !isReady)) {
      return null;
    }
    return SessionTicket(uid: uid, generation: _generation);
  }

  bool isCurrentTicket(SessionTicket ticket, {bool requireReady = true}) {
    return _activeUid == ticket.uid &&
        _generation == ticket.generation &&
        currentUserProvider()?.uid == ticket.uid &&
        (!requireReady || isReady);
  }

  Future<T> authenticate<T>({
    required Future<T> Function() operation,
    RegistrationSessionData? registration,
    void Function(bool ready)? onPreparationResult,
  }) async {
    if (_authenticationInProgress) {
      throw StateError('Ya existe una autenticación en curso.');
    }

    _authenticationInProgress = true;

    try {
      final result = await operation();
      final user = currentUserProvider();

      if (user == null) {
        throw StateError('Firebase no entregó el usuario autenticado.');
      }

      _adoptUser(user);
      if (registration != null) {
        _registrationData = registration;
        _registrationUid = user.uid;
        _registrationGeneration = _generation;
      }
      _preparationResultAction = onPreparationResult;
      _preparationResultUid = user.uid;
      _preparationResultGeneration = _generation;
      await requestPreparation();
      return result;
    } catch (_) {
      if (currentUserProvider() == null) {
        _clearRegistrationData();
        _clearPreparationResultAction();
      }
      rethrow;
    } finally {
      _authenticationInProgress = false;

      final user = currentUserProvider();
      if (user != null && _status == SessionStatus.preparing) {
        unawaited(requestPreparation());
      }
    }
  }

  Future<void> requestPreparation() {
    final user = currentUserProvider();

    if (user == null) {
      _setUnauthenticated();
      return Future<void>.value();
    }

    _adoptUser(user);
    final uid = user.uid;
    final generation = _generation;

    final current = _activePreparation;
    if (current != null &&
        _activePreparationUid == uid &&
        _activePreparationGeneration == generation) {
      return current;
    }

    _setState(SessionStatus.preparing);

    final future = _runPreparation(user, generation);
    _activePreparation = future;
    _activePreparationUid = uid;
    _activePreparationGeneration = generation;

    return future.whenComplete(() {
      if (identical(_activePreparation, future)) {
        _activePreparation = null;
        _activePreparationUid = null;
        _activePreparationGeneration = null;
      }
    });
  }

  Future<void> retry() => requestPreparation();

  Future<void> signOut() async {
    final previousUser = currentUserProvider();
    final wasReady = _status == SessionStatus.ready;
    _clearPreparationResultAction();
    _invalidateActiveWork();

    try {
      await signOutAction();
      _clearRegistrationData();
      await afterSignOut?.call();
      _setUnauthenticated();
    } catch (_) {
      final user = currentUserProvider() ?? previousUser;
      if (user != null) {
        if (wasReady) {
          _activeUid = user.uid;
          _setState(SessionStatus.ready);
        } else {
          _adoptUser(user);
          await requestPreparation();
        }
      }
      rethrow;
    }
  }

  Future<void> _runPreparation(SessionUserIdentity user, int generation) async {
    bool isValid() {
      return _generation == generation &&
          _activeUid == user.uid &&
          currentUserProvider()?.uid == user.uid;
    }

    try {
      final registration =
          _registrationUid == user.uid && _registrationGeneration == generation
          ? _registrationData
          : null;
      await sessionPreparation(user, registration, isValid);

      if (!isValid()) {
        return;
      }

      if (_registrationUid == user.uid &&
          _registrationGeneration == generation) {
        _clearRegistrationData();
      }
      _setState(SessionStatus.ready);
      _notifyPreparationResult(user.uid, generation, ready: true);
    } catch (error) {
      if (!isValid()) {
        return;
      }

      _notifyPreparationResult(user.uid, generation, ready: false);
      _error = error;
      _setState(SessionStatus.error, clearError: false);
    }
  }

  void _handleAuthChange(SessionUserIdentity? user) {
    if (user == null) {
      _setUnauthenticated();
      return;
    }

    _adoptUser(user);

    if (_authenticationInProgress) {
      _setState(SessionStatus.preparing);
      return;
    }

    if (_status != SessionStatus.ready || _activeUid != user.uid) {
      unawaited(requestPreparation());
    }
  }

  void _adoptUser(SessionUserIdentity user) {
    if (_activeUid == user.uid) {
      return;
    }

    _clearRegistrationData();
    _clearPreparationResultAction();
    _invalidateActiveWork();
    _activeUid = user.uid;
    _setState(SessionStatus.preparing);
  }

  void _invalidateActiveWork() {
    _generation += 1;
    _activeUid = null;
    _activePreparation = null;
    _activePreparationUid = null;
    _activePreparationGeneration = null;
  }

  void _setUnauthenticated() {
    if (_activeUid != null || _status != SessionStatus.unauthenticated) {
      _invalidateActiveWork();
    }
    _clearRegistrationData();
    _clearPreparationResultAction();
    _setState(SessionStatus.unauthenticated);
  }

  void _clearRegistrationData() {
    _registrationData = null;
    _registrationUid = null;
    _registrationGeneration = null;
  }

  void _notifyPreparationResult(
    String uid,
    int generation, {
    required bool ready,
  }) {
    if (_preparationResultUid != uid ||
        _preparationResultGeneration != generation) {
      return;
    }
    final action = _preparationResultAction;
    _preparationResultAction = null;
    _preparationResultUid = null;
    _preparationResultGeneration = null;
    action?.call(ready);
  }

  void _clearPreparationResultAction() {
    _preparationResultAction = null;
    _preparationResultUid = null;
    _preparationResultGeneration = null;
  }

  void _setState(SessionStatus value, {bool clearError = true}) {
    final changed = _status != value || (clearError && _error != null);
    _status = value;
    if (clearError) {
      _error = null;
    }
    if (changed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
