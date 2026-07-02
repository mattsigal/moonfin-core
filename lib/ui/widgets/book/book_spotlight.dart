import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import 'package:flutter/services.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../../util/platform_detection.dart';
import '../../mixins/focus_state_mixin.dart';
import '../navigation_layout.dart';
import 'book_glass.dart';

class BookSpotlight extends StatelessWidget {
  const BookSpotlight({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.onPrimary,
    this.imageUrl,
    this.progress,
    this.topInset = 0,
    this.focusNode,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final String ctaLabel;
  final VoidCallback onPrimary;
  final String? imageUrl;
  final double? progress;
  final double topInset;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final apple = PlatformDetection.isApple;
    final mobile = PlatformDetection.useMobileUi;
    final onSurface = AppColorScheme.onSurface;
    final background = AppColorScheme.background;
    final coverW = mobile ? 92.0 : 80.0;
    final coverH = coverW * 1.5;
    final height = (mobile ? 250.0 : 210.0) + topInset;

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
              child: CachedNetworkImage(
                imageUrl: imageUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => ColoredBox(color: background),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: 0.25),
                  background.withValues(alpha: 0.6),
                  background,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Cover(
                  imageUrl: imageUrl,
                  width: coverW,
                  height: coverH,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        eyebrow.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w600,
                          color: AppColorScheme.accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: mobile ? 20 : 22,
                          fontWeight: FontWeight.w600,
                          height: 1.08,
                          color: onSurface,
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                      const SizedBox(height: 11),
                      Row(
                        children: [
                          if (progress != null) ...[
                            _ProgressRing(value: progress!),
                            const SizedBox(width: 10),
                          ],
                          _ResumeButton(
                            apple: apple,
                            label: ctaLabel,
                            onTap: onPrimary,
                            focusNode: focusNode,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({
    required this.imageUrl,
    required this.width,
    required this.height,
  });

  final String? imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: AppRadius.circular(9),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: AppRadius.circular(9),
        child: SizedBox(
          width: width,
          height: height,
          child: imageUrl != null
              ? CachedNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.contain,
                  errorWidget: (_, _, _) => _placeholder(),
                )
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() => ColoredBox(
    color: AppColorScheme.surfaceVariant,
    child: Icon(
      Icons.menu_book,
      color: AppColorScheme.onSurface.withValues(alpha: 0.4),
      size: width * 0.3,
    ),
  );
}

class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final pct = (value.clamp(0.0, 1.0) * 100).round();
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: value.clamp(0.0, 1.0),
            strokeWidth: 3,
            backgroundColor: AppColorScheme.onSurface.withValues(alpha: 0.18),
            valueColor: AlwaysStoppedAnimation(AppColorScheme.accent),
          ),
          Text(
            '$pct',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _ResumeButton extends StatefulWidget {
  const _ResumeButton({
    required this.apple,
    required this.label,
    required this.onTap,
    this.focusNode,
  });

  final bool apple;
  final String label;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_ResumeButton> createState() => _ResumeButtonState();
}

class _ResumeButtonState extends State<_ResumeButton> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );

    final showLabel = showFocusBorder;
    final content = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: showLabel
          ? const EdgeInsets.symmetric(horizontal: 16, vertical: 9)
          : const EdgeInsets.all(9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            widget.apple ? CupertinoIcons.play_fill : Icons.play_arrow,
            size: 16,
            color: (widget.apple || showFocusBorder) ? AppColorScheme.onSurface : AppColorScheme.onAccent,
          ),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: (widget.apple || showFocusBorder) ? AppColorScheme.onSurface : AppColorScheme.onAccent,
              ),
            ),
          ],
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setFocused(f),
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent || event is KeyRepeatEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              final focusNavbar = NavigationLayout.focusNavbarNotifier.value;
              if (focusNavbar != null) {
                focusNavbar();
                return KeyEventResult.handled;
              }
            }
          }
          if (isActivateKey(event)) {
            widget.onTap();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              color: showFocusBorder
                  ? AppColorScheme.onSurface.withValues(alpha: 0.1)
                  : (widget.apple ? Colors.transparent : AppColorScheme.accent),
              borderRadius: AppRadius.circular(22),
              border: showFocusBorder
                  ? Border.all(color: focusColor, width: 2.0)
                  : Border.all(color: Colors.transparent, width: 2.0),
            ),
            child: widget.apple && !showFocusBorder
                ? bookGlassOrSolid(
                    cornerRadius: 22,
                    blur: 18,
                    tint: AppColorScheme.accent.withValues(alpha: 0.30),
                    fallbackColor: AppColorScheme.accent,
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}
