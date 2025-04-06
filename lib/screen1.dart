//screen1.dart (or your main screen file name)
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // <-- IMPORT NOTIFICATION PLUGIN

// Import the separated widgets and other screens
// --- NO CHANGES TO IMPORTS HERE ---
import 'dose_counter.dart';
import 'graphscreen.dart';
import 'test.dart'; // Import screen 2
import 'buzzer_control.dart'; // Import BuzzerControl
import 'motionDataWidget.dart'; // <-- IMPORT THE NEW WIDGET FILE

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
  int _doseCount = 90;
  int _maxDoseCount = 200;

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
        if (Theme.of(context).platform == TargetPlatform.android) {
           final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
               _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
                       AndroidFlutterLocalNotificationsPlugin>();
           final bool? granted = await androidImplementation?.requestNotificationsPermission();
           print("Android Notification Permission Granted: $granted");
        }

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
    setState(() { _isInitializing = true; });
    try {
      FirebaseDatabase database = FirebaseDatabase.instance;
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
      if(_dbRef != null) {
          _subscription?.cancel();
          _subscription = _dbRef.onValue.listen(
            (DatabaseEvent event) {
              if (event.snapshot.value != null) {
                _parseData(event.snapshot.value); // <--- PARSE DATA HERE
                if (!_isConnected && mounted) {
                   setState(() { _isConnected = true; });
                }
              } else {
                print('No data received from Firebase stream.');
              }
            },
            onError: (error) { /* ... error handling ... */ },
            onDone: () { /* ... done handling ... */ },
          );
      } else {
          print("DB ref null, cannot listen.");
           if (mounted) setState(() { _isConnected = false; _isInitializing = false; });
      }

    } catch (e) {
       /* ... setup error handling ... */
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
        final int oldDoseCount = _doseCount;
        final int oldMaxDoseCount = _maxDoseCount;
        final oldFSR1 = _fsrSensor1;
        final oldFSR2 = _fsrSensor2;
        final oldFSR3 = _fsrSensor3;

        // --- FSR and Dose Counting Logic ---
        if (data.containsKey('FSR') && data['FSR'] is Map) {
          final fsrData = Map<String, dynamic>.from(data['FSR']);
          final newFSR1 = _parseIntValue(fsrData['sensor1'], _fsrSensor1);
          final newFSR2 = _parseIntValue(fsrData['sensor2'], _fsrSensor2);
          final newFSR3 = _parseIntValue(fsrData['sensor3'], _fsrSensor3);
          const int pressThreshold = 50;
          bool allPressedNow = newFSR1 > pressThreshold && newFSR2 > pressThreshold && newFSR3 > pressThreshold;
          bool notAllPressedBefore = oldFSR1 <= pressThreshold || oldFSR2 <= pressThreshold || oldFSR3 <= pressThreshold;

          if (allPressedNow && notAllPressedBefore && _doseCount > 0 && !_doseCounted) {
             print("Dose condition met! Decrementing count.");
             _doseCounted = true;
             final newDoseCount = _doseCount - 1;
             // Update Firebase. The listener will pick up the change and update _doseCount.
             _dbRef.update({'doseCount': newDoseCount}).then((_) {
                print("Firebase doseCount updated to $newDoseCount");
             }).catchError((error) {
                print("Error updating Firebase doseCount: $error");
                 _doseCounted = false; // Reset flag on error
             });
             _doseCountResetTimer?.cancel();
             _doseCountResetTimer = Timer(const Duration(seconds: 2), () {
                 print("Resetting dose count flag.");
                 _doseCounted = false;
             });
          }
          // Update local FSR state (needed for the 'notAllPressedBefore' check next time)
          if (newFSR1 != _fsrSensor1 || newFSR2 != _fsrSensor2 || newFSR3 != _fsrSensor3) {
             _fsrSensor1 = newFSR1;
             _fsrSensor2 = newFSR2;
             _fsrSensor3 = newFSR3;
             // stateChanged = true; // Only set true if displayed or used in UI logic directly
          }
        }

        // --- Dose Count Update (from Firebase) ---
        if (data.containsKey('doseCount')) {
           final firebaseDoseCount = _parseIntValue(data['doseCount'], _doseCount);
           if (firebaseDoseCount != _doseCount) {
              _doseCount = firebaseDoseCount; // Update local value
              stateChanged = true;
           }
        }

        // --- Max Dose Count Update (from Firebase) ---
         if (data.containsKey('maxDoseCount')) {
           final firebaseMaxDoseCount = _parseIntValue(data['maxDoseCount'], _maxDoseCount);
           if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
              _maxDoseCount = firebaseMaxDoseCount; // Update local value
              stateChanged = true;
               // Reset notification flag if max dose changes, so it re-evaluates
               _lowDoseNotificationShown = false;
           }
        }

        // --- Buzzer Control Update ---
        if (data.containsKey('buzzerControl')) {
           final firebaseBuzzerControl = _parseIntValue(data['buzzerControl'], _buzzerControl);
            if (firebaseBuzzerControl != _buzzerControl) {
               _buzzerControl = firebaseBuzzerControl;
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
           setState(() {});
        }

        // Final connection status update
         if (!_isConnected && mounted) {
             setState(() { _isConnected = true; });
         }

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
    return int.tryParse(value.toString()) ?? defaultValue;
  }

   // Helper method to parse double values safely
  double _parseDoubleValue(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }


  // Function to update buzzer control value in Firebase
  Future<void> _updateBuzzerControl() async {
     // --- NO CHANGES TO THIS METHOD ---
     if (!_isConnected) { /* ... */ return; }
     if (_dbRef == null) { /* ... */ return; }
     final nextBuzzerState = _buzzerControl == 0 ? 29 : 0;
     try {
        await _dbRef.update({'buzzerControl': nextBuzzerState});
        if (mounted) { setState(() { _buzzerControl = nextBuzzerState; }); }
        _buzzerResetTimer?.cancel();
        if (nextBuzzerState == 29) {
           _buzzerResetTimer = Timer(const Duration(seconds: 5), () async {
             if (_buzzerControl == 29 && _isConnected && _dbRef != null && mounted) {
                 try {
                    await _dbRef.update({'buzzerControl': 0});
                    if(mounted) setState(() => _buzzerControl = 0);
                 } catch (e) {
                     print('Error auto-resetting buzzer: $e');
                     if(mounted) { /* show snackbar */ }
                 }
             }
           });
        }
     } catch (e) {
        print('Error updating buzzer control: $e');
        if (mounted) { /* show snackbar */ }
     }
  }

  // Function to edit dose count
 void _editDoseCount() {
     // --- NO CHANGES TO THIS METHOD ---
     if (_dbRef == null) { /* ... */ return; }
      if (!_isConnected && !_isInitializing) { /* ... */ }
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
               suffixText: '/ $_maxDoseCount',
               border: const OutlineInputBorder(),
             ),
           ),
           actions: [
             TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'),),
             TextButton(
               onPressed: () {
                 final newDoseCountInt = int.tryParse(newDoseCountController.text);
                 if (newDoseCountInt == null) { /* ... */ return; }
                 if (newDoseCountInt < 0 || newDoseCountInt > _maxDoseCount) { /* ... */ return; }
                 if (newDoseCountInt == _doseCount) { Navigator.of(context).pop(); return; }

                 _dbRef.update({'doseCount': newDoseCountInt}).then((_) {
                    print("Manual dose count update to $newDoseCountInt successful.");
                    // The listener will handle the state update and notification check
                    Navigator.of(context).pop();
                 }).catchError((error) {
                     print("Error manually updating dose count: $error");
                     if (mounted) { /* show snackbar */ }
                 });
               },
               child: const Text('Save'),
             ),
           ],
         );
       },
     );
   }

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
                       onPressed: _initializeDatabase,
                       style: ElevatedButton.styleFrom( padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12) ),
                    )
                 ],
              ),
           ),
        );
     } else {
       // --- Connected State ---
       bodyContent = SingleChildScrollView(
         physics: const AlwaysScrollableScrollPhysics(),
         padding: const EdgeInsets.all(16.0),
         child: Column(
           mainAxisAlignment: MainAxisAlignment.start,
           children: [
              // --- Use the imported DoseCounter widget (UNCHANGED) ---
              DoseCounter(
                doseCount: _doseCount,
                maxDoseCount: _maxDoseCount,
                onEdit: _editDoseCount,
              ),
              const SizedBox(height: 24),

              // --- Use the imported BuzzerControl widget (UNCHANGED) ---
              BuzzerControl(
                buzzerControl: _buzzerControl,
                onToggle: _updateBuzzerControl,
              ),
              const SizedBox(height: 30),

               // --- Navigation Buttons (UNCHANGED) ---
               _buildNavigationButton( context: context, text: 'View FSR & History', targetScreen: const FirebaseDataScreen2(), ),
               const SizedBox(height: 15),
               _buildNavigationButton( context: context, text: 'View Sensor Graphs', targetScreen: const GraphScreen(), ),
               const SizedBox(height: 30),

               // --- Use the imported MotionSensorNumericalData widget (UNCHANGED) ---
               MotionSensorNumericalData(
                accelX: _accelX, accelY: _accelY, accelZ: _accelZ,
                gyroX: _gyroX, gyroY: _gyroY, gyroZ: _gyroZ,
                temp: _temp,
              ),
              const SizedBox(height: 20),
             ],
           ),
       );
     }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Smart Inhaler'),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        actions: [
          // Connection status indicator (UNCHANGED)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Tooltip(
                message: _isConnected ? 'Connected' : 'Disconnected',
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
      body: SafeArea(
        child: bodyContent,
      ),
    );
  }

 // Helper method for navigation buttons (UNCHANGED)
 Widget _buildNavigationButton({ required BuildContext context, required String text, required Widget targetScreen, }) {
    return ElevatedButton(
      onPressed: () { Navigator.push( context, MaterialPageRoute(builder: (context) => targetScreen), ); },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
      ),
      child: Text(text),
    );
 }
}