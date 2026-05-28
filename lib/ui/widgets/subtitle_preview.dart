import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../preference/user_preferences.dart';
import '../../l10n/app_localizations.dart';

/// Live preview of subtitle styling that reacts to preference changes.
class SubtitlePreview extends StatefulWidget {
  const SubtitlePreview({super.key});

  @override
  State<SubtitlePreview> createState() => _SubtitlePreviewState();
}

class _SubtitlePreviewState extends State<SubtitlePreview> {
  final UserPreferences _prefs = GetIt.instance<UserPreferences>();

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Color(_prefs.get(UserPreferences.subtitlesTextColor));
    final bgColor = Color(_prefs.get(UserPreferences.subtitlesBackgroundColor));
    final strokeColor =
        Color(_prefs.get(UserPreferences.subtitleTextStrokeColor));
    final displaySize = _prefs.get(UserPreferences.subtitlesTextSize) * 1.3;
    final fontWeight = _prefs.get(UserPreferences.subtitlesTextWeight);

    return Container(
      height: 140,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColorScheme.surfaceVariant,
            AppColorScheme.scrim,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        AppLocalizations.of(context).subtitlePreviewText,
        textAlign: TextAlign.center,
        style: TextStyle(
          inherit: false,
          height: 1.4,
          fontSize: displaySize,
          color: textColor,
          backgroundColor: bgColor,
          fontFamilyFallback: const ['Roboto', 'Noto Sans', 'Arial'],
          fontWeight: fontWeight >= 700 ? FontWeight.bold : FontWeight.normal,
          shadows: subtitleStrokeShadows(strokeColor, displaySize),
        ),
      ),
    );
  }
}

/// 8-direction scaled shadow ring approximating a text stroke. Width scales
/// with [fontSize] so the outline stays visible at large sizes and extends
/// past any [TextStyle.backgroundColor] rectangle behind the glyph.
List<Shadow>? subtitleStrokeShadows(Color strokeColor, double fontSize) {
  if (strokeColor.a <= 0) return null;
  final w = (fontSize / 16.0).clamp(1.0, 3.0);
  return <Shadow>[
    Shadow(offset: Offset(-w, -w), color: strokeColor),
    Shadow(offset: Offset(0, -w), color: strokeColor),
    Shadow(offset: Offset(w, -w), color: strokeColor),
    Shadow(offset: Offset(-w, 0), color: strokeColor),
    Shadow(offset: Offset(w, 0), color: strokeColor),
    Shadow(offset: Offset(-w, w), color: strokeColor),
    Shadow(offset: Offset(0, w), color: strokeColor),
    Shadow(offset: Offset(w, w), color: strokeColor),
  ];
}
