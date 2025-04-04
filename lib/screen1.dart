import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dose_counter.dart';
import 'graphscreen.dart';
import 'test.dart'; // Import screen 2 (assuming this is the correct name)
import 'buzzer_control.dart'; // Import BuzzerControl

// --- Constants (Used by widgets remaining in this file) ---
const Color _motionSensorCardColor = Color(0xFFB2EBF2); // Light Teal
const Color _buzzerButtonColor = Color(0xFFFFAB91); // Warm Coral (If used by BuzzerControl internally)
const Color _textColor = Color(0xFF212121); // Used by MotionSensorNumericalData & AppBar
const double _cardCornerRadius = 12.0; // Used by MotionSensorNumericalData
const double _cardElevation = 4.0; // Used by MotionSensorNumericalData

// --- Motion Sensor Data Widget (Numerical Values Only) ---
class MotionSensorNumericalData extends StatelessWidget {
  final double accelX;
  final double accelY;
  final double accelZ;
  final double gyroX;
  final double gyroY;
  final double gyroZ;
  final double temp;

  const MotionSensorNumericalData({
    Key? key,
    required this.accelX,
    required this.accelY,
    required this.accelZ,
    required this.gyroX,
    required this.gyroY,
    required this.gyroZ,
    required this.temp,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: _cardElevation,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_cardCornerRadius),
      ),
      color: _motionSensorCardColor,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Motion Sensor Data', // Simplified title
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 12),
            _buildDataRow('Accel X:', accelX.toStringAsFixed(3)),
            _buildDataRow('Accel Y:', accelY.toStringAsFixed(3)),
            _buildDataRow('Accel Z:', accelZ.toStringAsFixed(3)),
             const Divider(height: 16, thickness: 1), // Separator
            _buildDataRow('Gyro X:', gyroX.toStringAsFixed(3)),
            _buildDataRow('Gyro Y:', gyroY.toStringAsFixed(3)),
            _buildDataRow('Gyro Z:', gyroZ.toStringAsFixed(3)),
            const Divider(height: 16, thickness: 1), // Separator
            _buildDataRow('Temperature:', '${temp.toStringAsFixed(1)} °C'), // Added space
          ],
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
             // fontWeight: FontWeight.w500, // Normal weight might be better here
              color: _textColor,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
}


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
  bool _isInitializing = true; // Track initial connection attempt

  // Variables for dose tracking
  int _doseCount = 90; // Default value
  int _maxDoseCount = 100; // Default value

  // Variables to store MPU6050 data
  double _accelX = 0.0;
  double _accelY = 0.0;
  double _accelZ = 0.0;
  double _gyroX = 0.0;
  double _gyroY = 0.0;
  double _gyroZ = 0.0;
  double _temp = 0.0;

  // Variables for FSR data (Still needed for dose detection logic)
  int _fsrSensor1 = 0;
  int _fsrSensor2 = 0;
  int _fsrSensor3 = 0;

  // Buzzer control value
  int _buzzerControl = 0;

  bool _doseCounted = false; // Flag to prevent multiple counts
  Timer? _doseCountResetTimer; // Timer to reset the flag
  Timer? _buzzerResetTimer; // Timer for auto-resetting buzzer

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    setState(() {
       _isInitializing = true; // Start initialization indicator
    });
    try {
      FirebaseDatabase database = FirebaseDatabase.instance;
      // Ensure your databaseURL is correct
      database.databaseURL =
          'https://smart-inhaler-db-default-rtdb.asia-southeast1.firebasedatabase.app/';

      _dbRef = database.ref();
      print('Database reference created: ${_dbRef.path}');

      // Attempt to get initial values once
      try {
         // Use timeout to prevent hanging indefinitely if DB is unreachable
         final snapshot = await _dbRef.get().timeout(const Duration(seconds: 10));
         if (snapshot.exists && snapshot.value != null) {
            print('Initial data fetched successfully.');
            _parseData(snapshot.value); // Parse initial data
             // Set connected state only if parsing is successful and mounted
            if(mounted) {
              setState(() {
                _isConnected = true;
              });
            }
         } else {
            print('Initial data fetch: No data found at root or snapshot is null.');
            // Keep default values if no initial data
            if (mounted) {
               setState(() {
                 _isConnected = false; // Explicitly set disconnected if initial fetch fails
               });
            }
         }
      } catch(e) {
          print('Error fetching initial data: $e');
          // Keep defaults, show error later if subscription also fails
          if (mounted) {
            setState(() {
              _isConnected = false;
            });
          }
      } finally {
         // Ensure initializing is set to false after initial fetch attempt
         if (mounted) {
            setState(() {
              _isInitializing = false;
            });
         }
      }


      // Listen for subsequent value changes only if initialization didn't fail catastrophically
      if(_dbRef != null) { // Check if dbRef was successfully initialized
          _subscription?.cancel(); // Cancel any previous subscription
          _subscription = _dbRef.onValue.listen(
            (DatabaseEvent event) {
              // print('Data received: ${event.snapshot.value}'); // Uncomment for debugging
              if (event.snapshot.value != null) {
                _parseData(event.snapshot.value);
                if (!_isConnected && mounted) {
                   setState(() {
                     _isConnected = true; // Mark as connected once data flows
                   });
                }
              } else {
                print('No data received from Firebase stream (snapshot value is null)');
                // Consider adding a timeout or counter here to set _isConnected=false
                // if no data is received for a certain period.
              }
            },
            onError: (error) {
              print('Database stream error: $error');
              if (mounted) { // Check if widget is still in the tree
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Firebase connection error: ${error.toString()}')),
                );
                setState(() {
                  _isConnected = false;
                   _isInitializing = false; // Ensure initializing is false on error
                });
              }
            },
            onDone: () {
              print('Database connection stream closed');
               if (mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                   const SnackBar(content: Text('Firebase connection closed')),
                 );
                 setState(() {
                   _isConnected = false;
                   _isInitializing = false; // Ensure initializing is false when done
                 });
               }
            },
          );
      } else {
          print("Database reference is null, cannot listen for changes.");
           if (mounted) {
             setState(() {
               _isConnected = false;
               _isInitializing = false;
             });
           }
      }


    } catch (e) {
      print('Error setting up database reference: $e');
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(content: Text('Error setting up Firebase: ${e.toString()}')),
         );
         setState(() {
           _isConnected = false;
           _isInitializing = false; // Initialization failed
         });
       }
    }
  }

  // Centralized data parsing logic
 void _parseData(dynamic rawData) {
     if (rawData == null || rawData is! Map) {
        print('Invalid or null data received for parsing.');
        return; // Exit if data is not a Map or is null
     }

     try {
        final data = Map<String, dynamic>.from(rawData);
        bool stateChanged = false; // Track if any state update is needed

        // --- FSR and Dose Counting Logic ---
        if (data.containsKey('FSR') && data['FSR'] is Map) {
          final fsrData = Map<String, dynamic>.from(data['FSR']);
          final oldFSR1 = _fsrSensor1;
          final oldFSR2 = _fsrSensor2;
          final oldFSR3 = _fsrSensor3;

          // Update FSR values safely
          final newFSR1 = _parseIntValue(fsrData['sensor1'], _fsrSensor1); // Pass current value as default
          final newFSR2 = _parseIntValue(fsrData['sensor2'], _fsrSensor2);
          final newFSR3 = _parseIntValue(fsrData['sensor3'], _fsrSensor3);

          // Threshold for detecting press
          const int pressThreshold = 50; // Define threshold clearly

          // Check for dose decrement condition: Transition from NOT all pressed to ALL pressed
          bool allPressedNow = newFSR1 > pressThreshold && newFSR2 > pressThreshold && newFSR3 > pressThreshold;
          bool notAllPressedBefore = oldFSR1 <= pressThreshold || oldFSR2 <= pressThreshold || oldFSR3 <= pressThreshold;

          if (allPressedNow && notAllPressedBefore && _doseCount > 0 && !_doseCounted) {
             print("Dose condition met! FSRs: $newFSR1, $newFSR2, $newFSR3. Decrementing count.");
             _doseCounted = true; // Set flag immediately
             final newDoseCount = _doseCount - 1;

             // Update Firebase first
             _dbRef.update({'doseCount': newDoseCount}).then((_) {
                print("Firebase doseCount updated to $newDoseCount");
                // Update local state only after successful Firebase update
                // No direct setState here, handled later if doseCount changes
             }).catchError((error) {
                print("Error updating Firebase doseCount: $error");
                 _doseCounted = false; // Reset flag on error
             });

             // Reset the flag after a delay to prevent rapid counts
             _doseCountResetTimer?.cancel(); // Cancel previous timer if any
             _doseCountResetTimer = Timer(const Duration(seconds: 2), () {
                 print("Resetting dose count flag.");
                 _doseCounted = false;
             });
          }

          // Update local FSR state if values changed
          if (newFSR1 != _fsrSensor1 || newFSR2 != _fsrSensor2 || newFSR3 != _fsrSensor3) {
             _fsrSensor1 = newFSR1;
             _fsrSensor2 = newFSR2;
             _fsrSensor3 = newFSR3;
             stateChanged = true; // Mark state changed (though FSR isn't directly displayed)
          }
        }

        // --- Dose Count Update (from Firebase) ---
        if (data.containsKey('doseCount')) {
           final firebaseDoseCount = _parseIntValue(data['doseCount'], _doseCount);
           if (firebaseDoseCount != _doseCount) {
              _doseCount = firebaseDoseCount;
              stateChanged = true;
           }
        }

        // --- Max Dose Count Update (from Firebase) ---
         if (data.containsKey('maxDoseCount')) {
           final firebaseMaxDoseCount = _parseIntValue(data['maxDoseCount'], _maxDoseCount);
           // Ensure max dose count is positive
           if (firebaseMaxDoseCount != _maxDoseCount && firebaseMaxDoseCount > 0) {
              _maxDoseCount = firebaseMaxDoseCount;
              stateChanged = true;
           }
        }

        // --- Buzzer Control Update (from Firebase) ---
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

          // Extract accelerometer data
          if (mpuData.containsKey('accelerometer') && mpuData['accelerometer'] is Map) {
            final accelData = Map<String, dynamic>.from(mpuData['accelerometer']);
            tempAccelX = _parseDoubleValue(accelData['x'], _accelX);
            tempAccelY = _parseDoubleValue(accelData['y'], _accelY);
            tempAccelZ = _parseDoubleValue(accelData['z'], _accelZ);
          }

          // Extract gyroscope data
          if (mpuData.containsKey('gyroscope') && mpuData['gyroscope'] is Map) {
            final gyroData = Map<String, dynamic>.from(mpuData['gyroscope']);
             tempGyroX = _parseDoubleValue(gyroData['x'], _gyroX);
             tempGyroY = _parseDoubleValue(gyroData['y'], _gyroY);
             tempGyroZ = _parseDoubleValue(gyroData['z'], _gyroZ);
          }

          // Extract temperature
          if (mpuData.containsKey('temp')) {
             tempTemp = _parseDoubleValue(mpuData['temp'], _temp);
          }

          // Check if any MPU value actually changed
          if (tempAccelX != _accelX || tempAccelY != _accelY || tempAccelZ != _accelZ ||
              tempGyroX != _gyroX || tempGyroY != _gyroY || tempGyroZ != _gyroZ ||
              tempTemp != _temp) {
              _accelX = tempAccelX;
              _accelY = tempAccelY;
              _accelZ = tempAccelZ;
              _gyroX = tempGyroX;
              _gyroY = tempGyroY;
              _gyroZ = tempGyroZ;
              _temp = tempTemp;
              stateChanged = true;
          }
        }

        // --- Apply state changes if necessary ---
        if (stateChanged && mounted) {
           setState(() {
              // This single setState call updates the UI with all changed values
           });
        }

        // Final connection status update (redundant if already connected, but safe)
         if (!_isConnected && mounted) {
             setState(() {
                _isConnected = true;
             });
         }

     } catch (e, stacktrace) { // Catch potential errors during parsing
         print('Error parsing data: $e');
         print('Problematic data chunk: $rawData'); // Log the raw data that caused the error
         print('Stacktrace: $stacktrace');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error processing incoming data: ${e.toString()}')),
            );
          }
          // Decide if you want to set _isConnected to false here based on parsing errors
          // setState(() => _isConnected = false );
     }
  }

  // Helper method to parse int values safely, returning a default if parsing fails
  int _parseIntValue(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
  }

   // Helper method to parse double values safely, returning a default if parsing fails
  double _parseDoubleValue(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString()) ?? defaultValue;
  }


  // Function to update buzzer control value in Firebase
  Future<void> _updateBuzzerControl() async {
     if (!_isConnected) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Not connected to inhaler.')));
        return;
     }
     // Check if dbRef is initialized
     if (_dbRef == null) {
        print("Cannot update buzzer: Database reference is null.");
         ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Database connection not ready.')));
        return;
     }

     final nextBuzzerState = _buzzerControl == 0 ? 29 : 0; // Toggle between 0 and 29

     try {
        print('Attempting to set buzzerControl to $nextBuzzerState');
        await _dbRef.update({'buzzerControl': nextBuzzerState});
        print('Buzzer control update sent successfully.');

        // Optimistic UI update: Update local state immediately after sending
        // The listener will correct it if Firebase reports a different value later.
        if (mounted) {
           setState(() {
             _buzzerControl = nextBuzzerState;
           });
        }

        // Cancel any existing auto-reset timer
        _buzzerResetTimer?.cancel();

        // If activating (setting to 29), start auto-reset timer
        if (nextBuzzerState == 29) {
           _buzzerResetTimer = Timer(const Duration(seconds: 5), () async {
             // Check if buzzer is *still* active (value hasn't changed back) before resetting
             // Also check connection and dbRef status again
             if (_buzzerControl == 29 && _isConnected && _dbRef != null && mounted) {
                 print('Auto-resetting buzzer control to 0');
                 try {
                    await _dbRef.update({'buzzerControl': 0});
                    // Update local state on successful auto-reset
                    if(mounted) setState(() => _buzzerControl = 0);
                 } catch (e) {
                     print('Error auto-resetting buzzer control: $e');
                     if(mounted) {
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Error auto-resetting buzzer: ${e.toString()}')),
                       );
                     }
                 }
             } else {
                 print('Buzzer state changed or disconnected before auto-reset timer fired.');
             }
           });
        }
     } catch (e) {
        print('Error updating buzzer control: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error updating buzzer: ${e.toString()}')),
          );
           // Optional: Revert optimistic UI update on error
           // setState(() { _buzzerControl = (_buzzerControl == 0 ? 29 : 0); }); // Revert back
        }
     }
  }

  // Function to edit dose count
 void _editDoseCount() {
     // Allow editing even if temporarily disconnected, but check dbRef
     if (_dbRef == null) {
         ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Cannot edit dose count: Database not initialized.')));
         return;
     }
      if (!_isConnected && !_isInitializing) {
         ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Warning: Editing while offline. Changes might not save immediately.')));
         // Allow proceeding, but maybe warn the user
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
               hintText: 'Current: $_doseCount', // Show current value clearly
               suffixText: '/ $_maxDoseCount', // Show max doses
               border: const OutlineInputBorder(),
             ),
             // InputFormatters can be used for better validation
             // inputFormatters: [FilteringTextInputFormatter.digitsOnly],
           ),
           actions: [
             TextButton(
               onPressed: () => Navigator.of(context).pop(),
               child: const Text('Cancel'),
             ),
             TextButton(
               onPressed: () {
                 final newDoseCountStr = newDoseCountController.text;
                 final newDoseCountInt = int.tryParse(newDoseCountStr);

                 if (newDoseCountInt == null) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     const SnackBar(content: Text('Please enter a valid whole number.')),
                   );
                   return; // Keep dialog open
                 }
                 if (newDoseCountInt < 0 || newDoseCountInt > _maxDoseCount) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text('Dose count must be between 0 and $_maxDoseCount.')),
                   );
                   return; // Keep dialog open
                 }

                 // Prevent saving if the value hasn't changed
                 if (newDoseCountInt == _doseCount) {
                    Navigator.of(context).pop(); // Just close if no change
                    return;
                 }

                 // Update Firebase
                 _dbRef.update({'doseCount': newDoseCountInt}).then((_) {
                    print("Manual dose count update to $newDoseCountInt successful.");
                    // Update local state only on success
                    // No need for setState here as the listener should pick it up,
                    // but you could add it for immediate visual feedback if the listener is slow.
                    // if (mounted) { setState(() => _doseCount = newDoseCountInt); }
                    Navigator.of(context).pop(); // Close dialog on success
                 }).catchError((error) {
                     print("Error manually updating dose count: $error");
                     if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Failed to save dose count: $error')),
                       );
                     }
                      // Don't close dialog on error
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
    // It's generally good practice to close the database connection if the app is completely closing,
    // but Firebase handles this reasonably well. Avoid closing if just disposing the widget.
    // FirebaseDatabase.instance.goOffline(); // Use with caution
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
                    const Text(
                      'Inhaler Offline',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                     const Text(
                       'Check device power/connection and internet access. Data shown may be outdated.',
                       textAlign: TextAlign.center,
                       style: TextStyle(color: Colors.grey),
                    ),
                    const SizedBox(height: 25),
                    ElevatedButton.icon(
                       icon: const Icon(Icons.refresh),
                       label: const Text('Retry Connection'),
                       onPressed: _initializeDatabase, // Re-run initialization
                       style: ElevatedButton.styleFrom(
                         // backgroundColor: Colors.blueAccent,
                         // foregroundColor: Colors.white,
                         padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)
                       ),
                    )
                 ],
              ),
           ),
        );
     } else {
       // --- Connected State ---
       bodyContent = SingleChildScrollView(
         physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling even if content fits
         padding: const EdgeInsets.all(16.0), // Padding around the scroll view content
         child: Column(
           mainAxisAlignment: MainAxisAlignment.start,
           children: [
              // --- Use the imported DoseCounter widget ---
              DoseCounter(
                doseCount: _doseCount,
                maxDoseCount: _maxDoseCount,
                onEdit: _editDoseCount,
              ),
              const SizedBox(height: 24),
              MotionSensorNumericalData(
                accelX: _accelX,
                accelY: _accelY,
                accelZ: _accelZ,
                gyroX: _gyroX,
                gyroY: _gyroY,
                gyroZ: _gyroZ,
                temp: _temp,
              ),
              const SizedBox(height: 24),
              BuzzerControl(
                buzzerControl: _buzzerControl,
                onToggle: _updateBuzzerControl,
              ),
              const SizedBox(height: 30),
               // --- Navigation Buttons ---
               _buildNavigationButton(
                 context: context,
                 text: 'View FSR & History', // Example text
                 targetScreen: const FirebaseDataScreen2(), // Your Screen 2
               ),
               const SizedBox(height: 15),
               _buildNavigationButton(
                 context: context,
                 text: 'View Sensor Graphs', // Example text
                 targetScreen: const GraphScreen(), // Your Graph Screen
               ),
               const SizedBox(height: 20), // Bottom padding inside scroll view
             ],
           ),
       );
     }

    return Scaffold(
      backgroundColor: Colors.grey[100], // Light background
      appBar: AppBar(
        title: const Text('Smart Inhaler'), // Simplified title
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        actions: [
          // Connection status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Tooltip( // Add tooltip for clarity
                message: _isConnected ? 'Connected to Firebase' : 'Disconnected from Firebase',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                     color: _isConnected ? Colors.green[100] : Colors.red[100],
                     borderRadius: BorderRadius.circular(10),
                     border: Border.all(
                        color: _isConnected ? Colors.green[300]! : Colors.red[300]!,
                        width: 0.5
                     )
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                         _isConnected ? Icons.wifi : Icons.wifi_off,
                         color: _isConnected ? Colors.green[800] : Colors.red[800],
                         size: 16,
                       ),
                       const SizedBox(width: 4),
                        Text(
                         _isConnected ? 'Online' : 'Offline', // Shorter text
                         style: TextStyle(
                            color: _isConnected ? Colors.green[800] : Colors.red[800],
                            fontSize: 12,
                            fontWeight: FontWeight.bold
                         ),
                       ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea( // Use SafeArea
        child: bodyContent, // Display the appropriate content based on state
      ),
    );
  }

 // Helper method for creating styled navigation buttons
 Widget _buildNavigationButton({
    required BuildContext context,
    required String text,
    required Widget targetScreen,
 }) {
    return ElevatedButton(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
        );
      },
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(double.infinity, 50), // Full width, fixed height
        // backgroundColor: Theme.of(context).primaryColor, // Use theme color
        // foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)
      ),
      child: Text(text),
    );
 }
}