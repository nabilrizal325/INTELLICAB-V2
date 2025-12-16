import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
//import 'package:intellicab/add_item_page.dart';
import 'package:intellicab/homepage.dart';
import 'package:intellicab/login_page.dart';
import 'package:intellicab/detection_processor_service.dart';
//import 'package:intellicab/sign_up_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IntelliCab',
      home: const AuthGate(), // Handles login vs home
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final DetectionProcessorService _detectionProcessor = DetectionProcessorService();
  bool _isListening = false;

  @override
  void dispose() {
    _detectionProcessor.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          // User is logged in - start automatic detection processing (only once)
          if (!_isListening) {
            _isListening = true;
            _detectionProcessor.startListening();
          }
          return const HomePage();
        } else {
          // User logged out - stop detection processing
          if (_isListening) {
            _isListening = false;
            _detectionProcessor.stopListening();
          }
        }

        return const LoginPage();
      },
    );
  }
}
