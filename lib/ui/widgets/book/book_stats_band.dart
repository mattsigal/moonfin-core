import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../mixins/focus_state_mixin.dart';
import '../adaptive/adaptive_glass.dart';

class BookStat {
  final String label;
  final int count;
  final VoidCallback? onTap;

  const BookStat({
    required this.label,
    required this.count,
    this.onTap,
  });
}

class BookStatsBand extends StatelessWidget {
  const BookStatsBand({
    super.key,
    required this.stats,
    this.booksFocusNode,
    this.audiobooksFocusNode,
    this.onBooksUpPressed,
    this.onAudiobooksUpPressed,
    this.onBooksDownPressed,
    this.onAudiobooksDownPressed,
  });

  final List<BookStat> stats;
  final FocusNode? booksFocusNode;
  final FocusNode? audiobooksFocusNode;
  final VoidCallback? onBooksUpPressed;
  final VoidCallback? onAudiobooksUpPressed;
  final VoidCallback? onBooksDownPressed;
  final VoidCallback? onAudiobooksDownPressed;

  @override
  Widget build(BuildContext context) {
    final visible = stats.where((s) => s.count > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: _BookStatCard(
                stat: visible[i],
                focusNode: i == 0
                    ? booksFocusNode
                    : (i == 1 ? audiobooksFocusNode : null),
                onUpPressed: i == 0 ? onBooksUpPressed : onAudiobooksUpPressed,
                onDownPressed: i == 0 ? onBooksDownPressed : onAudiobooksDownPressed,
                onLeftPressed: (i == 1 && visible.length > 1)
                    ? () => booksFocusNode?.requestFocus()
                    : null,
                onRightPressed: (i == 0 && visible.length > 1)
                    ? () => audiobooksFocusNode?.requestFocus()
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BookStatCard extends StatefulWidget {
  final BookStat stat;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final VoidCallback? onLeftPressed;
  final VoidCallback? onRightPressed;

  const _BookStatCard({
    required this.stat,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
    this.onLeftPressed,
    this.onRightPressed,
  });

  @override
  State<_BookStatCard> createState() => _BookStatCardState();
}

class _BookStatCardState extends State<_BookStatCard> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final onSurface = AppColorScheme.onSurface;
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );

    Widget cardContent = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${widget.stat.count}',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            widget.stat.label.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.6,
              color: onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );

    if (widget.stat.onTap == null) {
      return adaptiveGlass(
        cornerRadius: 12,
        fallbackColor: onSurface.withValues(alpha: 0.06),
        child: cardContent,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setFocused(f),
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.stat.onTap!();
            return KeyEventResult.handled;
          }
          if (event.isActionable) {
            if (event.logicalKey.isUpKey && widget.onUpPressed != null) {
              widget.onUpPressed!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey.isDownKey && widget.onDownPressed != null) {
              widget.onDownPressed!();
              return KeyEventResult.handled;
            }
            if (event.logicalKey.isLeftKey) {
              if (widget.onLeftPressed != null) {
                widget.onLeftPressed!();
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey.isRightKey) {
              if (widget.onRightPressed != null) {
                widget.onRightPressed!();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: widget.stat.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: showFocusBorder
                  ? Border.all(color: focusColor, width: 2.0)
                  : Border.all(color: Colors.transparent, width: 2.0),
            ),
            child: adaptiveGlass(
              cornerRadius: 12,
              fallbackColor: showFocusBorder
                  ? onSurface.withValues(alpha: 0.15)
                  : onSurface.withValues(alpha: 0.06),
              child: cardContent,
            ),
          ),
        ),
      ),
    );
  }
}
