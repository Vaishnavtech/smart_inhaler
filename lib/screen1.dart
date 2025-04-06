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

// --- Threshold Constants (Updated FSR3) ---
const int FSR1_THRESHOLD = 500;
const int FSR2_THRESHOLD = 50;
const int FSR3_THRESHOLD = 2000; // <-- UPDATED threshold as per new requirement
const double GYRO_Z_THRESHOLD = 7.0;

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
  int _doseCount = 200; // Initial placeholder, will be overwritten by Firebase
  int _maxDoseCount = 200; // Initial placeholder

  // Variables for the Stats Grid
  int _correctCount = 0;
  int _falseCount = 0;
  int _dailyDosesTaken = 0;
  final int _dailyDoseLimit = 5; // Keep this limit, but dailyDosesTaken now increments only on 'correct'

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

  // Flag and timer to prevent multiple counts for a single actuation
  bool _doseActionInProgress = false;
  Timer? _doseActionResetTimer;
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
            _parseData(snapshot.value, isInitialFetch: true); // Parse initial data
            if(mounted) setState(() { _isConnected = true; });
         } else {
            print('Initial data fetch: No data found.');
             _setInitialDefaults();
             if (mounted) setState(() { _isConnected = false; }); // Assume disconnected if no data initially
         }
      } catch(e) {
          print('Error fetching initial data: $e');
          _setInitialDefaults();
          if (mounted) setState(() { _isConnected = false; });
      } finally {
         if (mounted) setState(() { _isInitializing = false; });
      }

      // Listener for updates
      _subscription?.cancel();
      _subscription = _dbRef.onValue.listen(
        (DatabaseEvent event) {
          if (mounted && event.snapshot.value != null) {
             _parseData(event.snapshot.value); // Parse incoming data
             if (!_isConnected) {
               setState(() { _isConnected = true; });
             }
          } else if (event.snapshot.value == null) {
             print('No data received from Firebase stream (null snapshot).');
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
          _setInitialDefaults(); // Set defaults on setup error
          setState(() { _isConnected = false; _isInitializing = false; });
        }
    }
  }

  void _setInitialDefaults() {
      _doseCount = 90;
      _maxDoseCount = 200;
      _correctCount = 0;
      _falseCount = 0;
      _dailyDosesTaken = 0;
      _fsrSensor1 = 0;
      _fsrSensor2 = 0;
      _fsrSensor3 = 0;
      _accelX = 0.0; _accelY = 0.0; _accelZ = 0.0;
      _gyroX = 0.0; _gyroY = 0.0; _gyroZ = 0.0;
      _temp = 0.0;
      _buzzerControl = 0;
  }

 void _parseData(dynamic rawData, {bool isInitialFetch = false}) {
     if (rawData == null || rawData is! Map) {
        print('Invalid or null data received for parsing.');
        return;
     }

     try {
        final data = Map<String, dynamic>.from(rawData);
        bool stateChanged = false; // Tracks if UI needs rebuild

        // Store old values needed for checks and comparisons
        final int oldDoseCount = _doseCount;
        final int oldMaxDoseCount = _maxDoseCount;
        final int oldCorrectCount = _correctCount;
        final int oldFalseCount = _falseCount;
        final int oldDailyDosesTaken = _dailyDosesTaken;
        final int oldBuzzerControl = _buzzerControl;
        final double oldGyroZ = _gyroZ;
        final int oldFSR1 = _fsrSensor1;
        final int oldFSR2 = _fsrSensor2;
        final int oldFSR3 = _fsrSensor3;

        // --- Temp variables to hold newly parsed values ---
        int newFSR1 = _fsrSensor1;
        int newFSR2 = _fsrSensor2;
        int newFSR3 = _fsrSensor3;
        double newGyroZ = _gyroZ;

        // --- Parse FSR Data ---
        if (data.containsKey('FSR') && data['FSR'] is Map) {
          final fsrData = Map<String, dynamic>.from(data['FSR']);
          newFSR1 = _parseIntValue(fsrData['sensor1'], _fsrSensor1);
          newFSR2 = _parseIntValue(fsrData['sensor2'], _fsrSensor2);
          newFSR3 = _parseIntValue(fsrData['sensor3'], _fsrSensor3);
          if (newFSR1 != _fsrSensor1 || newFSR2 != _fsrSensor2 || newFSR3 != _fsrSensor3) {
              _fsrSensor1 = newFSR1;
              _fsrSensor2 = newFSR2;
              _fsrSensor3 = newFSR3;
              print("FSR data updated: S1=$newFSR1, S2=$newFSR2, S3=$newFSR3");
          }
        }

        // --- Parse MPU Data (including Gyro Z) ---
        if (data.containsKey('MPU') && data['MPU'] is Map) {
           final mpuData = Map<String, dynamic>.from(data['MPU']);
           double tempAccelX = _accelX, tempAccelY = _accelY, tempAccelZ = _accelZ;
           double tempGyroX = _gyroX, tempGyroY = _gyroY;
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
              newGyroZ = _parseDoubleValue(gyroData['z'], _gyroZ);
           }
           if (mpuData.containsKey('temp')) {
              tempTemp = _parseDoubleValue(mpuData['temp'], _temp);
           }

           if (tempAccelX != _accelX || tempAccelY != _accelY || tempAccelZ != _accelZ ||
               tempGyroX != _gyroX || tempGyroY != _gyroY || newGyroZ != _gyroZ ||
               tempTemp != _temp) {
               _accelX = tempAccelX; _accelY = tempAccelY; _accelZ = tempAccelZ;
               _gyroX = tempGyroX; _gyroY = tempGyroY; _gyroZ = newGyroZ;
               _temp = tempTemp;
               print("MPU data updated (GyroZ: $newGyroZ)");
           }
        }

        // --- Parse Counts Map (Dose, Correct, False, Daily, MaxDose) ---
        int firebaseDoseCount = _doseCount;
        int firebaseCorrectCount = _correctCount;
        int firebaseFalseCount = _falseCount;
        int firebaseDailyDosesTaken = _dailyDosesTaken;
        int firebaseMaxDoseCount = _maxDoseCount;

         if (data.containsKey('maxDoseCount')) {
            firebaseMaxDoseCount = _parseIntValue(data['maxDoseCount'], _maxDoseCount);
         } else if (data.containsKey('Counts') && data['Counts'] is Map && data['Counts']['maxDoseCount'] != null) {
            final countsData = Map<String, dynamic>.from(data['Counts']);
            firebaseMaxDoseCount = _parseIntValue(countsData['maxDoseCount'], _maxDoseCount);
         }
         if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
             print("Max dose count updated from Firebase to: $firebaseMaxDoseCount");
             _maxDoseCount = firebaseMaxDoseCount;
             stateChanged = true;
             _lowDoseNotificationShown = false;
         }

        if (data.containsKey('Counts') && data['Counts'] is Map) {
          final countsData = Map<String, dynamic>.from(data['Counts']);
          firebaseDoseCount = _parseIntValue(countsData['doseCount'], _doseCount);
          firebaseCorrectCount = _parseIntValue(countsData['correctCount'], _correctCount);
          firebaseFalseCount = _parseIntValue(countsData['falseCount'], _falseCount);
          firebaseDailyDosesTaken = _parseIntValue(countsData['dailyDosesTaken'], _dailyDosesTaken);

          if (firebaseDoseCount != _doseCount) {
             _doseCount = firebaseDoseCount;
             print("Dose count updated from Firebase listener: $_doseCount");
             stateChanged = true;
          }
          if (firebaseCorrectCount != _correctCount) {
            _correctCount = firebaseCorrectCount;
            print("Correct count updated from Firebase listener: $_correctCount");
            stateChanged = true;
          }
          if (firebaseFalseCount != _falseCount) {
            _falseCount = firebaseFalseCount;
             print("False count updated from Firebase listener: $_falseCount");
            stateChanged = true;
          }
          if (firebaseDailyDosesTaken != _dailyDosesTaken) {
            _dailyDosesTaken = firebaseDailyDosesTaken;
             print("Daily doses taken updated from Firebase listener: $_dailyDosesTaken");
            stateChanged = true;
          }
        } else if (!isInitialFetch && _isConnected) {
            print("Warning: 'Counts' map not found or not a map in Firebase data.");
        }


        // --- NEW Dose Counting Logic ---
        if (!isInitialFetch && _isConnected) {
            if (!_doseActionInProgress && _doseCount > 0) {

                // --- Condition for CORRECT Dose ---
                // All sensors must be ABOVE their thresholds
                bool correctConditionMet =
                    newFSR1 > FSR1_THRESHOLD &&
                    newFSR2 > FSR2_THRESHOLD &&
                    newFSR3 > FSR3_THRESHOLD && // Uses the updated FSR3_THRESHOLD (2000)
                    newGyroZ > GYRO_Z_THRESHOLD;

                // --- Condition for FALSE Dose (UPDATED LOGIC) ---
                // 1. FSR3 MUST be greater than its threshold (2000)
                bool primaryFalseCondition = newFSR3 > FSR3_THRESHOLD; // FSR3 > 2000

                // 2. AT LEAST ONE of the secondary conditions must be met:
                //    - Gyro Z is less than 7 OR
                //    - FSR2 is less than 50 OR
                //    - FSR1 is less than 500
                bool secondaryFalseConditionMet =
                    newGyroZ < GYRO_Z_THRESHOLD || // Gyro Z below threshold?
                    newFSR2 < FSR2_THRESHOLD ||   // FSR2 below threshold?
                    newFSR1 < FSR1_THRESHOLD;   // FSR1 below threshold?

                // Final false condition: Primary AND (at least one Secondary)
                bool falseConditionMet = primaryFalseCondition && secondaryFalseConditionMet;


                // --- Determine if there was a relevant sensor change ---
                // This prevents triggering counts repeatedly if sensors stay in the same state.
                bool relevantSensorChange = (newFSR1 != oldFSR1 || newFSR2 != oldFSR2 || newFSR3 != oldFSR3 || newGyroZ != oldGyroZ);

                // --- Trigger Actions ---
                if (relevantSensorChange) {
                    if (correctConditionMet) {
                        print("CORRECT dose condition met. Updating Firebase.");
                        _doseActionInProgress = true;

                        final nextDoseCount = _doseCount - 1;
                        final nextCorrectCount = _correctCount + 1;
                        final nextDailyDosesTaken = _dailyDosesTaken + 1;

                        Map<String, Object> updates = {
                          'Counts/doseCount': nextDoseCount,
                          'Counts/correctCount': nextCorrectCount,
                          'Counts/dailyDosesTaken': nextDailyDosesTaken,
                        };

                        _dbRef.update(updates).then((_) {
                            print("Firebase updated for CORRECT dose.");
                        }).catchError((error) {
                            print("Error updating Firebase for CORRECT dose: $error");
                            _doseActionInProgress = false;
                        });
                        _startDoseActionResetTimer();

                    } else if (falseConditionMet) {
                        print("FALSE dose condition met (FSR3 > ${FSR3_THRESHOLD} AND one of GyroZ<${GYRO_Z_THRESHOLD} or FSR2<${FSR2_THRESHOLD} or FSR1<${FSR1_THRESHOLD}). Updating Firebase.");
                        _doseActionInProgress = true;

                        final nextDoseCount = _doseCount - 1;
                        final nextFalseCount = _falseCount + 1;

                        Map<String, Object> updates = {
                          'Counts/doseCount': nextDoseCount,
                          'Counts/falseCount': nextFalseCount,
                        };

                        _dbRef.update(updates).then((_) {
                            print("Firebase updated for FALSE dose.");
                        }).catchError((error) {
                            print("Error updating Firebase for FALSE dose: $error");
                            _doseActionInProgress = false;
                        });
                        _startDoseActionResetTimer();
                    }
                }
            }
        }


        // --- Buzzer Control Update (Listener Driven) ---
        if (data.containsKey('buzzerControl')) {
           final firebaseBuzzerControl = _parseIntValue(data['buzzerControl'], _buzzerControl);
            if (firebaseBuzzerControl != _buzzerControl) {
               print("Buzzer control updated from Firebase listener: $firebaseBuzzerControl");
               _buzzerControl = firebaseBuzzerControl;
               stateChanged = true;
            }
        }

        // --- Check for Low Dose Notification ---
        if ((_doseCount != oldDoseCount || _maxDoseCount != oldMaxDoseCount) && _maxDoseCount > 0) {
           final int threshold = (_maxDoseCount * 0.2).floor();
           print("Checking notification: Dose=$_doseCount, Max=$_maxDoseCount, Threshold=$threshold, Shown=$_lowDoseNotificationShown");

           if (_doseCount <= threshold && !_lowDoseNotificationShown) {
             _notificationService.showLowDoseNotification(_doseCount, _maxDoseCount);
             _lowDoseNotificationShown = true;
             print("Low dose notification triggered.");
           }
           else if (_doseCount > threshold && _lowDoseNotificationShown) {
             print("Resetting notification flag as dose count is above threshold.");
             _lowDoseNotificationShown = false;
             _notificationService.cancelNotification(0);
           }
        }
        // --- End Notification Check ---

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
          }
     }
  }

  void _startDoseActionResetTimer() {
    _doseActionResetTimer?.cancel();
    _doseActionResetTimer = Timer(const Duration(seconds: 3), () {
        print("Resetting dose action flag.");
        _doseActionInProgress = false;
    });
  }

  int _parseIntValue(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  double _parseDoubleValue(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  Future<void> _updateBuzzerControl() async {
     if (!_isConnected) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot control buzzer: Offline')));
       return;
     }
     final nextBuzzerState = _buzzerControl == 0 ? 29 : 0;
     try {
        print("Attempting to set buzzerControl to $nextBuzzerState");
        await _dbRef.update({'buzzerControl': nextBuzzerState});
        print("Firebase buzzerControl update initiated.");

        _buzzerResetTimer?.cancel();
        if (nextBuzzerState == 29) {
           _buzzerResetTimer = Timer(const Duration(seconds: 5), () async {
             if (_buzzerControl == 29 && _isConnected && mounted) {
                 try {
                    print("Auto-resetting buzzerControl to 0");
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

 void _editDoseCount() {
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
               suffixText: '/ $_maxDoseCount',
               border: const OutlineInputBorder(),
             ),
           ),
           actions: [
             TextButton( onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel'),),
             TextButton(
               onPressed: () async {
                 final newDoseCountStr = newDoseCountController.text;
                 final newDoseCountInt = int.tryParse(newDoseCountStr);

                 if (newDoseCountInt == null || newDoseCountInt < 0 || newDoseCountInt > _maxDoseCount) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Dose count must be between 0 and $_maxDoseCount')));
                    return;
                 }
                 if (newDoseCountInt == _doseCount) {
                    Navigator.of(context).pop();
                    return;
                 }

                 print("Attempting manual dose count update to $newDoseCountInt");
                 try {
                     await _dbRef.update({'Counts/doseCount': newDoseCountInt});
                     print("Manual dose count update successful.");
                      final tempOldDose = _doseCount;
                      _doseCount = newDoseCountInt;
                       if (_maxDoseCount > 0) {
                           final int threshold = (_maxDoseCount * 0.2).floor();
                           if (_doseCount <= threshold && !_lowDoseNotificationShown) {
                               _notificationService.showLowDoseNotification(_doseCount, _maxDoseCount);
                               _lowDoseNotificationShown = true;
                           } else if (_doseCount > threshold && _lowDoseNotificationShown) {
                               _lowDoseNotificationShown = false;
                               _notificationService.cancelNotification(0);
                           }
                       }
                     Navigator.of(context).pop();
                 } catch (error) {
                     print("Error manually updating dose count: $error");
                     if (mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Error saving dose count: $error'))
                       );
                     }
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
    _doseActionResetTimer?.cancel();
    _buzzerResetTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget mainContent = RefreshIndicator(
       onRefresh: _initializeDatabase,
       child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            DoseCounter(
              doseCount: _doseCount,
              maxDoseCount: _maxDoseCount,
              onEdit: _editDoseCount,
            ),
            const SizedBox(height: 24),
            StatsGrid(
              dailyDosesTaken: _dailyDosesTaken,
              dailyDoseLimit: _dailyDoseLimit,
              correctCount: _correctCount,
              falseCount: _falseCount,
              maxDoseCount: _maxDoseCount,
            ),
            const SizedBox(height: 24),
            BuzzerControl(
              buzzerControl: _buzzerControl,
              onToggle: _updateBuzzerControl,
            ),
            const SizedBox(height: 30),
            _buildNavigationButton(
              context: context,
              text: 'View FSR & History',
              targetScreen: const FirebaseDataScreen2(), // Adjust name if needed
            ),
            const SizedBox(height: 15),
            _buildNavigationButton(
              context: context,
              text: 'View Sensor Graphs',
              targetScreen: const GraphScreen(),
            ),
            const SizedBox(height: 30),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Smart Inhaler'),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        actions: [
          ConnectionStatusIndicator(isConnected: _isConnected),
        ],
      ),
      body: SafeArea(
        child: ConnectionStatusHandler(
          isInitializing: _isInitializing,
          isConnected: _isConnected,
          onRetry: _initializeDatabase,
          child: mainContent,
        ),
      ),
    );
  }

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