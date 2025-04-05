// motion_sensor_data_widget.dart
import 'package:flutter/material.dart';

// --- Constants (Used only by this widget) ---
const Color _motionSensorCardColor = Color(0xFFB2EBF2); // Light Teal
const Color _textColor = Color(0xFF212121); // Define here as it's used locally
const double _cardCornerRadius = 12.0;
const double _cardElevation = 4.0;

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

  // Helper method to build a data row
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