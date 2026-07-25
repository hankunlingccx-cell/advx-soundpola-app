import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soundpola/data/sound_repository.dart';
import 'package:soundpola/device/device_models.dart';
import 'package:soundpola/device/device_registry.dart';
import 'package:soundpola/device/device_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DeviceRegistry.instance.reload();
  });

  test('bindViaQr-less demo bind + write job + confirm success', () async {
    final svc = MockSoundPolaDeviceService.instance;
    await svc.bindDevice('SP-TEST-001');
    expect(DeviceRegistry.instance.hasBoundDevice, isTrue);
    expect(DeviceRegistry.instance.activeDevice?.deviceId, 'SP-TEST-001');

    final progresses = <WriteJobStatus>[];
    final sub = svc.writeProgress.listen((p) => progresses.add(p.status));

    await svc.connect('SP-TEST-001');
    final job = svc.createWriteJob(
      deviceId: 'SP-TEST-001',
      soundId: 'sound_demo',
    );
    expect(job.payload.contains('soundpola'), isTrue);
    expect(job.payload.contains('"soundId"'), isTrue);
    expect(job.payload.toLowerCase().contains('mjpg'), isFalse);

    await svc.sendWriteJob(job);
    expect(svc.activeJob?.status, WriteJobStatus.waitingForCard);
    expect(progresses, contains(WriteJobStatus.waitingForCard));

    svc.mockDetectCard(cardUid: 'UID-AABBCC');
    expect(svc.activeJob?.cardUid, 'UID-AABBCC');
    expect(svc.activeJob?.status, WriteJobStatus.waitingForCard);

    await svc.confirmWrite(job.jobId);
    final result = await svc.queryWriteResult(job.jobId);
    expect(result.verifiedSuccess, isTrue);
    expect(progresses, contains(WriteJobStatus.success));
    expect(progresses, isNot(contains(WriteJobStatus.writeFailed)));

    await sub.cancel();
  });

  test('unbind clears credentials but leaves SoundRepository untouched', () async {
    final svc = MockSoundPolaDeviceService.instance;
    await svc.bindDevice('SP-UNBIND');

    final before =
        SoundRepository.instance.drafts.length +
        SoundRepository.instance.collection.length;
    await DeviceRegistry.instance.unbind('SP-UNBIND');
    expect(DeviceRegistry.instance.getById('SP-UNBIND'), isNull);
    expect(
      SoundRepository.instance.drafts.length +
          SoundRepository.instance.collection.length,
      before,
    );
  });

  test('cardAlreadyBound does not succeed', () async {
    final svc = MockSoundPolaDeviceService.instance;
    await svc.bindDevice('SP-BOUND-CARD');
    await svc.connect('SP-BOUND-CARD');
    final job = svc.createWriteJob(
      deviceId: 'SP-BOUND-CARD',
      soundId: 'sound_x',
    );
    await svc.sendWriteJob(job);
    svc.mockDetectCard(alreadyBound: true);
    final result = await svc.queryWriteResult(job.jobId);
    expect(result.verifiedSuccess, isFalse);
    expect(result.status, WriteJobStatus.cardAlreadyBound);
  });
}
