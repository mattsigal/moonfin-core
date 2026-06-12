import 'stream_resolution_result.dart';

abstract class MediaStreamResolver {
  static String extractItemId(dynamic mediaItem) {
    if (mediaItem is Map) return mediaItem['Id'] as String;
    return mediaItem.id as String;
  }

  static String applyStreamIndices(String url, int? audioStreamIndex, int? subtitleStreamIndex) {
    try {
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters);

      if (audioStreamIndex != null) {
        params['AudioStreamIndex'] = '$audioStreamIndex';
        params['audioStreamIndex'] = '$audioStreamIndex';
      }

      if (subtitleStreamIndex != null) {
        if (subtitleStreamIndex >= 0) {
          params['SubtitleStreamIndex'] = '$subtitleStreamIndex';
          params['subtitleStreamIndex'] = '$subtitleStreamIndex';
        } else if (subtitleStreamIndex == -1) {
          params.remove('SubtitleStreamIndex');
          params.remove('subtitleStreamIndex');
        }
      }

      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return url;
    }
  }

  static List<ExternalSubtitle> extractExternalSubtitles(
    List<Map<String, dynamic>> mediaStreams,
    String baseUrl,
  ) {
    final subs = <ExternalSubtitle>[];
    for (final stream in mediaStreams) {
      if (stream['Type'] != 'Subtitle') continue;
      final deliveryUrl = stream['DeliveryUrl'] as String?;
      if (deliveryUrl == null || deliveryUrl.isEmpty) continue;
      final isExternal = stream['IsExternal'] == true;
      final supportsExternal = stream['SupportsExternalStream'] == true;
      if (!isExternal && !supportsExternal) continue;
      subs.add(ExternalSubtitle(
        deliveryUrl: '$baseUrl$deliveryUrl',
        title: stream['DisplayTitle'] as String? ??
            stream['Title'] as String?,
        language: stream['Language'] as String?,
        codec: (stream['Codec'] as String?) ?? 'srt',
        isDefault: stream['IsDefault'] as bool? ?? false,
        isForced: stream['IsForced'] as bool? ?? false,
        streamIndex: stream['Index'] as int?,
      ));
    }
    return subs;
  }

  static String detectMediaType(
    List<Map<String, dynamic>> mediaStreams, {
    String fallbackUrl = '',
  }) {
    var hasVideo = false;
    var hasAudio = false;

    for (final stream in mediaStreams) {
      final type = stream['Type']?.toString().toUpperCase();
      if (type == 'VIDEO') {
        hasVideo = true;
      } else if (type == 'AUDIO') {
        hasAudio = true;
      }
      if (hasVideo && hasAudio) {
        break;
      }
    }

    if (hasVideo) {
      return 'video';
    }
    if (hasAudio) {
      return 'audio';
    }

    final uri = Uri.tryParse(fallbackUrl);
    final path = uri?.path.toLowerCase() ?? fallbackUrl.toLowerCase();
    const audioExtensions = <String>{
      '.mp3',
      '.flac',
      '.aac',
      '.m4a',
      '.ogg',
      '.opus',
      '.wav',
      '.alac',
      '.ape',
      '.wma',
    };
    for (final ext in audioExtensions) {
      if (path.endsWith(ext)) {
        return 'audio';
      }
    }

    return 'video';
  }

  static double? extractNormalizationGainDb(
    List<Map<String, dynamic>> mediaStreams,
  ) {
    for (final stream in mediaStreams) {
      if ((stream['Type']?.toString().toUpperCase() ?? '') != 'AUDIO') {
        continue;
      }

      for (final key in const <String>[
        'NormalizationGain',
        'normalizationGain',
        'ReplayGain',
        'replayGain',
        'TrackGain',
        'trackGain',
      ]) {
        final parsed = _parseGain(stream[key]);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  static double? _parseGain(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      final normalized = value.trim().replaceAll(
        RegExp(r'\s*dB\s*$', caseSensitive: false),
        '',
      );
      return double.tryParse(normalized);
    }
    return null;
  }

  Future<StreamResolutionResult> resolve(
    dynamic mediaItem, {
    Map<String, dynamic>? deviceProfile,
    int? maxStreamingBitrate,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    int? startTimeTicks,
    String? mediaSourceId,
    bool enableDirectPlay = true,
    bool enableDirectStream = true,
    bool enableTranscoding = true,
  });
}
