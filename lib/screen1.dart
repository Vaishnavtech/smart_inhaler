//screen1.dart (or your main screen file name)
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // <-- IMPORT NOTIFICATION PLUGIN

// Import the separated widgets and other screens
// --- Ensure these files exist and contain the necessary widgets ---
import 'dose_counter.dart';     // Import definition for DoseCounter
import 'graphscreen.dart';      // Assume this is your graphs screen
import 'test.dart';            // Assume this is FirebaseDataScreen2 (adjust name if needed)
import 'buzzer_control.dart';    // Import definition for BuzzerControl


// --- Constants ---
const Color _textColor = Color(0xFF212121);

// --- Main Dashboard Screen Widget ---
class InhalerDashboardScreen1 extends StatefulWidget {
  const InhalerDashboardScreen1({Key? key}) : super(key: key);

  @override
  _InhalerDashboardScreen1State createState() => _InhalerDashboardScreen1State();
}

class _InhalerDashboardScreen1State extends State<InhalerDashboardScreen1> {
  late DatabaseReference _dbRef;
  StreamSubscription<DatabaseEvent>? _subscription;
  bool _isConnected = false;
  bool _isInitializing = true;

  // Variables for dose tracking
  int _doseCount = 90; // Initial value, will be updated from Firebase
  int _maxDoseCount = 200; // Initial value, will be updated from Firebase

  // --- NEW State Variables for the Stats Grid ---
  int _correctCount = 0; // Default, updated from Firebase Counts/correctCount
  int _falseCount = 0;   // Default, updated from Firebase Counts/falseCount
  int _dailyDosesTaken = 0; // Default, needs Firebase field (e.g., Counts/dailyDosesTaken)
  final int _dailyDoseLimit = 5; // Hardcoded daily limit based on requirement
  // --- End NEW State Variables ---

  // Variables to store MPU6050 data
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 0.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;
  double _temp = 0.0;

  // Variables for FSR data
  int _fsrSensor1 = 0;
  int _fsrSensor2 = 0;
  int _fsrSensor3 = 0;

  // Buzzer control value
  int _buzzerControl = 0;

  bool _doseCounted = false;
  Timer? _doseCountResetTimer;
  Timer? _buzzerResetTimer;

  // --- Notification Setup ---
  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _lowDoseNotificationShown = false; // Track if notification was shown

  @override
  void initState() {
    super.initState();
    _initializeNotifications(); // Initialize notifications first
    _initializeDatabase();
  }

  // --- Initialize Local Notifications ---
  Future<void> _initializeNotifications() async {
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
          onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
              print('Notification tapped: ${notificationResponse.payload}');
              // Optional: Handle notification tap
          },
        );
        print("Notification Plugin Initialized");

        // Request Android 13+ permission if needed
         // Check if context is available before using Theme.of(context)
         // It's generally safer to request permission after the first frame
         WidgetsBinding.instance.addPostFrameCallback((_) async {
             if (mounted && Theme.of(context).platform == TargetPlatform.android) {
                 final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
                     _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                             AndroidFlutterLocalNotificationsPlugin>();
                 final bool? granted = await androidImplementation?.requestNotificationsPermission();
                 print("Android Notification Permission Granted: $granted");
             }
         });


    } catch(e) {
       print("Error initializing notifications: $e");
    }
  }

  // --- Show Low Dose Notification ---
  Future<void> _showLowDoseNotification(int currentDose, int maxDose) async {
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
        0, // Notification ID
        'Low Inhaler Dose', // Title
        'Only $currentDose doses remaining (out of $maxDose). Please refill soon.', // Body
        notificationDetails,
      );
      print("Low dose notification shown.");
    } catch (e) {
      print("Error showing notification: $e");
    }
  }


  Future<void> _initializeDatabase() async {
    if (mounted) setState(() { _isInitializing = true; });
    try {
      FirebaseDatabase database = FirebaseDatabase.instance;
      // Ensure your database URL is correct
      database.databaseURL =
          'https://smart-inhaler-db-default-rtdb.asia-southeast1.firebasedatabase.app/';
      _dbRef = database.ref();
      print('Database reference created: ${_dbRef.path}');

      // Initial Fetch
      try {
         final snapshot = await _dbRef.get().timeout(const Duration(seconds: 10));
         if (snapshot.exists && snapshot.value != null) {
            print('Initial data fetched.');
            _parseData(snapshot.value); // Parse initial data
            if(mounted) setState(() { _isConnected = true; });
         } else {
            print('Initial data fetch: No data found.');
            if (mounted) setState(() { _isConnected = false; });
         }
      } catch(e) {
          print('Error fetching initial data: $e');
          if (mounted) setState(() { _isConnected = false; });
      } finally {
         if (mounted) setState(() { _isInitializing = false; });
      }

      // Listener for updates
      // No need to check _dbRef for null here as it's assigned above or throws
      _subscription?.cancel(); // Cancel previous subscription if exists
      _subscription = _dbRef.onValue.listen(
        (DatabaseEvent event) {
          if (mounted && event.snapshot.value != null) {
             _parseData(event.snapshot.value); // <--- PARSE DATA HERE
             if (!_isConnected) {
               setState(() { _isConnected = true; });
             }
          } else if (event.snapshot.value == null) {
             print('No data received from Firebase stream (null snapshot).');
             // Optionally handle this case, e.g., set _isConnected to false
             // if (mounted && _isConnected) setState(() => _isConnected = false);
          }
        },
        onError: (error) {
           print('Firebase listener error: $error');
           if (mounted) {
              setState(() { _isConnected = false; });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connection error: ${error.toString()}')),
              );
           }
        },
        onDone: () {
           print('Firebase listener closed.');
           if (mounted && _isConnected) {
              setState(() { _isConnected = false; });
           }
        },
      );


    } catch (e) {
       print('Error setting up database reference: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error setting up Firebase: ${e.toString()}')),
          );
          setState(() { _isConnected = false; _isInitializing = false; });
        }
    }
  }

 // Centralized data parsing logic
void _parseData(dynamic rawData) {
     if (rawData == null || rawData is! Map) {
        print('Invalid or null data received for parsing.');
        return;
     }

     try {
        final data = Map<String, dynamic>.from(rawData);
        bool stateChanged = false;

        // Temporarily store old values needed for checks
        final int oldDoseCount = _doseCount; // Keep track of old dose value
        final int oldMaxDoseCount = _maxDoseCount;
        final int oldFSR1 = _fsrSensor1;
        final int oldFSR2 = _fsrSensor2;
        final int oldFSR3 = _fsrSensor3;
        final int oldCorrectCount = _correctCount;
        final int oldFalseCount = _falseCount;
        final int oldDailyDosesTaken = _dailyDosesTaken;


        // --- FSR and Dose Counting Logic ---
        if (data.containsKey('FSR') && data['FSR'] is Map) {
          final fsrData = Map<String, dynamic>.from(data['FSR']);
          final newFSR1 = _parseIntValue(fsrData['sensor1'], _fsrSensor1);
          final newFSR2 = _parseIntValue(fsrData['sensor2'], _fsrSensor2);
          final newFSR3 = _parseIntValue(fsrData['sensor3'], _fsrSensor3);
          const int pressThreshold = 50; // Example threshold
          bool allPressedNow = newFSR1 > pressThreshold && newFSR2 > pressThreshold && newFSR3 > pressThreshold;
          bool notAllPressedBefore = oldFSR1 <= pressThreshold || oldFSR2 <= pressThreshold || oldFSR3 <= pressThreshold;

          // *** Use the CURRENT _doseCount which was updated from Firebase listener ***
          if (allPressedNow && notAllPressedBefore && _doseCount > 0 && !_doseCounted) {
             print("Dose condition met! Attempting to decrement count.");
             _doseCounted = true;
             final newDoseCount = _doseCount - 1; // Calculate new value based on current state

             // *** CORRECT FIREBASE PATH for dose count update ***
             _dbRef.update({'Counts/doseCount': newDoseCount}).then((_) {
                print("Firebase Counts/doseCount updated to $newDoseCount");
                // Listener will update _doseCount state variable
             }).catchError((error) {
                print("Error updating Firebase Counts/doseCount: $error");
                 _doseCounted = false; // Reset flag on error
             });

             _doseCountResetTimer?.cancel();
             _doseCountResetTimer = Timer(const Duration(seconds: 2), () {
                 print("Resetting dose count flag.");
                 _doseCounted = false;
             });
          }
          // Update local FSR state
          if (newFSR1 != _fsrSensor1 || newFSR2 != _fsrSensor2 || newFSR3 != _fsrSensor3) {
             _fsrSensor1 = newFSR1;
             _fsrSensor2 = newFSR2;
             _fsrSensor3 = newFSR3;
             // stateChanged = true; // Only if displayed directly
          }
        }

        // --- REMOVED: Top-level doseCount parsing (it's inside Counts now) ---
        // if (data.containsKey('doseCount')) { ... }

        // --- Max Dose Count Update (from Firebase) ---
        // Keep checking both top-level and inside Counts for flexibility
         if (data.containsKey('maxDoseCount')) {
           final firebaseMaxDoseCount = _parseIntValue(data['maxDoseCount'], _maxDoseCount);
           if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
              _maxDoseCount = firebaseMaxDoseCount;
              print("Max dose count updated from Firebase (top-level): $_maxDoseCount");
              stateChanged = true;
              _lowDoseNotificationShown = false;
           }
         } else if (data.containsKey('Counts') && data['Counts'] is Map && data['Counts']['maxDoseCount'] != null) {
             final countsData = Map<String, dynamic>.from(data['Counts']);
             final firebaseMaxDoseCount = _parseIntValue(countsData['maxDoseCount'], _maxDoseCount);
              if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
                 _maxDoseCount = firebaseMaxDoseCount;
                 print("Max dose count updated from Firebase (Counts map): $_maxDoseCount");
                 stateChanged = true;
                 _lowDoseNotificationShown = false;
              }
         }


        // --- Parse Counts Map for Stats Grid AND Dose Count ---
        if (data.containsKey('Counts') && data['Counts'] is Map) {
          final countsData = Map<String, dynamic>.from(data['Counts']);

          // *** PARSE doseCount HERE ***
          final firebaseDoseCount = _parseIntValue(countsData['doseCount'], _doseCount);
          if (firebaseDoseCount != _doseCount) {
             _doseCount = firebaseDoseCount; // Update local value from Counts map
             print("Dose count updated from Firebase listener (Counts map): $_doseCount");
             stateChanged = true;
          }
          // *** END PARSE doseCount ***

          final newCorrectCount = _parseIntValue(countsData['correctCount'], _correctCount);
          final newFalseCount = _parseIntValue(countsData['falseCount'], _falseCount);
          final newDailyDosesTaken = _parseIntValue(countsData['dailyDosesTaken'], _dailyDosesTaken);

          if (newCorrectCount != _correctCount) {
            _correctCount = newCorrectCount;
            print("Correct count updated from Firebase: $_correctCount");
            stateChanged = true;
          }
          if (newFalseCount != _falseCount) {
            _falseCount = newFalseCount;
             print("False count updated from Firebase: $_falseCount");
            stateChanged = true;
          }
          if (newDailyDosesTaken != _dailyDosesTaken) {
            _dailyDosesTaken = newDailyDosesTaken;
             print("Daily doses taken updated from Firebase: $_dailyDosesTaken");
            stateChanged = true;
          }
        } else {
            print("Warning: 'Counts' map not found or not a map in Firebase data.");
            // If 'Counts' doesn't exist, _doseCount, _correctCount etc retain old values
        }


        // --- Buzzer Control Update ---
        if (data.containsKey('buzzerControl')) {
           final firebaseBuzzerControl = _parseIntValue(data['buzzerControl'], _buzzerControl);
            if (firebaseBuzzerControl != _buzzerControl) {
               _buzzerControl = firebaseBuzzerControl;
               print("Buzzer control updated from Firebase: $_buzzerControl");
               stateChanged = true;
            }
        }

        // --- MPU Data Update ---
        if (data.containsKey('MPU') && data['MPU'] is Map) {
          final mpuData = Map<String, dynamic>.from(data['MPU']);
          double tempAccelX = _accelX, tempAccelY = _accelY, tempAccelZ = _accelZ;
          double tempGyroX = _gyroX, tempGyroY = _gyroY, tempGyroZ = _gyroZ;
          double tempTemp = _temp;
          if (mpuData.containsKey('accelerometer') && mpuData['accelerometer'] is Map) {
            final accelData = Map<String, dynamic>.from(mpuData['accelerometer']);
            tempAccelX = _parseDoubleValue(accelData['x'], _accelX);
            tempAccelY = _parseDoubleValue(accelData['y'], _accelY);
            tempAccelZ = _parseDoubleValue(accelData['z'], _accelZ);
          }
          if (mpuData.containsKey('gyroscope') && mpuData['gyroscope'] is Map) {
            final gyroData = Map<String, dynamic>.from(mpuData['gyroscope']);
             tempGyroX = _parseDoubleValue(gyroData['x'], _gyroX);
             tempGyroY = _parseDoubleValue(gyroData['y'], _gyroY);
             tempGyroZ = _parseDoubleValue(gyroData['z'], _gyroZ);
          }
          if (mpuData.containsKey('temp')) {
             tempTemp = _parseDoubleValue(mpuData['temp'], _temp);
          }
          if (tempAccelX != _accelX || tempAccelY != _accelY || tempAccelZ != _accelZ ||
              tempGyroX != _gyroX || tempGyroY != _gyroY || tempGyroZ != _gyroZ ||
              tempTemp != _temp) {
              _accelX = tempAccelX; _accelY = tempAccelY; _accelZ = tempAccelZ;
              _gyroX = tempGyroX; _gyroY = tempGyroY; _gyroZ = tempGyroZ;
              _temp = tempTemp;
              // Avoid excessive state updates if MPU data changes frequently but isn't critical for UI redraw
              // Only set stateChanged = true if you *need* the UI to update on every MPU change
              // For the numerical display widget, we DO need it.
              stateChanged = true;
          }
        }


        // --- *** Check for Low Dose Notification *** ---
        // Check if dose count or max dose count changed, or if it's the initial load
        // Ensure maxDoseCount is positive to avoid division by zero or weird thresholds
        if ((_doseCount != oldDoseCount || _maxDoseCount != oldMaxDoseCount || (_isInitializing && !_isConnected)) && _maxDoseCount > 0) {
           final int threshold = (_maxDoseCount * 0.2).floor(); // Calculate 20% threshold

           print("Checking notification: Dose=$_doseCount, Max=$_maxDoseCount, Threshold=$threshold, Shown=$_lowDoseNotificationShown"); // Debug print

           // Condition to show notification: dose is below/at threshold AND notification hasn't been shown yet
           if (_doseCount <= threshold && !_lowDoseNotificationShown) {
             _showLowDoseNotification(_doseCount, _maxDoseCount);
             _lowDoseNotificationShown = true; // Set flag
             // Don't necessarily need stateChanged = true here unless the flag affects UI directly
           }
           // Condition to reset flag: dose goes back strictly above threshold
           else if (_doseCount > threshold && _lowDoseNotificationShown) {
             print("Resetting notification flag as dose count is above threshold.");
             _lowDoseNotificationShown = false; // Reset flag
             // Optionally cancel notification if user refills:
             // _flutterLocalNotificationsPlugin.cancel(0);
           }
        }
        // --- End Notification Check ---


        // --- Apply state changes if necessary ---
        if (stateChanged && mounted) {
           print("setState called due to Firebase data change.");
           setState(() {});
        }

        // Final connection status update (handled within listener 'onValue' now)
        // if (!_isConnected && mounted) {
        //    setState(() { _isConnected = true; });
        // }

     } catch (e, stacktrace) {
         print('Error parsing data: $e');
         print('Problematic data chunk: $rawData');
         print('Stacktrace: $stacktrace');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error processing data: ${e.toString()}')),
            );
          }
     }
  }

  // Helper method to parse int values safely
  int _parseIntValue(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    // Handle other types if necessary, or return default
    return defaultValue;
  }

   // Helper method to parse double values safely
  double _parseDoubleValue(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    // Handle other types if necessary, or return default
    return defaultValue;
  }


  // Function to update buzzer control value in Firebase
  Future<void> _updateBuzzerControl() async {
     if (!_isConnected) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot control buzzer: Offline')));
       return;
     }
     // _dbRef should not be null if _isConnected is true based on initialization logic
     // if (_dbRef == null) return;

     final nextBuzzerState = _buzzerControl == 0 ? 29 : 0; // Assuming 29 turns it ON
     try {
        print("Attempting to set buzzerControl to $nextBuzzerState");
        await _dbRef.update({'buzzerControl': nextBuzzerState});
        // Update local state immediately for responsiveness, though listener will confirm
        if (mounted) {
            setState(() { _buzzerControl = nextBuzzerState; });
            print("Local buzzer state updated to $nextBuzzerState");
        }

        // Cancel any existing reset timer
        _buzzerResetTimer?.cancel();

        // If the buzzer was turned ON (state 29), start a timer to turn it OFF
        if (nextBuzzerState == 29) {
           _buzzerResetTimer = Timer(const Duration(seconds: 5), () async {
             // Check if the state is still ON and we are connected before turning OFF
             if (_buzzerControl == 29 && _isConnected && mounted) {
                 try {
                    print("Auto-resetting buzzerControl to 0");
                    await _dbRef.update({'buzzerControl': 0});
                    // Update local state via listener is preferred, but can force here if needed
                    // if(mounted) setState(() => _buzzerControl = 0);
                 } catch (e) {
                     print('Error auto-resetting buzzer: $e');
                     if(mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error stopping buzzer'))); }
                 }
             } else {
                print("Buzzer reset timer fired, but conditions not met (state=$_buzzerControl, connected=$_isConnected)");
             }
           });
        }
     } catch (e) {
        print('Error updating buzzer control: $e');
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error updating buzzer: $e'))); }
     }
  }

  // Function to edit dose count
 void _editDoseCount() {
     // _dbRef should not be null here if the button is active
     if (!_isConnected && !_isInitializing) {
         if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot edit dose count: Offline')));
         return;
     }

     final newDoseCountController = TextEditingController(text: _doseCount.toString());
     showDialog(
       context: context,
       builder: (BuildContext context) {
         return AlertDialog(
           title: const Text('Edit Dose Count'),
           content: TextField(
             controller: newDoseCountController,
             keyboardType: TextInputType.number,
             autofocus: true,
             decoration: InputDecoration(
               labelText: 'Enter remaining doses',
               hintText: 'Current: $_doseCount',
               suffixText: '/ $_maxDoseCount', // Show max dose limit
               border: const OutlineInputBorder(),
             ),
           ),
           actions: [
             TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'),),
             TextButton(
               onPressed: () {
                 final newDoseCountStr = newDoseCountController.text;
                 final newDoseCountInt = int.tryParse(newDoseCountStr);

                 if (newDoseCountInt == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid number entered')));
                    return;
                 }
                 if (newDoseCountInt < 0 || newDoseCountInt > _maxDoseCount) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dose count must be between 0 and $_maxDoseCount')));
                    return;
                 }
                 // If no change, just close the dialog
                 if (newDoseCountInt == _doseCount) {
                    Navigator.of(context).pop();
                    return;
                 }

                 print("Attempting manual dose count update to $newDoseCountInt");
                 // Update Firebase. The listener will handle the state update and notification check.
                  // Again, ensure the path is correct ('doseCount' or 'Counts/doseCount')
                 _dbRef.update({'doseCount': newDoseCountInt}).then((_) {
                    print("Manual dose count update successful.");
                    Navigator.of(context).pop(); // Close dialog on success
                 }).catchError((error) {
                     print("Error manually updating dose count: $error");
                     if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error saving dose count: $error'))); }
                     // Optionally leave the dialog open on error
                 });
               },
               child: const Text('Save'),
             ),
           ],
         );
       },
     );
   }


 // --- NEW: Helper method to build a single stat card for the grid ---
   Widget _buildStatCard(String title, String value) {
    return Card(
      color: const Color(0xFF0D47A1), // Dark blue color from image
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
      elevation: 3,
      child: Padding(
        // Slightly reduce vertical padding if needed, but try aspect ratio first
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Center content vertically
          crossAxisAlignment: CrossAxisAlignment.center, // Center content horizontally
          children: [
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600), // Slightly smaller title?
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6), // Slightly reduce space
            // Wrap the large value text with FittedBox
            Expanded( // Allow FittedBox to take available vertical space
              child: FittedBox(
                fit: BoxFit.scaleDown, // Scale down if needed, don't scale up
                child: Text(
                  value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold), // Keep original size, FittedBox will shrink if needed
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
 // --- End NEW Helper Method ---


  @override
  void dispose() {
    print("Disposing InhalerDashboardScreen1");
    _subscription?.cancel();
    _doseCountResetTimer?.cancel();
    _buzzerResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget bodyContent;

     if (_isInitializing) {
       bodyContent = const Center(
         child: Column(
           mainAxisAlignment: MainAxisAlignment.center,
           children: [
             CircularProgressIndicator(),
             SizedBox(height: 16),
             Text('Connecting to Inhaler...'),
           ],
         ),
       );
     } else if (!_isConnected) {
        bodyContent = Center(
           child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                 mainAxisAlignment: MainAxisAlignment.center,
                 crossAxisAlignment: CrossAxisAlignment.center,
                 children: [
                    Icon(Icons.cloud_off, size: 60, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    const Text('Inhaler Offline', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold), textAlign: TextAlign.center,),
                    const SizedBox(height: 8),
                     const Text('Check device connection and internet access. Data shown may be outdated.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey),),
                    const SizedBox(height: 25),
                    ElevatedButton.icon(
                       icon: const Icon(Icons.refresh),
                       label: const Text('Retry Connection'),
                       onPressed: _initializeDatabase, // Retry initialization
                       style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12) ),
                    )
                 ],
              ),
           ),
        );
     } else {
       // --- Connected State ---
       bodyContent = SingleChildScrollView(
         physics: const AlwaysScrollableScrollPhysics(), // Allow scrolling if content overflows
         padding: const EdgeInsets.all(16.0),
         child: Column(
           mainAxisAlignment: MainAxisAlignment.start,
           children: [
              // --- Dose Counter Widget (Imported) ---
              DoseCounter(
                doseCount: _doseCount,
                maxDoseCount: _maxDoseCount,
                onEdit: _editDoseCount,
              ),
              const SizedBox(height: 24), // Spacing after DoseCounter

              // --- NEW Stats Grid ---
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true, // Important inside SingleChildScrollView
                physics: const NeverScrollableScrollPhysics(), // Disable grid's own scrolling
                crossAxisSpacing: 12, // Horizontal space between cards
                mainAxisSpacing: 12,  // Vertical space between cards
                childAspectRatio: 1.6, // Width / Height ratio - adjust as needed for appearance
                children: [
                  _buildStatCard('Daily Doses', '$_dailyDosesTaken/$_dailyDoseLimit'),
                  _buildStatCard('Correct Count', '$_correctCount'),
                  // Displaying the overall maximum capacity here
                  _buildStatCard('Maximum dose', '$_maxDoseCount'),
                  _buildStatCard('False Count', '$_falseCount'),
                ],
              ),
              // --- End NEW Stats Grid ---

              const SizedBox(height: 24), // Spacing before BuzzerControl

              // --- Buzzer Control Widget (Imported) ---
              BuzzerControl(
                buzzerControl: _buzzerControl,
                onToggle: _updateBuzzerControl,
              ),
              const SizedBox(height: 30),

               // --- Navigation Buttons ---
               // Assuming test.dart defines FirebaseDataScreen2
               _buildNavigationButton( context: context, text: 'View FSR & History', targetScreen: const FirebaseDataScreen2(), ),
               const SizedBox(height: 15),
               // Assuming graphscreen.dart defines GraphScreen
               _buildNavigationButton( context: context, text: 'View Sensor Graphs', targetScreen: const GraphScreen(), ),
               const SizedBox(height: 30),

               // --- Motion Sensor Numerical Data Widget ---
               // Ensure motionDataWidget.dart exists and defines this widget
              
              const SizedBox(height: 20), // Bottom padding
             ],
           ),
       );
     }

    return Scaffold(
      backgroundColor: Colors.grey[100], // Light grey background
      appBar: AppBar(
        title: const Text('Smart Inhaler'),
        elevation: 1, // Subtle shadow
        backgroundColor: Colors.white,
        foregroundColor: _textColor, // Use defined text color
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Tooltip(
                message: _isConnected ? 'Connected to Firebase' : 'Disconnected from Firebase',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                     color: _isConnected ? Colors.green[100] : Colors.red[100],
                     borderRadius: BorderRadius.circular(10),
                     border: Border.all( color: _isConnected ? Colors.green[300]! : Colors.red[300]!, width: 0.5 )
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon( _isConnected ? Icons.wifi : Icons.wifi_off, color: _isConnected ? Colors.green[800] : Colors.red[800], size: 16, ),
                       const SizedBox(width: 4),
                        Text( _isConnected ? 'Online' : 'Offline', style: TextStyle( color: _isConnected ? Colors.green[800] : Colors.red[800], fontSize: 12, fontWeight: FontWeight.bold ), ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea( // Ensures content avoids notches, status bars, etc.
        child: bodyContent,
      ),
    );
  }

 // Helper method for navigation buttons
 Widget _buildNavigationButton({ required BuildContext context, required String text, required Widget targetScreen, }) {
    return ElevatedButton(
      onPressed: () {
         // Only navigate if connected? Or allow navigation even if offline?
         // If navigation depends on live data in the target screen, check _isConnected here.
         Navigator.push( context, MaterialPageRoute(builder: (context) => targetScreen), );
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50), // Full width, fixed height
        shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
      ),
      child: Text(text),
    );
 }
}

