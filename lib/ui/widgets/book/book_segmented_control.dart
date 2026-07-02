import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../preference/user_preferences.dart';
import '../../../util/focus/dpad_keys.dart';
import '../../mixins/focus_state_mixin.dart';

class BookSegmentedControl extends StatelessWidget {
  const BookSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
    this.libraryFocusNode,
    this.discoverFocusNode,
    this.onLibraryDownPressed,
    this.onDiscoverDownPressed,
    this.onUpPressed,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final FocusNode? libraryFocusNode;
  final FocusNode? discoverFocusNode;
  final VoidCallback? onLibraryDownPressed;
  final VoidCallback? onDiscoverDownPressed;
  final VoidCallback? onUpPressed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: _SegmentTabButton(
            label: labels[0],
            selected: selectedIndex == 0,
            onTap: () => onChanged(0),
            focusNode: libraryFocusNode,
            onUpPressed: onUpPressed,
            onDownPressed: onLibraryDownPressed,
            onRightPressed: () => discoverFocusNode?.requestFocus(),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SegmentTabButton(
            label: labels[1],
            selected: selectedIndex == 1,
            onTap: () => onChanged(1),
            focusNode: discoverFocusNode,
            onUpPressed: onUpPressed,
            onDownPressed: onDiscoverDownPressed,
            onLeftPressed: () => libraryFocusNode?.requestFocus(),
          ),
        ),
      ],
    );
  }
}

class _SegmentTabButton extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final FocusNode? focusNode;
  final VoidCallback? onUpPressed;
  final VoidCallback? onDownPressed;
  final VoidCallback? onLeftPressed;
  final VoidCallback? onRightPressed;

  const _SegmentTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.focusNode,
    this.onUpPressed,
    this.onDownPressed,
    this.onLeftPressed,
    this.onRightPressed,
  });

  @override
  State<_SegmentTabButton> createState() => _SegmentTabButtonState();
}

class _SegmentTabButtonState extends State<_SegmentTabButton> with FocusStateMixin {
  @override
  Widget build(BuildContext context) {
    final focusColor = Color(
      GetIt.instance<UserPreferences>()
          .get(UserPreferences.focusColor)
          .colorValue,
    );
    final isNeon = ThemeRegistry.active.id == ThemeRegistry.neonPulseId;
    final accentColor = AppColorScheme.accent;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setHovered(true),
      onExit: (_) => setHovered(false),
      child: Focus(
        focusNode: widget.focusNode,
        onFocusChange: (f) => setFocused(f),
        onKeyEvent: (_, event) {
          if (isActivateKey(event)) {
            widget.onTap();
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
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: widget.selected
                  ? (isNeon ? accentColor.withValues(alpha: 0.15) : accentColor)
                  : AppColorScheme.onSurface.withValues(alpha: 0.08),
              border: Border.all(
                color: showFocusBorder
                    ? focusColor
                    : (widget.selected && isNeon ? AppColorScheme.onSurface : Colors.transparent),
                width: 2.0,
              ),
            ),
            child: Text(
              widget.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                color: widget.selected
                    ? (isNeon ? accentColor : AppColorScheme.onAccent)
                    : AppColorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
