import 'dart:async';

import 'package:wakelock_plus/wakelock_plus.dart';

class ScreensaverController {
  ScreensaverController() {
    _refreshWakeLock();
  }

  bool _activityPaused = false;
  bool _playbackActive = false;
  bool _wakeLockEnabled = false;

  bool get activityPaused => _activityPaused;

  set activityPaused(bool value) {
    if (_activityPaused == value) return;
    _activityPaused = value;
    _refreshWakeLock();
  }

  void setPlaybackActive(bool value) {
    if (_playbackActive == value) return;
    _playbackActive = value;
    _refreshWakeLock();
  }

  Future<void> _setWakeLockEnabled(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _refreshWakeLock() {
    final shouldEnable = !_activityPaused && _playbackActive;
    if (_wakeLockEnabled == shouldEnable) {
      return;
    }
    _wakeLockEnabled = shouldEnable;
    unawaited(_setWakeLockEnabled(shouldEnable));
  }

  void dispose() {
    _wakeLockEnabled = false;
    unawaited(_setWakeLockEnabled(false));
  }
}
