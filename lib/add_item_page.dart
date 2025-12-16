import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intellicab/manual_entry.dart';
import 'package:mobile_scanner/mobile_scanner.dart' as mobile;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart' as mlkit;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AddItemPage extends StatefulWidget {
  const AddItemPage({super.key});

  @override
  State<AddItemPage> createState() => _AddItemPageState();
}

// Add this variable at the top of your State class
bool _isProcessingBarcode = false;
late mobile.MobileScannerController _scannerController;



class _AddItemPageState extends State<AddItemPage> {
  bool _isLoading = false;
  
  @override
  void initState() {
  super.initState();
  _scannerController = mobile.MobileScannerController();
  }

  bool isScanMode = true;
  final ImagePicker _picker = ImagePicker();
  String? scannedCode;

  // Firebase references
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

// Handles barcode scanning result from live camera
void _onBarcodeDetected(mobile.BarcodeCapture capture) async {
  if (_isProcessingBarcode) return; // 🔹 Prevent duplicate scans

  final barcodes = capture.barcodes;
  if (barcodes.isNotEmpty) {
    _isProcessingBarcode = true; // 🔹 Block further detections
    await _scannerController.stop();

    if (barcodes.length == 1) {
      // Only one barcode → process it
      final code = barcodes.first.rawValue;
      if (code != null) {
        setState(() => scannedCode = code);
        await _processScannedBarcode(code);
      }
    } else {
      // Multiple barcodes → let user choose
      final selectedCode = await _showBarcodeChoiceDialog(barcodes);
      if (selectedCode != null) {
        setState(() => scannedCode = selectedCode);
        await _processScannedBarcode(selectedCode);
      }
    }

    await Future.delayed(const Duration(seconds: 1)); // 🔹 small cooldown
    await _scannerController.start();
    _isProcessingBarcode = false; // 🔹 Allow next detection
  }
}




  /// Show a dialog to let user choose from multiple barcodes
  Future<String?> _showBarcodeChoiceDialog(List<mobile.Barcode> barcodes) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Select a barcode"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: barcodes
                .map((b) => ListTile(
                      title: Text(b.rawValue ?? "Unknown"),
                      onTap: () => Navigator.pop(context, b.rawValue),
                    ))
                .toList(),
          ),
        );
      },
    );
  }

  // Handles image picking and scanning using Google ML Kit
  Future<void> _scanFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      final inputImage = mlkit.InputImage.fromFilePath(image.path);
      final barcodeScanner = mlkit.BarcodeScanner(
        formats: [mlkit.BarcodeFormat.all],
      );

      try {
        final List<mlkit.Barcode> barcodes =
            await barcodeScanner.processImage(inputImage);

        if (barcodes.isNotEmpty) {
          setState(() {
            scannedCode = barcodes.first.rawValue;
          });
          debugPrint('Scanned from gallery: $scannedCode');
          if (scannedCode != null) {
            _processScannedBarcode(scannedCode!);
          }
        } else {
          debugPrint('No barcode found in image.');
        }
      } catch (e) {
        debugPrint('Error scanning barcode: $e');
      } finally {
        await barcodeScanner.close();
      }
    }
  }


  /// 🔹 Process scanned barcode: fetch from global, then add to user inventory
  Future<void> _processScannedBarcode(String barcode) async {
    setState(() => _isLoading = true);
    
    try {
      // Step 1: Lookup product in food_products (global database)
      final query = await _firestore
          .collection('food_products')
          .where('barcode', isEqualTo: barcode)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _showErrorDialog("Product not found in global database.");
        return;
      }

      final globalData = query.docs.first.data();
      final brand = globalData['brand'];
      final name = globalData['name'];

      // Step 3: Ask user for expiry date
      final expiryDate = await _askForExpiryDate();
      if (expiryDate == null) return;

      // Step 3: Add/update user inventory under User/{uid}/inventory/{barcode}
      final userInvRef = _firestore
          .collection('User')
          .doc(_currentUser!.uid)
          .collection('inventory')
          .doc(barcode); // barcode as document ID

      final userDoc = await userInvRef.get();

      if (userDoc.exists) {
        // If item already exists → increment quantity and update expiry date
        await userInvRef.update({
          'quantity': FieldValue.increment(1),
          'expiryDates': [expiryDate], // Store as array only
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        // New item - store in unorganized cabinet
        await userInvRef.set({
          'barcode': barcode,
          'brand': brand,
          'name': name,
          'quantity': 1,
          'expiryDates': [expiryDate], // Store as array only
          'cabinetName': 'unorganized',
          'location': 'out',
          'created_at': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }

      _showSuccessDialog("$name added to your inventory!");
    } catch (e) {
      debugPrint("Error processing barcode: $e");
      _showErrorDialog("Something went wrong. Please try again.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 🔹 Popup for expiry date input
  Future<String?> _askForExpiryDate() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Expiry Date'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Format: dd-mm-yyyy\nExample: 25-12-2025',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'dd-mm-yyyy',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        // Validate the date format (dd-mm-yyyy)
        final parts = result.split('-');
        if (parts.length != 3) throw FormatException('Invalid date format');
        
        final day = int.parse(parts[0]);
        final month = int.parse(parts[1]);
        final year = int.parse(parts[2]);
        
        // Basic date validation
        if (day < 1 || day > 31 || month < 1 || month > 12 || year < 2023) {
          throw FormatException('Invalid date values');
        }
        
        return result; // Return the original string input
      } catch (e) {
        _showErrorDialog('Invalid date format. Please use dd-mm-yyyy');
        return null;
      }
    }
    return null;
  }


  /// 🔹 Helper dialogs
  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Error"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Success"),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  // 🔹 UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 70,
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Add Item',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          )
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildToggleButton('Scan', isScanMode, () {
                    setState(() => isScanMode = true);
                  }),
                  const SizedBox(width: 10),
                  _buildToggleButton('Manual', !isScanMode, () {
                    setState(() => isScanMode = false);
                  }),
                ],
              ),
              const SizedBox(height: 20),
              Expanded(
                child: isScanMode ? _buildScanUI() : ManualEntryForm(),
              ),
            ],
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool active, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor:
            active ? Colors.pinkAccent.shade100 : Colors.grey.shade300,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 8),
      ),
      child: Text(
        label,
        style: TextStyle(color: active ? Colors.black : Colors.black54),
      ),
    );
  }

  Widget _buildScanUI() {
    return SingleChildScrollView(
      child: Column(
        children: [
          const Text(
            "Scan Barcode",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // 🔹 Fixed height for camera preview
          Container(
            height: 420,
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26, width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: mobile.MobileScanner(
              controller: _scannerController,
              onDetect: _onBarcodeDetected,
            ),
          ),

          const SizedBox(height: 10),
          const Text("Place Barcode in the scan area"),
          const SizedBox(height: 20),

          // 🔹 Scan from gallery button
          ElevatedButton(
            onPressed: _scanFromGallery,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent.shade100,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
            ),
            child: const Text("Scan from Gallery",
                style: TextStyle(color: Colors.black)),
          ),

          if (scannedCode != null) ...[
            const SizedBox(height: 10),
            Text("Detected: $scannedCode"),
          ]
        ],
      ),
    );
  }
}