// lib/main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screen1.dart'; // Import the main dashboard screen

void main() async {
  // Ensure Flutter bindings are initialized before Firebase
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print('Firebase initialized successfully');
  } catch (e) {
    // Log error or show a specific error screen if Firebase fails critically
    print('Error initializing Firebase: $e');
    // Optionally, runApp(ErrorApp(e));
    return; // Don't run the main app if Firebase fails
  }

  // Run the main application
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Inhaler App', // Added app title
      theme: ThemeData(
        fontFamily: 'Roboto', // Keep your font
        primarySwatch: Colors.blue, // Or use ColorScheme.fromSeed for Material 3
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // Consider adding more theme elements (e.g., CardTheme, ButtonTheme)
         colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue), // Material 3 style
         useMaterial3: true, // Enable Material 3
         cardTheme: CardTheme( // Consistent card styling
             elevation: 4.0,
             shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12.0),
             ),
         ),
         appBarTheme: const AppBarTheme( // Consistent app bar
            backgroundColor: Colors.white,
            foregroundColor: Color(0xFF212121), // Assuming _textColor
            elevation: 1.0,
         )
      ),
      // Set screen1 as the home screen
      home: const InhalerDashboardScreen1(),
      debugShowCheckedModeBanner: false, // Keep this off for production builds
    );
  }
}
