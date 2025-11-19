// ============================================================================
// FILE: add_device_screen.dart
// PURPOSE: Allows users to pair/claim a new Raspberry Pi device
// 
// This screen provides a form for users to enter a device's MAC address
// and pair it to their account. The device must already be registered in
// Firestore by the Raspberry Pi (with userId=null) before pairing.
// 
// PAIRING FLOW:
// 1. User runs smart_cabinet_pi_backend.py on Raspberry Pi
// 2. Pi registers itself in Firestore with userId=null (unpaired)
// 3. User finds device MAC address (displayed in Pi terminal)
// 4. User enters MAC address in this screen
// 5. App calls DeviceService.pairDevice() to set userId
// 6. Device now appears in user's device list
// 
// FEATURES:
// - Text input for device MAC address
// - Format validation (MAC address pattern)
// - Loading state during pairing
// - Success/error feedback via SnackBars
// - Auto-navigation back on success
// 
// NAVIGATION:
// - From: DevicesScreen → FAB
// - To: DevicesScreen (on success)
// 
// UI COMPONENTS:
// - Form with TextFormField for device ID
// - Validation for MAC address format
// - Loading indicator during pairing
// - ElevatedButton for pairing action
// ============================================================================

import 'package:flutter/material.dart';
import 'device_service.dart';

/// Screen for pairing a new Raspberry Pi device to user's account
/// 
/// Provides a form to enter device MAC address and initiate pairing.
/// The device must already be registered in Firestore by the Pi.
class AddDeviceScreen extends StatefulWidget {
  const AddDeviceScreen({super.key});

  @override
  State<AddDeviceScreen> createState() => _AddDeviceScreenState();
}

class _AddDeviceScreenState extends State<AddDeviceScreen> {
  /// Text controller for device ID input field
  final _deviceIdController = TextEditingController();
  
  /// Form key for validation
  final _formKey = GlobalKey<FormState>();
  
  /// Loading state flag (shows CircularProgressIndicator)
  bool _isLoading = false;

  /// Attempts to pair the device with entered MAC address
  /// 
  /// This method:
  /// 1. Validates the form input
  /// 2. Calls DeviceService.pairDevice() with the MAC address
  /// 3. Shows success SnackBar and navigates back on success
  /// 4. Shows error SnackBar on failure
  /// 5. Manages loading state throughout the process
  Future<void> _pairDevice() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await DeviceService().pairDevice(_deviceIdController.text.trim());
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Device paired successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Add Device',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter Device ID',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'You can find the Device ID on your Raspberry Pi display or in the logs.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _deviceIdController,
                decoration: InputDecoration(
                  labelText: 'Device ID',
                  hintText: 'e.g., b8:27:eb:xx:xx:xx',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a device ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _pairDevice,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pinkAccent.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Pair Device',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _deviceIdController.dispose();
    super.dispose();
  }
}
