import 'package:flutter/material.dart';

// --- Constants (Specific to DoseCounter or shared via theme/constants file later) ---
// Define textColor here if it's primarily for this widget,
// or consider moving shared constants to a separate file.
const Color _textColor = Color(0xFF212121);

// --- Dose Counter Widget ---
class DoseCounter extends StatefulWidget {
  final int doseCount;
  final int maxDoseCount;
  final VoidCallback onEdit;

  const DoseCounter({
    Key? key,
    required this.doseCount,
    required this.maxDoseCount,
    required this.onEdit,
  }) : super(key: key);

  @override
  _DoseCounterState createState() => _DoseCounterState();
}

class _DoseCounterState extends State<DoseCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant DoseCounter oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Trigger animation when dose count decreases (typically when a dose is taken)
    if (widget.doseCount < oldWidget.doseCount) {
      // Reset and play animation if not already running forward
      if (_animationController.status != AnimationStatus.forward) {
         _animationController.reset();
         _animationController.forward();
      }
    }
     // Optional: Animate back down if count increases (e.g., manual edit)
     else if (widget.doseCount > oldWidget.doseCount) {
        // You could add a reverse animation here if desired
     }
  }


  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Color _getProgressColor(double progress) {
    if (progress > 0.6) {
      return Colors.cyan; // Plenty of doses left
    } else if (progress > 0.3) {
      return Colors.orange; // Getting low
    } else if (progress <= 0.0) { // Handle zero explicitly if needed
      return Colors.red.shade900; // Darker red for empty
    }
    else {
      return Colors.red; // Very low, needs replacement
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ensure maxDoseCount is not zero to avoid division by zero
    double progress = (widget.maxDoseCount > 0)
        ? widget.doseCount / widget.maxDoseCount
        : 0.0;
    // Clamp progress between 0.0 and 1.0
    progress = progress.clamp(0.0, 1.0);


    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          const Text(
            'Doses Remaining',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w500,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: widget.onEdit,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer progress circle
                SizedBox(
                  width: 230,
                  height: 230,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 25,
                    backgroundColor: Colors.grey.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        _getProgressColor(progress)),
                  ),
                ),
                // Inner circle with radial gradient and white numbers
                ScaleTransition(
                  scale: _animation,
                  child: Container(
                    width: 205, // Slightly smaller than progress indicator
                    height: 205,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.blue,
                          Color(0xFF00008B), // Dark Blue
                        ],
                        center: Alignment.center,
                        radius: 0.7,
                      ),
                       boxShadow: [ // Optional: Add a subtle shadow for depth
                         BoxShadow(
                           color: Colors.black26,
                           blurRadius: 5.0,
                           offset: Offset(0, 2),
                         )
                       ]
                    ),
                    child: Center(
                      child: Text(
                        '${widget.doseCount}',
                        style: const TextStyle(
                          fontSize: 60,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // White text color
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap number to edit', // More specific hint
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}