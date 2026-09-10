import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BetaNoticeKind { welcome, ai }

@immutable
class BetaNoticeReservation {
  const BetaNoticeReservation._({
    required this.uid,
    required this.kind,
    required this._owner,
  });

  @visibleForTesting
  factory BetaNoticeReservation.forTesting(String uid, BetaNoticeKind kind) {
    return BetaNoticeReservation._(uid: uid, kind: kind, owner: Object());
  }

  final String uid;
  final BetaNoticeKind kind;
  final Object _owner;
}

abstract interface class BetaNoticeCoordinator {
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  );

  void release(BetaNoticeReservation reservation);

  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  });
}

class BetaNoticeService implements BetaNoticeCoordinator {
  factory BetaNoticeService._() {
    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    return BetaNoticeService._internal(
      currentUid: () => auth.currentUser?.uid,
      loadLocalPreferences: SharedPreferences.getInstance,
      loadRemoteNotices: (uid) async {
        final snapshot = await firestore.collection('usuarios').doc(uid).get();
        final rawNotices = snapshot.data()?['avisosBeta'];
        return rawNotices is Map ? Map<String, dynamic>.from(rawNotices) : null;
      },
      markRemoteSeen: (uid, kind) async {
        final ref = firestore.collection('usuarios').doc(uid);
        final remoteKey = _remoteKey(kind);
        try {
          await ref.update({'avisosBeta.$remoteKey': true});
        } catch (_) {
          await ref.set({
            'avisosBeta': {remoteKey: true},
          }, SetOptions(merge: true));
        }
      },
    );
  }

  BetaNoticeService._internal({
    required this.currentUid,
    required this.loadLocalPreferences,
    required this.loadRemoteNotices,
    required this.markRemoteSeen,
  });

  @visibleForTesting
  factory BetaNoticeService.forTesting({
    required String? Function() currentUid,
    Future<SharedPreferences> Function()? loadLocalPreferences,
    Future<Map<String, dynamic>?> Function(String uid)? loadRemoteNotices,
    Future<void> Function(String uid, BetaNoticeKind kind)? markRemoteSeen,
  }) {
    return BetaNoticeService._internal(
      currentUid: currentUid,
      loadLocalPreferences:
          loadLocalPreferences ?? SharedPreferences.getInstance,
      loadRemoteNotices: loadRemoteNotices ?? (_) async => null,
      markRemoteSeen: markRemoteSeen ?? (_, _) async {},
    );
  }

  static final BetaNoticeService instance = BetaNoticeService._();

  static const String betaVersion = '0.1';

  final String? Function() currentUid;
  final Future<SharedPreferences> Function() loadLocalPreferences;
  final Future<Map<String, dynamic>?> Function(String uid) loadRemoteNotices;
  final Future<void> Function(String uid, BetaNoticeKind kind) markRemoteSeen;
  final Map<String, Object> _reservations = <String, Object>{};

  static String _remoteKey(BetaNoticeKind kind) {
    return switch (kind) {
      BetaNoticeKind.welcome => 'beta01Bienvenida',
      BetaNoticeKind.ai => 'beta01Ia',
    };
  }

  String _localKey(String uid, BetaNoticeKind kind) {
    final suffix = switch (kind) {
      BetaNoticeKind.welcome => 'welcome',
      BetaNoticeKind.ai => 'ai',
    };
    return 'educflow-user-$uid-beta-$betaVersion-$suffix-seen';
  }

  String _reservationKey(String uid, BetaNoticeKind kind) =>
      '$uid:${kind.name}';

  bool _owns(BetaNoticeReservation reservation) {
    return identical(
      _reservations[_reservationKey(reservation.uid, reservation.kind)],
      reservation._owner,
    );
  }

  @override
  Future<BetaNoticeReservation?> reserveIfShouldShow(
    String uid,
    BetaNoticeKind kind,
  ) async {
    if (currentUid() != uid) return null;

    final key = _reservationKey(uid, kind);
    if (_reservations.containsKey(key)) return null;

    final reservation = BetaNoticeReservation._(
      uid: uid,
      kind: kind,
      owner: Object(),
    );
    _reservations[key] = reservation._owner;
    var keepReservation = false;

    try {
      final local = await loadLocalPreferences();
      if (currentUid() != uid || !_owns(reservation)) return null;

      final localKey = _localKey(uid, kind);
      if (local.getBool(localKey) == true) return null;

      try {
        final notices = await loadRemoteNotices(uid);
        if (currentUid() != uid || !_owns(reservation)) return null;
        if (notices?[_remoteKey(kind)] == true) {
          await local.setBool(localKey, true);
          return null;
        }
      } catch (_) {
        // Sin backend, la copia local sigue siendo suficiente para mostrar.
      }

      if (currentUid() != uid || !_owns(reservation)) return null;
      keepReservation = true;
      return reservation;
    } finally {
      if (!keepReservation) release(reservation);
    }
  }

  @override
  void release(BetaNoticeReservation reservation) {
    final key = _reservationKey(reservation.uid, reservation.kind);
    if (_owns(reservation)) _reservations.remove(key);
  }

  @override
  Future<bool> markShown(
    BetaNoticeReservation reservation, {
    required bool Function() isValid,
  }) async {
    bool remainsValid() {
      return _owns(reservation) && currentUid() == reservation.uid && isValid();
    }

    if (!remainsValid()) return false;

    final local = await loadLocalPreferences();
    if (!remainsValid()) return false;

    final localKey = _localKey(reservation.uid, reservation.kind);
    await local.setBool(localKey, true);
    if (!remainsValid()) {
      await local.remove(localKey);
      return false;
    }

    try {
      await markRemoteSeen(reservation.uid, reservation.kind);
    } catch (_) {
      // La marca local confirmada evita repetir el aviso sin conexión.
    }

    if (!remainsValid()) {
      await local.remove(localKey);
      return false;
    }
    return true;
  }
}
