import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:web/web.dart' as web;

import 'platform_detection.dart';

class AppExit {
  static const MethodChannel _platformChannel = MethodChannel(
    'org.moonfin.androidtv/platform',
  );

  static Future<void> closeApp() async {
    if (kIsWeb) {
      try {
        web.window.close();
      } catch (_) {}
      return;
    }

    if (PlatformDetection.isAndroid) {
      try {
        final handled =
            await _platformChannel.invokeMethod<bool>('exitApp') ?? false;
        if (handled) return;
      } catch (e, st) {
        debugPrint('[AppExit] Android platform channel error: $e\n$st');
      }
    }

    if (PlatformDetection.isDesktop) {
      try {
        await windowManager.close();
        return;
      } catch (_) {}
    }

    await SystemNavigator.pop();
  }
}
