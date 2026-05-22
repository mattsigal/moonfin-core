import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:media_kit/media_kit.dart';
import 'package:playback_core/playback_core.dart';
import 'package:web/web.dart' as web;
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'data/services/cast/airplay_command_bridge.dart';
import 'data/services/download_notification_service.dart';
import 'data/services/media_server_client_factory.dart';
import 'di/injection.dart';
import 'playback/audio_handler.dart';
import 'playback/playback_lifecycle_handler.dart';
import 'preference/user_preferences.dart';
import 'util/platform_detection.dart';

const _forceTv = bool.fromEnvironment('FORCE_TV', defaultValue: false);

void _configureImageCache() {
  final imageCache = PaintingBinding.instance.imageCache;
  if (PlatformDetection.isWeb) {
    imageCache.maximumSize = 200;
    imageCache.maximumSizeBytes = 96 << 20;
    return;
  }
  if (PlatformDetection.isMobile) {
    imageCache.maximumSize = 100;
    imageCache.maximumSizeBytes = 120 << 20;
    return;
  }

  imageCache.maximumSize = 200;
  imageCache.maximumSizeBytes = 256 << 20;
}

Future<void> _restoreWindowGeometry() async {
  final prefs = GetIt.instance<UserPreferences>();
  final w = prefs.get(UserPreferences.windowWidth);
  final h = prefs.get(UserPreferences.windowHeight);
  final x = prefs.get(UserPreferences.windowX);
  final y = prefs.get(UserPreferences.windowY);

  const minW = 800.0;
  const minH = 500.0;
  final hasSavedGeometry = w >= minW && h >= minH;

  final options = WindowOptions(
    size: hasSavedGeometry ? Size(w, h) : const Size(1280, 720),
    minimumSize: const Size(minW, minH),
    center: !hasSavedGeometry,
    skipTaskbar: false,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    if (hasSavedGeometry) {
      await windowManager.setPosition(Offset(x, y));
    }
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> _detectAndSetTvMode() async {
  if (kIsWeb) {
    if (_forceTv) {
      PlatformDetection.setTvMode(true);
      print('[Moonfin] TV mode forced via compile-time dart-define');
      return;
    }

    final ua = web.window.navigator.userAgent.toLowerCase();
    final query = Uri.base.queryParameters;
    final forceTvFromQuery =
        query['tv'] == '1' ||
        query['tv'] == 'true' ||
        query['force_tv'] == '1' ||
        query['force_tv'] == 'true';
    var forcedWebOsFlag = false;
    var hasWebOsRuntime = false;
    try {
      final dynamic win = web.window;
      forcedWebOsFlag = win.__MOONFIN_WEBOS__ == true;
      hasWebOsRuntime = win.PalmSystem != null || win.webOSSystem != null;
    } catch (_) {}

    final isWebOsTv =
        forceTvFromQuery ||
        forcedWebOsFlag ||
        hasWebOsRuntime ||
        ua.contains('webos') ||
        ua.contains('web0s') ||
        (ua.contains('smarttv') && ua.contains('lg'));

    PlatformDetection.setTvMode(isWebOsTv);
    print(
      'Moonfin web TV detection: isTV=$isWebOsTv, '
      'queryForce=$forceTvFromQuery, forced=$forcedWebOsFlag, '
      'runtime=$hasWebOsRuntime, ua="$ua"',
    );
    return;
  }
  if (!PlatformDetection.isAndroid) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    final isTV = await channel.invokeMethod<bool>('isTvDevice') ?? false;
    PlatformDetection.setTvMode(isTV);
  } catch (_) {}
}

Future<void> _detectAndSetDisplayCapabilities() async {
  if (!(PlatformDetection.isAndroid && PlatformDetection.isTV)) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    final hdrTypes = await channel.invokeMethod<List<dynamic>>('displayHdrTypes');
    PlatformDetection.setDisplayHdrTypes(
      hdrTypes?.map((value) => value.toString()),
    );

    final codecCaps = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'mediaCodecCapabilities',
    );
    if (codecCaps != null) {
      PlatformDetection.setMediaCodecCapabilities(
        codecCaps.map((key, value) => MapEntry(key.toString(), value)),
      );
      return;
    }

    final legacyDvCaps = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'dolbyVisionCodecCapabilities',
    );
    PlatformDetection.setDolbyVisionCodecCapabilities(
      legacyDvCaps?.map(
        (key, value) => MapEntry(key.toString(), value == true),
      ),
    );
  } catch (_) {}
}

Future<void> _detectAndApplyAudioCapabilities(UserPreferences prefs) async {
  if (!(PlatformDetection.isAndroid && PlatformDetection.isTV)) return;
  try {
    const channel = MethodChannel('org.moonfin.androidtv/platform');
    final audioCaps = await channel.invokeMethod<Map<dynamic, dynamic>>(
      'audioCapabilities',
    );
    if (audioCaps == null) {
      PlatformDetection.setAudioCapabilities(null);
      return;
    }

    PlatformDetection.setAudioCapabilities(
      audioCaps.map((key, value) => MapEntry(key.toString(), value)),
    );

    final hasAutoDetected = prefs.get(UserPreferences.audioPrefsAutoDetected);
    if (hasAutoDetected) return;

    final supportsAc3 = PlatformDetection.supportsAc3Audio;
    final supportsTrueHd = PlatformDetection.supportsTrueHdAudio;
    final supportsDts = PlatformDetection.supportsDtsAudio;

    if (prefs.get(UserPreferences.ac3Enabled) != supportsAc3) {
      await prefs.set(UserPreferences.ac3Enabled, supportsAc3);
    }
    if (prefs.get(UserPreferences.trueHdEnabled) != supportsTrueHd) {
      await prefs.set(UserPreferences.trueHdEnabled, supportsTrueHd);
    }
    if (prefs.get(UserPreferences.dtsEnabled) != supportsDts) {
      await prefs.set(UserPreferences.dtsEnabled, supportsDts);
    }

    await prefs.set(UserPreferences.audioPrefsAutoDetected, true);
  } catch (_) {}
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (PlatformDetection.isDesktop) {
    await windowManager.ensureInitialized();
  }

  _configureImageCache();
  MediaKit.ensureInitialized();

  await _detectAndSetTvMode();
  await _detectAndSetDisplayCapabilities();

  // On Linux the GTK font pipeline loads fonts asynchronously. The first frame
  // can render before MaterialIcons and other fonts are ready, causing icons to
  // appear blank. Pumping a warm-up frame gives the font loader time to finish.
  // The issue is intermittent and goes away on re-run once the OS font cache
  // is warm, which confirms the timing root cause.
  if (PlatformDetection.isLinux) {
    WidgetsBinding.instance.scheduleWarmUpFrame();
  }

  if (PlatformDetection.isMobile) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
  }

  await configureDependencies();

  final prefs = GetIt.instance<UserPreferences>();
  await _detectAndApplyAudioCapabilities(prefs);

  if (PlatformDetection.isDesktop) {
    await _restoreWindowGeometry();
  }

  final notificationService = GetIt.instance<DownloadNotificationService>();
  try {
    await notificationService.initialize();
  } catch (_) {}

  if (PlatformDetection.isMobile) {
    try {
      await initAudioService(
        manager: GetIt.instance<PlaybackManager>(),
        clientFactory: GetIt.instance<MediaServerClientFactory>(),
      );
    } catch (_) {}
  }

  try {
    final session = await AudioSession.instance;
    final iosCategoryOptions =
        AVAudioSessionCategoryOptions.allowAirPlay |
        AVAudioSessionCategoryOptions.allowBluetooth |
        AVAudioSessionCategoryOptions.allowBluetoothA2dp;
    await session.configure(AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: iosCategoryOptions,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
    ));
    await session.setActive(true);
  } catch (_) {}

  if (!GetIt.instance.isRegistered<PlaybackLifecycleHandler>()) {
    GetIt.instance.registerSingleton<PlaybackLifecycleHandler>(
      PlaybackLifecycleHandler(GetIt.instance<PlaybackManager>()),
    );
  }

  try {
    GetIt.instance<AirPlayCommandBridge>().start();
  } catch (_) {}

  runApp(const MoonfinApp());
}
