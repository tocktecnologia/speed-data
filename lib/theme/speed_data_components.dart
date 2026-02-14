import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'speed_data_theme.dart';

// -----------------------------------------------------------------------------
// Buttons
// -----------------------------------------------------------------------------

class SpeedButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final Widget? icon;
  final bool isLoading;
  final ButtonType type;
  final bool fullWidth;

  const SpeedButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.type = ButtonType.primary,
    this.fullWidth = false,
  });

  const SpeedButton.primary({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  }) : type = ButtonType.primary;

  const SpeedButton.secondary({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  }) : type = ButtonType.secondary;

  const SpeedButton.ghost({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  }) : type = ButtonType.ghost;

  const SpeedButton.danger({
    super.key,
    required this.text,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = false,
  }) : type = ButtonType.danger;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 48,
        width: 48,
        child: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: SpeedDataTheme.accentPrimary),
        ),
      );
    }

    Widget buttonContent = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[icon!, const SizedBox(width: 8)],
        Text(text),
      ],
    );

    Widget button;
    switch (type) {
      case ButtonType.primary:
        button = ElevatedButton(
          onPressed: onPressed,
          child: buttonContent,
        );
        break;
      case ButtonType.secondary:
        button = OutlinedButton(
          onPressed: onPressed,
          child: buttonContent,
        );
        break;
      case ButtonType.ghost:
        button = TextButton(
          onPressed: onPressed,
          child: buttonContent,
        );
        break;
      case ButtonType.danger:
        button = ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: SpeedDataTheme.flagRed,
            foregroundColor: Colors.white,
          ),
          child: buttonContent,
        );
        break;
    }

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

enum ButtonType { primary, secondary, ghost, danger }

// -----------------------------------------------------------------------------
// Cards
// -----------------------------------------------------------------------------

class SpeedCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final bool selected;

  const SpeedCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.selected = false,
  });

  @override
  State<SpeedCard> createState() => _SpeedCardState();
}

class _SpeedCardState extends State<SpeedCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.selected
        ? SpeedDataTheme.accentPrimaryMuted
        : (_isHovered ? SpeedDataTheme.bgElevated : SpeedDataTheme.bgSurface);
    
    final borderColor = widget.selected
        ? SpeedDataTheme.accentPrimary
        : SpeedDataTheme.borderSubtle;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd),
          child: Padding(
            padding: widget.padding,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Badges
// -----------------------------------------------------------------------------

class SpeedBadge extends StatelessWidget {
  final String label;
  final Color color;
  final bool outline;

  const SpeedBadge({
    super.key,
    required this.label,
    required this.color,
    this.outline = false,
  });

  const SpeedBadge.open({super.key})
      : label = 'OPEN',
        color = SpeedDataTheme.flagGreen,
        outline = false;

  const SpeedBadge.live({super.key})
      : label = 'LIVE',
        color = SpeedDataTheme.flagGreen,
        outline = false;

  const SpeedBadge.finished({super.key})
      : label = 'FINISHED',
        color = SpeedDataTheme.textSecondary,
        outline = false;

  const SpeedBadge.redFlag({super.key})
      : label = 'RED FLAG',
        color = SpeedDataTheme.flagRed,
        outline = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outline ? Colors.transparent : color.withOpacity(0.15),
        border: outline ? Border.all(color: color) : null,
        borderRadius: BorderRadius.circular(SpeedDataTheme.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
           if (label == 'LIVE') ...[
             _PulsingDot(color: color),
             const SizedBox(width: 6),
           ],
          Text(
            label,
            style: SpeedDataTheme.themeData.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1, milliseconds: 500),
    )..repeat();

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.4).animate(_controller);
    _opacityAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(_opacityAnimation.value),
          ),
          child: Center(
            child: Container(
              width: 8 / _scaleAnimation.value,
              height: 8 / _scaleAnimation.value,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
              ),
            ),
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Flag Buttons (Race Control)
// -----------------------------------------------------------------------------

class SpeedFlagButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final bool active;

  const SpeedFlagButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      // decoration: active ? BoxDecoration(boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]) : null,
      child: ElevatedButton(
        onPressed: () {
          HapticFeedback.mediumImpact();
          onPressed();
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          minimumSize: const Size(80, 80),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(SpeedDataTheme.radiusMd)),
          elevation: active ? 8 : 2,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
