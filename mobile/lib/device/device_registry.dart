import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'device_models.dart';

/// Persists bound hardware devices. Unbind clears credentials only — never sounds.
class DeviceRegistry extends ChangeNotifier {
  DeviceRegistry._();
  static final instance = DeviceRegistry._();

  static const _prefsKey = 'soundpola_bound_devices_v1';
  static const _activeKey = 'soundpola_active_device_id_v1';

  final List<SoundPolaDevice> _devices = [];
  String? _activeDeviceId;
  bool _loaded = false;

  List<SoundPolaDevice> get devices => List.unmodifiable(_devices);
  String? get activeDeviceId => _activeDeviceId;
  SoundPolaDevice? get activeDevice {
    final id = _activeDeviceId;
    if (id == null) return null;
    for (final d in _devices) {
      if (d.deviceId == id) return d;
    }
    return _devices.isEmpty ? null : _devices.first;
  }

  bool get hasBoundDevice =>
      _devices.any((d) => d.bindingStatus == DeviceBindingStatus.bound);

  Future<void> load() async {
    if (_loaded) return;
    await _readFromPrefs();
    _loaded = true;
    notifyListeners();
  }

  /// Force re-read (tests / after external prefs wipe).
  Future<void> reload() async {
    _loaded = false;
    _devices.clear();
    _activeDeviceId = null;
    await load();
  }

  Future<void> _readFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    _activeDeviceId = prefs.getString(_activeKey);
    _devices.clear();
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = (jsonDecode(raw) as List<dynamic>)
            .whereType<Map>()
            .map((e) => SoundPolaDevice.fromJson(Map<String, dynamic>.from(e)))
            .where((d) => d.bindingStatus == DeviceBindingStatus.bound)
            .toList();
        _devices.addAll(list);
      } catch (_) {}
    }
    if (_activeDeviceId != null &&
        !_devices.any((d) => d.deviceId == _activeDeviceId)) {
      _activeDeviceId = _devices.isEmpty ? null : _devices.first.deviceId;
    } else if (_activeDeviceId == null && _devices.isNotEmpty) {
      _activeDeviceId = _devices.first.deviceId;
    }
  }

  Future<void> upsert(SoundPolaDevice device, {bool setActive = true}) async {
    await load();
    final i = _devices.indexWhere((d) => d.deviceId == device.deviceId);
    if (i >= 0) {
      _devices[i] = device;
    } else {
      _devices.add(device);
    }
    if (setActive) _activeDeviceId = device.deviceId;
    await _persist();
    notifyListeners();
  }

  Future<void> rename(String deviceId, String name) async {
    await load();
    final i = _devices.indexWhere((d) => d.deviceId == deviceId);
    if (i < 0) return;
    _devices[i] = _devices[i].copyWith(deviceName: name.trim());
    await _persist();
    notifyListeners();
  }

  Future<void> setActive(String deviceId) async {
    await load();
    if (!_devices.any((d) => d.deviceId == deviceId)) return;
    _activeDeviceId = deviceId;
    await _persist();
    notifyListeners();
  }

  /// Clears local binding credentials. Does not touch Drafts / Collection.
  Future<void> unbind(String deviceId) async {
    await load();
    _devices.removeWhere((d) => d.deviceId == deviceId);
    if (_activeDeviceId == deviceId) {
      _activeDeviceId = _devices.isEmpty ? null : _devices.first.deviceId;
    }
    await _persist();
    notifyListeners();
  }

  SoundPolaDevice? getById(String deviceId) {
    for (final d in _devices) {
      if (d.deviceId == deviceId) return d;
    }
    return null;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      jsonEncode(_devices.map((e) => e.toJson()).toList()),
    );
    if (_activeDeviceId == null) {
      await prefs.remove(_activeKey);
    } else {
      await prefs.setString(_activeKey, _activeDeviceId!);
    }
  }
}
