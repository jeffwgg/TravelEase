import 'dart:async';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/services/flash_alert_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.svprdga.torchlight/main');
  final service = FlashAlertService.instance;
  final calls = <String>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return call.method == 'torch_available' ? true : null;
        });
  });
  tearDown(() async {
    await service.stopSosFlash();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'one torch session stays on through notification flashes until stopped',
    () async {
      await service.startSosFlash();
      await service.startSosFlash();
      await service.blinkTwice();
      expect(calls.where((call) => call == 'enable_torch'), hasLength(1));
      expect(calls, isNot(contains('disable_torch')));
      await service.stopSosFlash();
      expect(calls.last, 'disable_torch');
      expect(
        IsolateNameServer.lookupPortByName('travelease.sos.torch'),
        isNull,
      );
    },
  );

  test(
    'background-isolate ownership suppresses notification torch operations',
    () async {
      final owner = ReceivePort();
      IsolateNameServer.registerPortWithName(
        owner.sendPort,
        'travelease.sos.torch',
      );
      try {
        await service.blinkTwice();
        expect(calls, isEmpty);
      } finally {
        IsolateNameServer.removePortNameMapping('travelease.sos.torch');
        owner.close();
      }
    },
  );

  test('stop racing slow torch startup still leaves the torch off', () async {
    final availability = Completer<bool>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'torch_available') return availability.future;
          return null;
        });
    final starting = service.startSosFlash();
    await Future<void>.delayed(Duration.zero);
    final stopping = service.stopSosFlash();
    availability.complete(true);
    await Future.wait([starting, stopping]);
    expect(calls.last, 'disable_torch');
    expect(IsolateNameServer.lookupPortByName('travelease.sos.torch'), isNull);
  });
}
