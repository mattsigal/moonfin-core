import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../../widgets/adaptive/adaptive_glass.dart';
import '../../../../widgets/focus/focusable_wrapper.dart';

/// Glass "Up Next" card: a small label badge on top, then a thumbnail with a
/// play overlay on the left and the episode title + short description on the
/// right, with a progress bar and remaining time pinned to the bottom. Purely
/// presentational and theme-tokenized.
class UpNextCard extends StatelessWidget {
  final String label;
  final String title;
  final String? description;
  final String? imageUrl;
  final double progress; // 0..1
  final String? remainingLabel;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateDown;
  final double width;

  const UpNextCard({
    super.key,
    required this.label,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.progress,
    required this.remainingLabel,
    required this.onTap,
    this.focusNode,
    this.onNavigateLeft,
    this.onNavigateDown,
    this.width = double.infinity,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final radius = JellyfinTokens.shapes.mediumRadius;
    final muted = AppColorScheme.onSurface.withValues(alpha: 0.7);
    return FocusableWrapper(
      focusNode: focusNode,
      onSelect: onTap,
      onNavigateLeft: onNavigateLeft,
      onNavigateDown: onNavigateDown,
      borderRadius: radius.topLeft.x,
      suppressFocusGlow: true,
      focusColor: const Color(0xFF00F0FF),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius.topLeft.x),
              border: Border.all(
                color: ThemeRegistry.active.id == ThemeRegistry.neonPulseId
                    ? const Color(0xFF00F0FF)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1.25,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius.topLeft.x - 1.25),
              child: adaptiveGlass(
                cornerRadius: radius.topLeft.x - 1.25,
                blur: 18,
                fallbackColor: AppColorScheme.surface.withValues(alpha: 0.42),
                tint: AppColorScheme.surface.withValues(alpha: 0.22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    label,
                    style: textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _thumbnail(),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.titleMedium,
                              ),
                              if (description != null &&
                                  description!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  description!,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall
                                      ?.copyWith(color: muted),
                                ),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  if (progress > 0)
                                    Expanded(
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(2),
                                        child: LinearProgressIndicator(
                                          value: progress.clamp(0.0, 1.0),
                                          minHeight: 4,
                                          backgroundColor: AppColorScheme
                                              .onSurface
                                              .withValues(alpha: 0.20),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                  AppColorScheme.accent),
                                        ),
                                      ),
                                    )
                                  else
                                    const Spacer(),
                                  if (remainingLabel != null) ...[
                                    const SizedBox(width: 12),
                                    Text(
                                      remainingLabel!,
                                      style: textTheme.labelSmall
                                          ?.copyWith(color: muted),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
}

  Widget _thumbnail() {
    return SizedBox(
      width: 150,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl != null && imageUrl!.isNotEmpty)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const SizedBox.shrink(),
            )
          else
            ColoredBox(
              color: AppColorScheme.surface.withValues(alpha: 0.6),
            ),
          Center(
            child: Icon(
              Icons.play_circle_outline,
              size: 40,
              color: AppColorScheme.onSurface.withValues(alpha: 0.95),
            ),
          ),
        ],
      ),
    );
  }
}
