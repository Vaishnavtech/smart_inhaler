import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    print('Error initializing Firebase: $e');
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: const FirebaseDataScreen(),
    );
  }
}

class FirebaseDataScreen extends StatefulWidget {
  const FirebaseDataScreen({super.key});

  @override
  _FirebaseDataScreenState createState() => _FirebaseDataScreenState();
}

class _FirebaseDataScreenState extends State<FirebaseDataScreen> {
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

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    try {
      // Initialize database reference with the specific URL
      FirebaseDatabase database = FirebaseDatabase.instance;
      database.databaseURL = 'https://smart-inhaler-db-default-rtdb.asia-southeast1.firebasedatabase.app/';
      _dbRef = database.ref('MPU');
      print('Database reference created');

      // Set up listener
      _subscription = _dbRef.onValue.listen(
        (DatabaseEvent event) {
          print('Data received: ${event.snapshot.value}');
          if (event.snapshot.value != null) {
            try {
              // Parse the MPU data
              final mpuData = event.snapshot.value as Map<dynamic, dynamic>;
              
              // Extract accelerometer data
              if (mpuData['accelerometer'] != null) {
                final accelData = mpuData['accelerometer'] as Map<dynamic, dynamic>;
                setState(() {
                  _accelX = accelData['x'].toString();
                  _accelY = accelData['y'].toString();
                  _accelZ = accelData['z'].toString();
                });
              }
              
              // Extract gyroscope data
              if (mpuData['gyroscope'] != null) {
                final gyroData = mpuData['gyroscope'] as Map<dynamic, dynamic>;
                setState(() {
                  _gyroX = gyroData['x'].toString();
                  _gyroY = gyroData['y'].toString();
                  _gyroZ = gyroData['z'].toString();
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
              
              setState(() {
                _status = 'Connected';
              });
            } catch (e) {
              print('Error parsing MPU data: $e');
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

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MPU6050 Sensor Data'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Status indicator
              Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: _status == 'Connected' ? Colors.green.shade100 : Colors.red.shade100,
                  borderRadius: BorderRadius.circular(8.0),
                ),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _status == 'Connected' ? Colors.green.shade800 : Colors.red.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 30),
              
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
                    Icon(Icons.thermostat, color: Colors.red.shade400, size: 32),
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
              
              const SizedBox(height: 30),
              
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
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
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
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'X',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'Y',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 1,
                                    child: Text(
                                      'Z',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Accelerometer row
                            Container(
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
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
                                      style: TextStyle(fontWeight: FontWeight.w500),
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
                              padding: const EdgeInsets.symmetric(vertical: 12.0),
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
                                      style: TextStyle(fontWeight: FontWeight.w500),
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
    );
  }
}