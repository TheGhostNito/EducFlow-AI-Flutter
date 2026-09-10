import 'dart:async';

import 'package:eduflow_ai/services/beta_notice_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'una excepción al adquirir libera la reserva y permite reintentar',
    () async {
      var currentUid = 'a';
      var attempts = 0;
      final service = BetaNoticeService.forTesting(
        currentUid: () => currentUid,
        loadLocalPreferences: () async {
          attempts++;
          if (attempts == 1) throw StateError('preferencias');
          return SharedPreferences.getInstance();
        },
      );

      await expectLater(
        service.reserveIfShouldShow('a', BetaNoticeKind.welcome),
        throwsStateError,
      );
      final retry = await service.reserveIfShouldShow(
        'a',
        BetaNoticeKind.welcome,
      );

      expect(retry, isNotNull);
      service.release(retry!);
      currentUid = '';
    },
  );

  test(
    'la reserva pendiente de A no bloquea una reserva distinta de B',
    () async {
      var currentUid = 'a';
      final aRemoteRead = Completer<void>();
      final aReadStarted = Completer<void>();
      final service = BetaNoticeService.forTesting(
        currentUid: () => currentUid,
        loadRemoteNotices: (uid) async {
          if (uid == 'a') {
            aReadStarted.complete();
            await aRemoteRead.future;
          }
          return null;
        },
      );

      final reservationA = service.reserveIfShouldShow(
        'a',
        BetaNoticeKind.welcome,
      );
      await aReadStarted.future;

      currentUid = 'b';
      final reservationB = await service.reserveIfShouldShow(
        'b',
        BetaNoticeKind.welcome,
      );

      expect(reservationB, isNotNull);
      aRemoteRead.complete();
      expect(await reservationA, isNull);
      service.release(reservationB!);
    },
  );

  test(
    'el mismo UID y tipo no puede adquirir dos reservas simultáneas',
    () async {
      const currentUid = 'a';
      final service = BetaNoticeService.forTesting(
        currentUid: () => currentUid,
      );

      final first = await service.reserveIfShouldShow(
        currentUid,
        BetaNoticeKind.ai,
      );
      final duplicate = await service.reserveIfShouldShow(
        currentUid,
        BetaNoticeKind.ai,
      );

      expect(first, isNotNull);
      expect(duplicate, isNull);
      service.release(first!);
      expect(
        await service.reserveIfShouldShow(currentUid, BetaNoticeKind.ai),
        isNotNull,
      );
    },
  );

  test(
    'markShown suspendido no confirma después de cambiar de sesión',
    () async {
      var currentUid = 'a';
      var generationIsValid = true;
      final remoteMarkStarted = Completer<void>();
      final remoteMarkPending = Completer<void>();
      final service = BetaNoticeService.forTesting(
        currentUid: () => currentUid,
        markRemoteSeen: (_, _) async {
          remoteMarkStarted.complete();
          await remoteMarkPending.future;
        },
      );
      final reservation = (await service.reserveIfShouldShow(
        'a',
        BetaNoticeKind.welcome,
      ))!;

      final marking = service.markShown(
        reservation,
        isValid: () => generationIsValid,
      );
      await remoteMarkStarted.future;
      currentUid = 'b';
      generationIsValid = false;
      remoteMarkPending.complete();

      expect(await marking, isFalse);
      final local = await SharedPreferences.getInstance();
      expect(local.getBool('educflow-user-a-beta-0.1-welcome-seen'), isNull);
      expect(local.getBool('educflow-user-b-beta-0.1-welcome-seen'), isNull);
      service.release(reservation);
    },
  );
}
