// notification_service.dart
import 'package:flutter/material.dart'; // Needed for TargetPlatform, Theme
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Optional: Callback for handling notification taps
  final Future<void> Function(NotificationResponse)? onNotificationTap;

  NotificationService({this.onNotificationTap});

  // --- Initialize Local Notifications ---
  Future<void> init(BuildContext context) async { // Pass context for permission request
    // Android Initialization Settings
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_launcher'); // Use your app icon name

    // iOS Initialization Settings
    const DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Initialize the plugin
    try {
      await _flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onNotificationTap ??
            (NotificationResponse notificationResponse) async {
              print('Notification tapped (default handler): ${notificationResponse.payload}');
              // Optional: Add default tap handling if needed
            },
      );
      print("Notification Plugin Initialized by Service");

      // Request Android 13+ permission if needed
      // This ideally runs after the first frame when context is fully available
      WidgetsBinding.instance.addPostFrameCallback((_) async {
         if (Theme.of(context).platform == TargetPlatform.android) {
             final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
                 _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                         AndroidFlutterLocalNotificationsPlugin>();
             final bool? granted = await androidImplementation?.requestNotificationsPermission();
             print("Android Notification Permission Granted via Service: $granted");
         }
      });

    } catch (e) {
      print("Error initializing notifications via Service: $e");
      // Consider re-throwing or using a result type if initialization failure needs handling
    }
  }

  // --- Show Low Dose Notification ---
  Future<void> showLowDoseNotification(int currentDose, int maxDose) async {
     if (maxDose <= 0) {
         print("Cannot show low dose notification: Max dose is not positive.");
         return;
     }
     if (currentDose < 0) {
         print("Cannot show low dose notification: Current dose is negative.");
         // Optionally show a different notification for invalid state?
         return;
     }

    // Android Notification Details
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'low_dose_channel', // Channel ID
      'Low Dose Alerts', // Channel Name
      channelDescription: 'Notifications for low inhaler dose count',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'Low Dose Alert',
      playSound: true,
      enableVibration: true,
    );

    // iOS Notification Details
    const DarwinNotificationDetails darwinNotificationDetails =
        DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    // Combined Notification Details
    const NotificationDetails notificationDetails = NotificationDetails(
        android: androidNotificationDetails, iOS: darwinNotificationDetails);

    // Show the notification
    try {
      await _flutterLocalNotificationsPlugin.show(
        0, // Notification ID (use a consistent ID for updates/cancellation)
        'Low Inhaler Dose', // Title
        'Only $currentDose doses remaining (out of $maxDose). Please refill soon.', // Body
        notificationDetails,
        // payload: 'low_dose_alert' // Optional payload for tap handling
      );
      print("Low dose notification shown by Service.");
    } catch (e) {
      print("Error showing notification via Service: $e");
    }
  }

  // --- Optional: Method to cancel notifications ---
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
    print("Cancelled notification with ID: $id");
  }

  Future<void> cancelAllNotifications() async {
    await _flutterLocalNotificationsPlugin.cancelAll();
     print("Cancelled all notifications.");
  }
}