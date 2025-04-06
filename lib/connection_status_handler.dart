// connection_status_handler.dart
import 'package:flutter/material.dart';

/// A widget that displays different UI based on initialization and connection status.
///
/// Shows a loading indicator during initialization, an offline message when disconnected,
/// and the main content [child] when connected.
class ConnectionStatusHandler extends StatelessWidget {
  final bool isInitializing;
  final bool isConnected;
  final VoidCallback onRetry;
  final Widget child; // The main content to show when connected

  const ConnectionStatusHandler({
    Key? key,
    required this.isInitializing,
    required this.isConnected,
    required this.onRetry,
    required this.child,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isInitializing) {
      // --- Loading State ---
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting to Inhaler...'),
          ],
        ),
      );
    } else if (!isConnected) {
      // --- Offline State ---
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 60, color: Colors.red[300]),
              const SizedBox(height: 16),
              const Text(
                'Inhaler Offline',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Check device connection and internet access. Data shown may be outdated.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 25),
              ElevatedButton.icon(
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                onPressed: onRetry, // Use the passed callback
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              )
            ],
          ),
        ),
      );
    } else {
      // --- Connected State ---
      // Display the main content passed via the 'child' parameter
      return child;
    }
  }
}


/// A reusable widget for the connection status indicator in the AppBar.
class ConnectionStatusIndicator extends StatelessWidget {
  final bool isConnected;

  const ConnectionStatusIndicator({
    Key? key,
    required this.isConnected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
     final Color indicatorColor = isConnected ? Colors.green[100]! : Colors.red[100]!;
     final Color borderColor = isConnected ? Colors.green[300]! : Colors.red[300]!;
     final Color iconTextColor = isConnected ? Colors.green[800]! : Colors.red[800]!;
     final IconData iconData = isConnected ? Icons.wifi : Icons.wifi_off;
     final String statusText = isConnected ? 'Online' : 'Offline';
     final String tooltipMessage = isConnected ? 'Connected to Firebase' : 'Disconnected from Firebase';

    return Padding(
      padding: const EdgeInsets.only(right: 16.0),
      child: Center(
        child: Tooltip(
          message: tooltipMessage,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: indicatorColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 0.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(iconData, color: iconTextColor, size: 16),
                const SizedBox(width: 4),
                Text(
                  statusText,
                  style: TextStyle(
                    color: iconTextColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
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