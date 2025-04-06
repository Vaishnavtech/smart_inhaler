// stats_grid.dart
import 'package:flutter/material.dart';

class StatsGrid extends StatelessWidget {
  final int dailyDosesTaken;
  final int dailyDoseLimit;
  final int correctCount;
  final int falseCount;
  final int maxDoseCount; // Added max dose count

  const StatsGrid({
    Key? key,
    required this.dailyDosesTaken,
    required this.dailyDoseLimit,
    required this.correctCount,
    required this.falseCount,
    required this.maxDoseCount, // Make it required
  }) : super(key: key);

  // Helper method to build a single stat card
  Widget _buildStatCard(String title, String value) {
    return Card(
      color: const Color(0xFF0D47A1), // Dark blue color
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 8.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                  color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true, // Important inside SingleChildScrollView
      physics: const NeverScrollableScrollPhysics(), // Disable grid's own scrolling
      crossAxisSpacing: 12, // Horizontal space between cards
      mainAxisSpacing: 12,  // Vertical space between cards
      childAspectRatio: 1.6, // Width / Height ratio
      children: [
        _buildStatCard('Daily Doses', '$dailyDosesTaken/$dailyDoseLimit'),
        _buildStatCard('Correct Count', '$correctCount'),
        // Use the passed maxDoseCount here
        _buildStatCard('Maximum dose', '$maxDoseCount'),
        _buildStatCard('False Count', '$falseCount'),
      ],
    );
  }
}