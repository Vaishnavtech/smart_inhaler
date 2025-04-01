import 'package:flutter/material.dart';

// --- Constants (Make sure these are consistent or passed from screen1.dart) ---
const Color _buzzerButtonColor = Color(0xFFFFAB91); // Warm Coral
const double _cardCornerRadius = 12.0;
const double _cardElevation = 4.0;

class BuzzerControl extends StatefulWidget {
  final int buzzerControl;
  final VoidCallback onToggle;

  const BuzzerControl({
    Key? key,
    required this.buzzerControl,
    required this.onToggle,
  }) : super(key: key);

  @override
  _BuzzerControlState createState() => _BuzzerControlState();
}

class _BuzzerControlState extends State<BuzzerControl>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation; // For button press effect

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500), // Slower pulse
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );

    if (widget.buzzerControl != 0) {
      _animationController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant BuzzerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.buzzerControl != oldWidget.buzzerControl) {
      if (widget.buzzerControl != 0) {
        if (!_animationController.isAnimating) {
          _animationController.repeat(reverse: true);
        }
      } else {
        _animationController.stop();
        _animationController.reset(); // Reset to normal state when off
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    _animationController.forward(); // Start press animation
  }

  void _handleTapUp(TapUpDetails details) {
    _animationController.reverse(); // Reverse press animation
    widget.onToggle(); // Trigger the actual toggle
  }

  void _handleTapCancel() {
    _animationController.reverse(); // Reverse press animation if tap is cancelled
  }

  @override
  Widget build(BuildContext context) {
    bool isActive = widget.buzzerControl != 0;

    return GestureDetector(
      // Use GestureDetector for tap effects
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: () {/* onTap handled by Up/Down/Cancel */},
      // Keep onTap empty or remove
      child: ScaleTransition(
        // Apply scale animation
        scale: _scaleAnimation,
        child: Card(
          elevation: _cardElevation,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_cardCornerRadius),
          ),
          color: isActive
              ? _buzzerButtonColor.withOpacity(0.8)
              : _buzzerButtonColor, // Slightly dim when active?
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Use a pulsing icon effect when active
                isActive
                    ? FadeTransition(
                        opacity: _animationController,
                        child: const Icon(Icons.notifications_active,
                            color: Colors.white, size: 32.0),
                      )
                    : const Icon(Icons.notifications_off_outlined,
                        color: Colors.white70,
                        size:
                            32.0), // Different icon when off
                const SizedBox(width: 12),
                Text(
                  isActive ? 'Buzzer Active' : 'Activate Buzzer',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}