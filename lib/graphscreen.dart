// lib/graph_screen.dart
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'package:fl_chart/fl_chart.dart'; // For graphs

// --- Constants (Moved here as they are specific to this screen's UI) ---
const Color _motionSensorCardColor = Color(0xFFB2EBF2); // Light Teal
const Color _textColor = Color(0xFF212121);
const double _cardCornerRadius = 12.0;
const double _cardElevation = 4.0;

class GraphScreen extends StatefulWidget {
  const GraphScreen({Key? key}) : super(key: key);

  @override
  _GraphScreenState createState() => _GraphScreenState();
}

class _GraphScreenState extends State<GraphScreen> {
  late DatabaseReference _dbRef;
  StreamSubscription<DatabaseEvent>? _subscription;
  bool _isConnected = false;
  bool _isInitializing = true;

  // Variables to store MPU6050 data for the graphs
  final List<FlSpot> _accelXData = [];
  final List<FlSpot> _accelYData = [];
  final List<FlSpot> _accelZData = [];
  final List<FlSpot> _gyroXData = [];
  final List<FlSpot> _gyroYData = [];
  final List<FlSpot> _gyroZData = [];
  double _temp = 0.0;
  int _timeCounter = 0; // Use a counter for FlSpot x-axis

  // Limit the number of data points shown
  final int dataLimit = 50;

  @override
  void initState() {
    super.initState();
    _initializeDatabase();
  }

  Future<void> _initializeDatabase() async {
    setState(() {
      _isInitializing = true;
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
        final snapshot = await _dbRef.get();
        if (snapshot.exists && snapshot.value != null) {
          print('Initial data fetched successfully.');
          _parseData(snapshot.value); // Parse initial data
          setState(() {
            _isConnected = true; // Assume connected if initial fetch works
          });
        } else {
          print('Initial data fetch: No data found at root.');
        }
      } catch (e) {
        print('Error fetching initial data: $e');
      }

      _subscription = _dbRef.onValue.listen((DatabaseEvent event) {
        if (event.snapshot.value != null) {
          _parseData(event.snapshot.value);
          setState(() {
            _isConnected = true;
          });
        } else {
          print('No data received from Firebase stream');
        }
      }, onError: (error) {
        print('Database stream error: $error');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Firebase connection error: ${error.toString()}')),
          );
          setState(() {
            _isConnected = false;
          });
        }
      }, onDone: () {
        print('Database connection closed');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Firebase connection closed')),
          );
          setState(() {
            _isConnected = false;
          });
        }
      });
      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      print('Error setting up database reference: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error setting up Firebase: ${e.toString()}')),
        );
        setState(() {
          _isConnected = false;
          _isInitializing = false;
        });
      }
    }
  }

  // Centralized data parsing logic
  void _parseData(dynamic rawData) {
    if (rawData == null) return;

    try {
      final data = Map<String, dynamic>.from(rawData as Map);

      if (data.containsKey('MPU') && data['MPU'] is Map) {
        final mpuData = Map<String, dynamic>.from(data['MPU']);
        bool mpuUpdated = false;

        // Extract accelerometer data
        if (mpuData.containsKey('accelerometer') && mpuData['accelerometer'] is Map) {
          final accelData = Map<String, dynamic>.from(mpuData['accelerometer']);
          final xValue = _parseDoubleValue(accelData['x']);
          final yValue = _parseDoubleValue(accelData['y']);
          final zValue = _parseDoubleValue(accelData['z']);

          _accelXData.add(FlSpot(_timeCounter.toDouble(), xValue));
          _accelYData.add(FlSpot(_timeCounter.toDouble(), yValue));
          _accelZData.add(FlSpot(_timeCounter.toDouble(), zValue));
          mpuUpdated = true;
        }

        // Extract gyroscope data
        if (mpuData.containsKey('gyroscope') && mpuData['gyroscope'] is Map) {
          final gyroData = Map<String, dynamic>.from(mpuData['gyroscope']);
          final xValue = _parseDoubleValue(gyroData['x']);
          final yValue = _parseDoubleValue(gyroData['y']);
          final zValue = _parseDoubleValue(gyroData['z']);

          _gyroXData.add(FlSpot(_timeCounter.toDouble(), xValue));
          _gyroYData.add(FlSpot(_timeCounter.toDouble(), yValue));
          _gyroZData.add(FlSpot(_timeCounter.toDouble(), zValue));
          mpuUpdated = true;
        }

        // Extract temperature
        if (mpuData.containsKey('temp')) {
          final tempValue = _parseDoubleValue(mpuData['temp']);
          // Only update temp if it actually changed significantly
          if ((tempValue - _temp).abs() > 0.01 && mounted) {
            setState(() {
              _temp = tempValue;
            });
          }
        }

        if (mpuUpdated) {
          _timeCounter++; // Increment time only if MPU data was processed
          if (mounted) {
            setState(() {
              // This setState call triggers UI update for graphs
            });
          }
        }
      }

      // Final connection status update (redundant if already connected, but safe)
      if (!_isConnected && mounted) {
        setState(() {
          _isConnected = true;
        });
      }
    } catch (e) {
      print('Error parsing data: $e');
      print('Problematic data chunk: $rawData'); // Log the raw data that caused the error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing incoming data: ${e.toString()}')),
        );
      }
    }
  }

  // Helper method to parse double values safely
  double _parseDoubleValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) {
      return value;
    } else if (value is int) {
      return value.toDouble();
    } else {
      return double.tryParse(value.toString()) ?? 0.0;
    }
  }

  List<FlSpot> _limitData(List<FlSpot> data) {
    if (data.length > dataLimit) {
      return data.sublist(data.length - dataLimit);
    }
    return data;
  }

  @override
  void dispose() {
    print("Disposing GraphScreen");
    _subscription?.cancel();
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
            Text('Initializing connection...'),
          ],
        ),
      );
    } else if (!_isConnected) {
      bodyContent = Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.cloud_off, size: 60, color: Colors.red[300]),
              const SizedBox(height: 16),
              const Text(
                'Disconnected from Inhaler',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please check the device connection and your internet.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon( // Add a retry button maybe?
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
                onPressed: _initializeDatabase, // Re-run initialization
              )
            ],
          ),
        ),
      );
    } else {
      bodyContent = SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildGraphCard(
              'Acceleration X',
              _limitData(_accelXData),
              Colors.redAccent,
            ),
            _buildGraphCard(
              'Acceleration Y',
              _limitData(_accelYData),
              Colors.greenAccent,
            ),
            _buildGraphCard(
              'Acceleration Z',
              _limitData(_accelZData),
              Colors.blueAccent,
            ),
            _buildGraphCard(
              'Gyroscope X',
              _limitData(_gyroXData),
              Colors.orangeAccent,
            ),
            _buildGraphCard(
              'Gyroscope Y',
              _limitData(_gyroYData),
              Colors.purpleAccent,
            ),
            _buildGraphCard(
              'Gyroscope Z',
              _limitData(_gyroZData),
              Colors.tealAccent,
            ),
            Card(
              elevation: _cardElevation,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_cardCornerRadius),
              ),
              color: _motionSensorCardColor,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Temperature:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _textColor,
                      ),
                    ),
                    Text(
                      '${_temp.toStringAsFixed(1)}°C',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Motion Sensor Graphs'),
        elevation: 1,
        backgroundColor: Colors.white,
        foregroundColor: _textColor,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isConnected ? Colors.green[100] : Colors.red[100],
                  borderRadius: BorderRadius.circular(10),
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
                      _isConnected ? 'Connected' : 'Offline',
                      style: TextStyle(
                        color: _isConnected ? Colors.green[800] : Colors.red[800],
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
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

  Widget _buildGraphCard(String title, List<FlSpot> data, Color color) {
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 8),
            _buildGraph(data, color),
          ],
        ),
      ),
    );
  }

  Widget _buildGraph(List<FlSpot> data, Color color) {
    if (data.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8.0),
        child: Text('No data available'),
      );
    }

    // Find min/max Y values for dynamic axis scaling
    double minY = data.first.y;
    double maxY = data.first.y;
    for (var spot in data) {
      if (spot.y < minY) minY = spot.y;
      if (spot.y > maxY) maxY = spot.y;
    }
    // Add some padding to min/max Y
    final double paddingY = (maxY - minY) * 0.1; // 10% padding
    minY -= paddingY;
    maxY += paddingY;
    if (minY == maxY) { // Avoid zero range
      minY -= 1;
      maxY += 1;
    }

    return SizedBox(
      height: 150,
      child: LineChart(
        LineChartData(
          lineBarsData: [
            LineChartBarData(
              spots: data,
              isCurved: true,
              barWidth: 2,
              color: color,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          minX: data.first.x,
          maxX: data.last.x,
          minY: minY,
          maxY: maxY,
        ),
      ),
    );
  }
}