//screen1.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';

// --- Import Separated Components ---
import 'notification_service.dart'; // <-- Import Notification Service
import 'stats_grid.dart';           // <-- Import Stats Grid Widget
import 'connection_status_handler.dart'; // <-- Import the new handler

// Import other widgets and screens (ensure paths are correct)
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
  int _doseCount = 90;
  int _maxDoseCount = 200;

  // Variables for the Stats Grid
  int _correctCount = 0;
  int _falseCount = 0;
  int _dailyDosesTaken = 0;
  final int _dailyDoseLimit = 5;

  // Variables to store MPU6050 data (keep if displayed elsewhere or needed)
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
  late final NotificationService _notificationService;
  bool _lowDoseNotificationShown = false;

  @override
  void initState() {
    super.initState();
     _notificationService = NotificationService(
       onNotificationTap: (NotificationResponse response) async {
         print("Notification tapped from screen1: ${response.payload}");
       }
     );
    _notificationService.init(context);
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    if (mounted) setState(() { _isInitializing = true; });
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
            if(mounted) setState(() { _isConnected = true; }); // Set connected after parsing
         } else {
            print('Initial data fetch: No data found.');
            if (mounted) setState(() { _isConnected = false; });
         }
      } catch(e) {
          print('Error fetching initial data: $e');
          if (mounted) setState(() { _isConnected = false; });
      } finally {
         // Crucially, set initializing to false *after* attempting fetch and parse
         if (mounted) setState(() { _isInitializing = false; });
      }

      // Listener for updates
      _subscription?.cancel(); // Cancel previous listener if any
      _subscription = _dbRef.onValue.listen(
        (DatabaseEvent event) {
          if (mounted && event.snapshot.value != null) {
             _parseData(event.snapshot.value); // Parse incoming data
             // Ensure connection state is updated if it wasn't already
             if (!_isConnected) {
               setState(() { _isConnected = true; });
             }
          } else if (event.snapshot.value == null) {
             print('No data received from Firebase stream (null snapshot).');
             // Optionally handle this, maybe set to disconnected if it persists?
             // if (mounted) setState(() => _isConnected = false);
          }
        },
        onError: (error) {
           print('Firebase listener error: $error');
           if (mounted) {
              setState(() { _isConnected = false; }); // Set disconnected on error
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Connection error: ${error.toString()}')),
              );
           }
        },
        onDone: () {
           print('Firebase listener closed.');
           if (mounted && _isConnected) {
              setState(() { _isConnected = false; }); // Set disconnected when stream closes
           }
        },
      );

    } catch (e) {
       print('Error setting up database reference: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error setting up Firebase: ${e.toString()}')),
          );
          // Ensure states are correct on setup error
          setState(() { _isConnected = false; _isInitializing = false; });
        }
    }
  }

 // Centralized data parsing logic
 void _parseData(dynamic rawData) {
     if (rawData == null || rawData is! Map) {
        print('Invalid or null data received for parsing.');
        // Decide if this means disconnected or just bad data.
        // Maybe keep the current state unless it's consistently null?
        // Example: If it's critical data is missing, set _isConnected = false;
        return;
     }

     try {
        final data = Map<String, dynamic>.from(rawData);
        bool stateChanged = false;

        // Temporarily store old values needed for checks
        final int oldDoseCount = _doseCount;
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
          // Check against previous *parsed* values, not the ones directly from the state before this function call
          bool notAllPressedBefore = oldFSR1 <= pressThreshold || oldFSR2 <= pressThreshold || oldFSR3 <= pressThreshold;

          if (allPressedNow && notAllPressedBefore && _doseCount > 0 && !_doseCounted) {
             print("Dose condition met! Attempting to decrement count.");
             _doseCounted = true; // Set flag immediately
             final newDoseCount = _doseCount - 1; // Calculate based on *current* state

             // Update Firebase - Listener will handle the state update if successful
             _dbRef.update({'Counts/doseCount': newDoseCount}).then((_) {
                print("Firebase Counts/doseCount updated to $newDoseCount");
                // Do NOT update _doseCount here, let the listener do it
             }).catchError((error) {
                print("Error updating Firebase Counts/doseCount: $error");
                 // If update fails, reset the flag so user can try again
                 _doseCounted = false;
             });

             // Start the reset timer regardless of Firebase success for the flag
             _doseCountResetTimer?.cancel();
             _doseCountResetTimer = Timer(const Duration(seconds: 2), () {
                 print("Resetting dose count flag.");
                 _doseCounted = false; // Reset the local flag after delay
             });
          }
          // Update local FSR state values AFTER the check
          if (newFSR1 != _fsrSensor1 || newFSR2 != _fsrSensor2 || newFSR3 != _fsrSensor3) {
             _fsrSensor1 = newFSR1;
             _fsrSensor2 = newFSR2;
             _fsrSensor3 = newFSR3;
             // stateChanged = true; // Only set true if these values are directly displayed
          }
        }


        // --- Max Dose Count Update (from Firebase) ---
         if (data.containsKey('maxDoseCount')) { // Check top-level first
           final firebaseMaxDoseCount = _parseIntValue(data['maxDoseCount'], _maxDoseCount);
           if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
              _maxDoseCount = firebaseMaxDoseCount;
              print("Max dose count updated from Firebase (top-level): $_maxDoseCount");
              stateChanged = true;
              _lowDoseNotificationShown = false; // Reset flag on max dose change
           }
         } else if (data.containsKey('Counts') && data['Counts'] is Map && data['Counts']['maxDoseCount'] != null) { // Check within Counts map
             final countsData = Map<String, dynamic>.from(data['Counts']);
             final firebaseMaxDoseCount = _parseIntValue(countsData['maxDoseCount'], _maxDoseCount);
              if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
                 _maxDoseCount = firebaseMaxDoseCount;
                 print("Max dose count updated from Firebase (Counts map): $_maxDoseCount");
                 stateChanged = true;
                 _lowDoseNotificationShown = false; // Reset flag on max dose change
              }
         }


        // --- Parse Counts Map for Stats Grid AND Dose Count ---
        if (data.containsKey('Counts') && data['Counts'] is Map) {
          final countsData = Map<String, dynamic>.from(data['Counts']);

          // Dose Count (updated by listener from Firebase)
          final firebaseDoseCount = _parseIntValue(countsData['doseCount'], _doseCount);
          if (firebaseDoseCount != _doseCount) {
             _doseCount = firebaseDoseCount;
             print("Dose count updated from Firebase listener (Counts map): $_doseCount");
             stateChanged = true; // Dose count affects UI
          }

          // Other stats
          final newCorrectCount = _parseIntValue(countsData['correctCount'], _correctCount);
          final newFalseCount = _parseIntValue(countsData['falseCount'], _falseCount);
          final newDailyDosesTaken = _parseIntValue(countsData['dailyDosesTaken'], _dailyDosesTaken);

          if (newCorrectCount != _correctCount) {
            _correctCount = newCorrectCount;
            print("Correct count updated from Firebase: $_correctCount");
            stateChanged = true; // Affects StatsGrid
          }
          if (newFalseCount != _falseCount) {
            _falseCount = newFalseCount;
             print("False count updated from Firebase: $_falseCount");
            stateChanged = true; // Affects StatsGrid
          }
          if (newDailyDosesTaken != _dailyDosesTaken) {
            _dailyDosesTaken = newDailyDosesTaken;
             print("Daily doses taken updated from Firebase: $_dailyDosesTaken");
            stateChanged = true; // Affects StatsGrid
          }
        } else {
            print("Warning: 'Counts' map not found or not a map in Firebase data.");
            // Consider if missing Counts means data is incomplete/invalid
        }


        // --- Buzzer Control Update ---
        if (data.containsKey('buzzerControl')) {
           final firebaseBuzzerControl = _parseIntValue(data['buzzerControl'], _buzzerControl);
            if (firebaseBuzzerControl != _buzzerControl) {
               _buzzerControl = firebaseBuzzerControl;
               print("Buzzer control updated from Firebase: $_buzzerControl");
               stateChanged = true; // Affects BuzzerControl widget
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
           // Check if any MPU value actually changed
           if (tempAccelX != _accelX || tempAccelY != _accelY || tempAccelZ != _accelZ ||
               tempGyroX != _gyroX || tempGyroY != _gyroY || tempGyroZ != _gyroZ ||
               tempTemp != _temp) {
               _accelX = tempAccelX; _accelY = tempAccelY; _accelZ = tempAccelZ;
               _gyroX = tempGyroX; _gyroY = tempGyroY; _gyroZ = tempGyroZ;
               _temp = tempTemp;
               // Only set stateChanged = true if MPU data is displayed directly on *this* screen
               // If it's only used on the GraphScreen, no need to trigger rebuild here.
               // stateChanged = true;
               print("MPU data updated (Accel: $tempAccelX, Gyro: $tempGyroX, Temp: $tempTemp)");
           }
        }


        // --- Check for Low Dose Notification ---
        // Check if dose count OR max dose count changed compared to *before* parsing
        if ((_doseCount != oldDoseCount || _maxDoseCount != oldMaxDoseCount) && _maxDoseCount > 0) {
           final int threshold = (_maxDoseCount * 0.2).floor(); // Recalculate threshold

           print("Checking notification: Dose=$_doseCount, Max=$_maxDoseCount, Threshold=$threshold, Shown=$_lowDoseNotificationShown");

           if (_doseCount <= threshold && !_lowDoseNotificationShown) {
             _notificationService.showLowDoseNotification(_doseCount, _maxDoseCount);
             _lowDoseNotificationShown = true; // Set flag *after* showing
           }
           else if (_doseCount > threshold && _lowDoseNotificationShown) {
             print("Resetting notification flag as dose count is above threshold.");
             _lowDoseNotificationShown = false;
             _notificationService.cancelNotification(0); // Cancel if above threshold again
           }
        }
        // --- End Notification Check ---

        // Trigger rebuild ONLY if relevant state affecting the UI has changed
        if (stateChanged && mounted) {
           print("setState called due to Firebase data change.");
           setState(() {});
        }

     } catch (e, stacktrace) {
         print('Error parsing data: $e');
         print('Problematic data chunk: $rawData');
         print('Stacktrace: $stacktrace');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error processing data: ${e.toString()}')),
            );
            // Consider setting _isConnected = false here if parsing errors are frequent/critical
            // setState(() => _isConnected = false);
          }
     }
  }

  // Helper method to parse int values safely
  int _parseIntValue(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    print("Warning: Could not parse int value '$value', using default $defaultValue");
    return defaultValue;
  }

   // Helper method to parse double values safely
  double _parseDoubleValue(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    print("Warning: Could not parse double value '$value', using default $defaultValue");
    return defaultValue;
  }

  // Function to update buzzer control value in Firebase
  Future<void> _updateBuzzerControl() async {
     if (!_isConnected) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot control buzzer: Offline')));
       return;
     }

     // Determine the next state based on the *current* state
     final nextBuzzerState = _buzzerControl == 0 ? 29 : 0;
     try {
        print("Attempting to set buzzerControl to $nextBuzzerState");
        // Update Firebase - the listener will update the local _buzzerControl state
        await _dbRef.update({'buzzerControl': nextBuzzerState});
        print("Firebase buzzerControl update initiated.");

        // Manage the auto-reset timer locally based on the *intended* next state
        _buzzerResetTimer?.cancel(); // Cancel any existing timer

        if (nextBuzzerState == 29) { // If we just turned the buzzer ON
           _buzzerResetTimer = Timer(const Duration(seconds: 5), () async {
             // Check the actual state *when the timer fires*
             if (_buzzerControl == 29 && _isConnected && mounted) {
                 try {
                    print("Auto-resetting buzzerControl to 0");
                    // Send update to Firebase, listener will handle state change
                    await _dbRef.update({'buzzerControl': 0});
                 } catch (e) {
                     print('Error auto-resetting buzzer: $e');
                     if(mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error stopping buzzer'))); }
                 }
             } else {
                print("Buzzer reset timer fired, but conditions not met (state=$_buzzerControl, connected=$_isConnected, mounted=$mounted)");
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
     // Check connection status *before* showing dialog
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
               // Use the current max dose count from state
               suffixText: '/ $_maxDoseCount',
               border: const OutlineInputBorder(),
             ),
           ),
           actions: [
             TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'),),
             TextButton(
               onPressed: () async { // Make async for await
                 final newDoseCountStr = newDoseCountController.text;
                 final newDoseCountInt = int.tryParse(newDoseCountStr);

                 if (newDoseCountInt == null || newDoseCountInt < 0 || newDoseCountInt > _maxDoseCount) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dose count must be between 0 and $_maxDoseCount')));
                    return; // Stay in dialog if invalid
                 }
                 if (newDoseCountInt == _doseCount) {
                    Navigator.of(context).pop(); // Close if no change
                    return;
                 }

                 print("Attempting manual dose count update to $newDoseCountInt");
                 try {
                     // Update Firebase. The listener will update the UI state.
                     await _dbRef.update({'Counts/doseCount': newDoseCountInt});
                     print("Manual dose count update successful.");
                     Navigator.of(context).pop(); // Close dialog on success
                 } catch (error) {
                     print("Error manually updating dose count: $error");
                     if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Error saving dose count: $error'))
                       );
                     }
                     // Optionally keep the dialog open on error, or close it
                     // Navigator.of(context).pop();
                 }
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
    // This is the main content widget that will be passed to ConnectionStatusHandler
    Widget mainContent = SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
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
          const SizedBox(height: 24),

          // --- Stats Grid Widget (Imported) ---
          StatsGrid(
            dailyDosesTaken: _dailyDosesTaken,
            dailyDoseLimit: _dailyDoseLimit,
            correctCount: _correctCount,
            falseCount: _falseCount,
            maxDoseCount: _maxDoseCount, // Pass the max dose count
          ),
          const SizedBox(height: 24),

          // --- Buzzer Control Widget (Imported) ---
          BuzzerControl(
            buzzerControl: _buzzerControl,
            onToggle: _updateBuzzerControl,
          ),
          const SizedBox(height: 30),

          // --- Navigation Buttons ---
          _buildNavigationButton(
            context: context,
            text: 'View FSR & History',
            targetScreen: const FirebaseDataScreen2(),
          ),
          const SizedBox(height: 15),
          _buildNavigationButton(
            context: context,
            text: 'View Sensor Graphs',
            targetScreen: const GraphScreen(),
          ),
          const SizedBox(height: 30),

          const SizedBox(height: 20), // Bottom padding
        ],
      ),
    );

    return Scaffold(
      backgroundColor: Colors.grey[100], // Light grey background
      appBar: AppBar(
        title: const Text('Smart Inhaler'),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        actions: [
          // --- Use the Reusable Connection Status Indicator Widget ---
          ConnectionStatusIndicator(isConnected: _isConnected),
        ],
      ),
      body: SafeArea(
        // --- Use the ConnectionStatusHandler to manage body content ---
        child: ConnectionStatusHandler(
          isInitializing: _isInitializing,
          isConnected: _isConnected,
          onRetry: _initializeDatabase, // Pass the retry function
          child: mainContent,          // Pass the main dashboard UI
        ),
      ),
    );
  }

 // Helper method for navigation buttons (no changes needed here)
 Widget _buildNavigationButton({
   required BuildContext context,
   required String text,
   required Widget targetScreen,
 }) {
    return ElevatedButton(
      onPressed: () {
        Navigator.push( context, MaterialPageRoute(builder: (context) => targetScreen), );
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50),
        shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(12), ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
      ),
      child: Text(text),
    );
 }
}