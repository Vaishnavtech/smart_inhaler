import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

class FirebaseDataScreen2 extends StatefulWidget {
  const FirebaseDataScreen2({super.key});

  @override
  _FirebaseDataScreen2State createState() => _FirebaseDataScreen2State();
}

class _FirebaseDataScreen2State extends State<FirebaseDataScreen2> {
  late DatabaseReference _dbRef;
  StreamSubscription<DatabaseEvent>? _subscription;
  String _status = 'Initializing...';

  // Variables to store MPU6050 data
  String _accelX = '0.0';
  String _accelY = '0.0';
  String _accelZ = '0.0';
  String _gyroX = '0.0';
  String _gyroY = '0.0';
  String _gyroZ = '0.0';
  double _temp = 0.0;

  // Variables for FSR data
  int _fsrValue = 0;
  int _fsrSensor1 = 0;
  int _fsrSensor2 = 0;
  int _fsrSensor3 = 0;

  // Counter for when all FSR sensors are non-zero
  int _triggerCount = 0;

  // Buzzer control value
  int _buzzerControl = 0;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      // Initialize database reference with the specific URL
      FirebaseDatabase database = FirebaseDatabase.instance;
      database.databaseURL =
          'https://smart-inhaler-db-default-rtdb.asia-southeast1.firebasedatabase.app/';

      // Set the reference to the root
      _dbRef = database.ref();
      print('Database reference created');

      // Set up listener for the root node
      _subscription = _dbRef.onValue.listen(
        (DatabaseEvent event) {
          print('Data received: ${event.snapshot.value}');
          if (event.snapshot.value != null) {
            try {
              // Parse the entire data structure
              final data = event.snapshot.value as Map<dynamic, dynamic>;

              // Get FSR values
              if (data['FSR'] != null) {
                final fsrData = data['FSR'] as Map<dynamic, dynamic>;
                final oldFSR1 = _fsrSensor1;
                final oldFSR2 = _fsrSensor2;
                final oldFSR3 = _fsrSensor3;

                setState(() {
                  _fsrSensor1 = _parseIntValue(fsrData['sensor1']);
                  _fsrSensor2 = _parseIntValue(fsrData['sensor2']);
                  _fsrSensor3 = _parseIntValue(fsrData['sensor3']);
                  _fsrValue = _fsrSensor1 +
                      _fsrSensor2 +
                      _fsrSensor3; // Sum for backward compatibility

                  // Increment counter when all FSR sensors go from any state to all non-zero
                  bool allNonZeroNow =
                      _fsrSensor1 > 0 && _fsrSensor2 > 0 && _fsrSensor3 > 0;
                  bool anyZeroBefore =
                      oldFSR1 == 0 || oldFSR2 == 0 || oldFSR3 == 0;

                  if (allNonZeroNow && anyZeroBefore) {
                    _triggerCount++;
                  }
                });
              }

              // Get buzzer control value
              if (data['buzzerControl'] != null) {
                setState(() {
                  _buzzerControl = _parseIntValue(data['buzzerControl']);
                });
              }

              // Get MPU data
              if (data['MPU'] != null) {
                final mpuData = data['MPU'] as Map<dynamic, dynamic>;

                // Extract accelerometer data
                if (mpuData['accelerometer'] != null) {
                  final accelData =
                      mpuData['accelerometer'] as Map<dynamic, dynamic>;
                  setState(() {
                    _accelX = accelData['x']?.toString() ?? '0.0';
                    _accelY = accelData['y']?.toString() ?? '0.0';
                    _accelZ = accelData['z']?.toString() ?? '0.0';
                  });
                }

                // Extract gyroscope data
                if (mpuData['gyroscope'] != null) {
                  final gyroData =
                      mpuData['gyroscope'] as Map<dynamic, dynamic>;
                  setState(() {
                    _gyroX = gyroData['x']?.toString() ?? '0.0';
                    _gyroY = gyroData['y']?.toString() ?? '0.0';
                    _gyroZ = gyroData['z']?.toString() ?? '0.0';
                  });
                }

                // Extract temperature
                if (mpuData['temp'] != null) {
                  final tempValue = mpuData['temp'];
                  setState(() {
                    if (tempValue is int) {
                      _temp = tempValue.toDouble();
                    } else if (tempValue is double) {
                      _temp = tempValue;
                    } else {
                      _temp = double.tryParse(tempValue.toString()) ?? 0.0;
                    }
                  });
                }
              }

              setState(() {
                _status = 'Connected';
              });
            } catch (e) {
              print('Error parsing data: $e');
              setState(() {
                _status = 'Error parsing data: $e';
              });
            }
          } else {
            print('No data received from Firebase');
            setState(() {
              _status = 'No data received from Firebase';
            });
          }
        },
        onError: (error) {
          print('Database error: $error');
          setState(() {
            _status = 'Error: $error';
          });
        },
        onDone: () {
          print('Database connection closed');
          setState(() {
            _status = 'Connection closed';
          });
        },
      );

      print('Listener set up');
    } catch (e) {
      print('Error setting up database: $e');
      setState(() {
        _status = 'Setup error: $e';
      });
    }
  }

  // Helper method to parse int values from different data types
  int _parseIntValue(dynamic value) {
    if (value is int) {
      return value;
    } else if (value is double) {
      return value.toInt();
    } else {
      return int.tryParse(value.toString()) ?? 0;
    }
  }

// Function to update buzzer control value in Firebase
  Future<void> _updateBuzzerControl() async {
    try {
      await _dbRef.update({
        'buzzerControl': 29,
      });
      setState(() {
        _buzzerControl = 29;
      });
      print('Buzzer control updated to 29');

      // Add 10-second timer to reset buzzer to 0
      Timer(const Duration(seconds: 5), () async {
        await _dbRef.update({
          'buzzerControl': 0,
        });
        setState(() {
          _buzzerControl = 0;
        });
        print('Buzzer control reset to 0 after 10 seconds');
      });
    } catch (e) {
      print('Error updating buzzer control: $e');
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Inhaler Sensor Data'),
      ),
      body: SingleChildScrollView( // Add SingleChildScrollView Here
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Status indicator
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: _status == 'Connected'
                        ? Colors.green.shade100
                        : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    _status,
                    style: TextStyle(
                      color: _status == 'Connected'
                          ? Colors.green.shade800
                          : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // FSR Counter and Buzzer Control Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // FSR Trigger Counter
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8.0),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.countertops,
                              color: Colors.amber.shade700, size: 28),
                          const SizedBox(height: 8),
                          const Text(
                            'Trigger Count',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '$_triggerCount',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Buzzer Control Button
                    Column(
                      children: [
                        const Text(
                          'Buzzer Control',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _updateBuzzerControl,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _buzzerControl == 29
                                  ? Colors.red
                                  : Colors.grey.shade300,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.volume_up,
                                color: Colors.white,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // FSR Sensors Display
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Force Sensitive Resistors',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildFSRDisplay(1, _fsrSensor1),
                            _buildFSRDisplay(2, _fsrSensor2),
                            _buildFSRDisplay(3, _fsrSensor3),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Temperature display
                Container(
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8.0),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.thermostat,
                          color: Colors.red.shade400, size: 32),
                      const SizedBox(width: 12),
                      Text(
                        'Temperature: ${_temp.toStringAsFixed(1)}°C',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Acceleration and Gyroscope Tables
                Card(
                  elevation: 4,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Text(
                          'Motion Sensor Data',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Accelerometer Table
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8.0),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade100,
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(8.0),
                                    topRight: Radius.circular(8.0),
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Sensor',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'X',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'Y',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        'Z',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Accelerometer row
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12.0),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Accelerometer',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _accelX,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _accelY,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _accelZ,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Gyroscope row
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12.0),
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: Colors.grey.shade300),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Expanded(
                                      flex: 2,
                                      child: Text(
                                        'Gyroscope',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _gyroX,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _gyroY,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Expanded(
                                      flex: 1,
                                      child: Text(
                                        _gyroZ,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper widget to build FSR sensor display
  Widget _buildFSRDisplay(int sensorNumber, int value) {
    Color fillColor =
        value > 0 ? Colors.green.shade400 : Colors.grey.shade300;

    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(color: Colors.grey.shade400, width: 2),
          ),
          child: Center(
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fillColor,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Sensor $sensorNumber',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          '$value',
          style: const TextStyle(fontSize: 16),
        ),
      ],
    );
  }
}