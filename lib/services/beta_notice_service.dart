import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BetaNoticeKind { welcome, ai }

class BetaNoticeService {
  BetaNoticeService._();

  static final BetaNoticeService instance = BetaNoticeService._();

  static const String betaVersion = '0.1';

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String? get _uid => _auth.currentUser?.uid;

  String _remoteKey(BetaNoticeKind kind) {
    switch (kind) {
      case BetaNoticeKind.welcome:
        return 'beta01Bienvenida';

      case BetaNoticeKind.ai:
        return 'beta01Ia';
    }
  }

  String _localKey(String uid, BetaNoticeKind kind) {
    final String suffix = switch (kind) {
      BetaNoticeKind.welcome => 'welcome',
      BetaNoticeKind.ai => 'ai',
    };

    return 'educflow-user-$uid-beta-$betaVersion-$suffix-seen';
  }

  Future<bool> shouldShow(BetaNoticeKind kind) async {
    final String? uid = _uid;

    if (uid == null) {
      return false;
    }

    final SharedPreferences local = await SharedPreferences.getInstance();

    final String localKey = _localKey(uid, kind);

    if (local.getBool(localKey) == true) {
      return false;
    }

    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
          .collection('usuarios')
          .doc(uid)
          .get();

      final Map<String, dynamic>? data = snapshot.data();

      final dynamic rawNotices = data?['avisosBeta'];

      if (rawNotices is Map) {
        final Map<String, dynamic> notices = Map<String, dynamic>.from(
          rawNotices,
        );

        if (notices[_remoteKey(kind)] == true) {
          await local.setBool(localKey, true);

          return false;
        }
      }
    } catch (_) {
      // Si Firestore no responde, mostramos el aviso.
      // Al marcarlo guardaremos primero la copia local
      // para no repetirlo innecesariamente.
    }

    return true;
  }

  Future<void> markShown(BetaNoticeKind kind) async {
    final String? uid = _uid;

    if (uid == null) {
      return;
    }

    final SharedPreferences local = await SharedPreferences.getInstance();

    await local.setBool(_localKey(uid, kind), true);

    final DocumentReference<Map<String, dynamic>> ref = _firestore
        .collection('usuarios')
        .doc(uid);

    final String field = 'avisosBeta.${_remoteKey(kind)}';

    try {
      await ref.update({field: true});
    } catch (_) {
      try {
        await ref.set({
          'avisosBeta': {_remoteKey(kind): true},
        }, SetOptions(merge: true));
      } catch (_) {
        // La copia local ya quedó marcada.
      }
    }
  }
}
