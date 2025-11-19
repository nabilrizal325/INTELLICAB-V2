// ============================================================================
// FILE: device_service.dart
// PURPOSE: Service layer for all device-related Firestore operations
// 
// This file provides a centralized service for managing smart cabinet camera
// devices. It handles all CRUD operations, device pairing, control commands,
// and inventory integration.
// 
// RESPONSIBILITIES:
// - Device pairing (claiming unowned devices)
// - Fetching user's devices from Firestore
// - Toggling device features (preview, detection)
// - Calibration management (requesting frames, saving boundaries)
// - Linking devices to inventory cabinets
// - Processing detection events into inventory updates
// - Marking detections as ignored (false positives)
// 
// FIRESTORE OPERATIONS:
// - Read: devices/{deviceId} - Get device state
// - Read: devices (query) - Get all user devices
// - Write: devices/{deviceId} - Update device commands/config
// - Read: User/{userId}/inventory - Query inventory items
// - Write: User/{userId}/inventory/{itemId} - Update item quantities
// - Write: devices/{deviceId}/detections/{detectionId} - Mark processed
// 
// USAGE:
// ```dart
// final deviceService = DeviceService();
// 
// // Get user's devices
// Stream<List<DeviceModel>> devices = deviceService.getUserDevices();
// 
// // Pair a new device
// await deviceService.pairDevice('AA:BB:CC:DD:EE:FF');
// 
// // Toggle preview
// await deviceService.togglePreview(deviceId, true);
// 
// // Link to cabinet
// await deviceService.linkDeviceToCabinet(deviceId, 'Kitchen Cabinet');
// 
// // Process detection
// await deviceService.processDetection(
//   detectionId: 'det123',
//   deviceId: 'device123',
//   itemName: 'Coca Cola',
//   direction: 'in',
// );
// ```
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'device_model.dart';

/// Service class for managing Raspberry Pi camera devices
/// 
/// This service provides all device-related functionality including
/// pairing, control, calibration, and inventory integration.
class DeviceService {
  /// Firestore instance for database operations
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  /// Firebase Auth instance to get current user ID
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Streams all devices owned by the current user
  /// 
  /// This method queries the 'devices' collection for documents where
  /// userId matches the current user's UID. It returns a real-time stream
  /// that updates whenever device data changes in Firestore.
  /// 
  /// Returns: Stream<List<DeviceModel>> - Real-time list of user's devices
  /// 
  /// Example:
  /// ```dart
  /// StreamBuilder<List<DeviceModel>>(
  ///   stream: deviceService.getUserDevices(),
  ///   builder: (context, snapshot) {
  ///     final devices = snapshot.data ?? [];
  ///     return ListView.builder(...);
  ///   },
  /// )
  /// ```
  Stream<List<DeviceModel>> getUserDevices() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) return Stream.value([]);

    return _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => DeviceModel.fromFirestore(doc))
            .toList());
  }

  /// Pairs (claims) an unowned device to the current user
  /// 
  /// This method assigns the current user's UID to a device document,
  /// effectively claiming ownership. The device must exist in Firestore
  /// and should have userId=null (unowned).
  /// 
  /// The Raspberry Pi creates its device document on first boot with
  /// userId=null. Users then "pair" it through the app by entering the
  /// device's MAC address.
  /// 
  /// Parameters:
  ///   - deviceId: String - The device's MAC address (e.g., "AA:BB:CC:DD:EE:FF")
  /// 
  /// Throws: Exception if user is not logged in or device doesn't exist
  /// 
  /// Example:
  /// ```dart
  /// try {
  ///   await deviceService.pairDevice('AA:BB:CC:DD:EE:FF');
  ///   print('Device paired successfully!');
  /// } catch (e) {
  ///   print('Failed to pair device: $e');
  /// }
  /// ```
  Future<void> pairDevice(String deviceId) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not logged in');

    final deviceRef = _firestore.collection('devices').doc(deviceId);
    final deviceDoc = await deviceRef.get();

    if (!deviceDoc.exists) {
      throw Exception('Device not found. Make sure the Pi is running.');
    }

    await deviceRef.update({'userId': userId});
  }

  /// Toggles live preview streaming on/off
  /// 
  /// This method updates the 'previewEnabled' field in Firestore.
  /// The Raspberry Pi listens to this field and starts/stops sending
  /// preview frames as base64 images to the 'previewImage' field.
  /// 
  /// Preview uses low FPS (~1-2 fps) to avoid Firestore quota issues.
  /// Images are JPEG compressed and base64 encoded.
  /// 
  /// Parameters:
  ///   - deviceId: String - Target device ID
  ///   - enabled: bool - true to start preview, false to stop
  /// 
  /// Example:
  /// ```dart
  /// // Start preview
  /// await deviceService.togglePreview(deviceId, true);
  /// 
  /// // Stop preview
  /// await deviceService.togglePreview(deviceId, false);
  /// ```
  Future<void> togglePreview(String deviceId, bool enabled) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'preview_enabled': enabled});
  }

  /// Requests a calibration frame from the device
  /// 
  /// This method sets 'calibrationRequested=true' in Firestore.
  /// The Raspberry Pi detects this, captures a single frame,
  /// converts it to base64 JPEG, and stores it in 'calibrationImage' field.
  /// 
  /// The user then uses this frame to draw a boundary line that defines
  /// the detection zone. Items crossing this line trigger detection events.
  /// 
  /// Parameters:
  ///   - deviceId: String - Target device ID
  /// 
  /// Flow:
  /// 1. App calls requestCalibration()
  /// 2. Pi detects calibrationRequested=true
  /// 3. Pi captures frame and uploads to calibrationImage
  /// 4. Pi sets calibrationRequested=false
  /// 5. App shows CalibrationScreen for boundary drawing
  /// 
  /// Example:
  /// ```dart
  /// await deviceService.requestCalibration(deviceId);
  /// // Wait for calibrationImage to appear in device stream
  /// // Then navigate to CalibrationScreen
  /// ```
  Future<void> requestCalibration(String deviceId) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'calibration_requested': true});
  }

  // Save boundary
  Future<void> saveBoundary(String deviceId, Map<String, dynamic> boundary) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'boundary': boundary});
  }

  /// Toggles object detection monitoring on/off
  /// 
  /// This method updates the 'detectionEnabled' field in Firestore.
  /// When enabled, the Raspberry Pi:
  /// 1. Connects to the cloud detection server via TCP socket
  /// 2. Streams video frames to the server
  /// 3. Server runs YOLO object detection
  /// 4. Server checks if objects cross the boundary line
  /// 5. Detection events are logged to Firestore
  /// 
  /// Requirements before enabling:
  /// - Boundary must be set (boundary != null)
  /// - Cloud server must be configured (IP and port)
  /// - Cloud server must be running and accessible
  /// 
  /// Parameters:
  ///   - deviceId: String - Target device ID
  ///   - enabled: bool - true to start detection, false to stop
  /// 
  /// Example:
  /// ```dart
  /// // Start detection
  /// await deviceService.toggleDetection(deviceId, true);
  /// 
  /// // Stop detection
  /// await deviceService.toggleDetection(deviceId, false);
  /// ```
  Future<void> toggleDetection(String deviceId, bool enabled) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'detection_enabled': enabled});
  }

  /// Streams a single device's data in real-time
  /// 
  /// This method returns a stream that emits the latest device state
  /// whenever any field changes in Firestore. Useful for monitoring
  /// a specific device's status, preview images, and configuration.
  /// 
  /// Parameters:
  ///   - deviceId: String - Target device ID
  /// 
  /// Returns: Stream<DeviceModel> - Real-time device state stream
  /// 
  /// Example:
  /// ```dart
  /// StreamBuilder<DeviceModel>(
  ///   stream: deviceService.getDevice(deviceId),
  ///   builder: (context, snapshot) {
  ///     final device = snapshot.data;
  ///     return Text('Status: ${device?.status}');
  ///   },
  /// )
  /// ```
  Stream<DeviceModel> getDevice(String deviceId) {
    return _firestore
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .map((doc) => DeviceModel.fromFirestore(doc));
  }

  /// Processes detection and updates inventory based on device location
  /// 
  /// The DEVICE itself represents a cabinet/storage location. When an item
  /// is detected going 'in', it's assigned to that device's location.
  /// 
  /// FLOW:
  /// 1. Get device info (device IS the cabinet)
  /// 2. Find item in inventory by name
  /// 3. If item in "unorganized" and direction='in' → assign to this device
  /// 4. Otherwise update quantity normally
  /// 5. Mark detection as processed
  /// 
  /// Parameters:
  /// - detectionId: ID of detection event to process
  /// - deviceId: Device that detected the item (represents the cabinet)
  /// - itemName: Name of detected item
  /// - direction: 'in' or 'out'
  /// - correctedItemName: User-corrected name if edited
  /// 
  /// Example:
  /// ```dart
  /// // Device "AA:BB:CC:DD:EE:FF" detects Coca Cola going in:
  /// await processDetection(
  ///   detectionId: 'det_123',
  ///   deviceId: 'AA:BB:CC:DD:EE:FF',
  ///   itemName: 'Coca Cola',
  ///   direction: 'in',
  /// );
  /// // Result: If Coca Cola was in "unorganized", it's now assigned to device AA:BB:CC:DD:EE:FF
  /// ```
  Future<void> processDetection({
    required String detectionId,
    required String deviceId,
    required String itemName,
    required String direction,
    String? correctedItemName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not logged in');

    // Get device info - the device IS the cabinet
    final deviceDoc = await _firestore
        .collection('devices')
        .doc(deviceId)
        .get();
    
    if (!deviceDoc.exists) {
      throw Exception('Device not found');
    }

    final deviceData = deviceDoc.data()!;
    final deviceName = deviceData['name'] as String? ?? deviceId;

    // Use corrected name if provided
    final finalItemName = correctedItemName ?? itemName;

    final userDocRef = _firestore.collection('User').doc(userId);

    // Find inventory item by name
    final inventoryQuery = await userDocRef
        .collection('inventory')
        .where('name', isEqualTo: finalItemName)
        .limit(1)
        .get();

    if (inventoryQuery.docs.isEmpty) {
      // Item not in inventory - create it and assign to this device
      if (direction == 'in') {
        await userDocRef.collection('inventory').add({
          'name': finalItemName,
          'deviceId': deviceId,           // Device ID instead of cabinetId
          'deviceName': deviceName,       // Device name for display
          'quantity': 1,
          'category': 'Detected',
          'added_date': FieldValue.serverTimestamp(),
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Created new inventory item: $finalItemName at $deviceName');
      } else {
        print('⚠️ Item "$finalItemName" removed but was not in inventory');
      }
    } else {
      // Item exists - check if it needs to be moved from unorganized
      final inventoryDoc = inventoryQuery.docs.first;
      final itemData = inventoryDoc.data();
      final currentDeviceId = itemData['deviceId'] as String?;
      final currentQuantity = itemData['quantity'] as int? ?? 0;

      // If item is in unorganized and detection is 'in', assign it to this device
      if (currentDeviceId == 'unorganized' && direction == 'in') {
        await inventoryDoc.reference.update({
          'deviceId': deviceId,           // Assign to this device
          'deviceName': deviceName,       // Update device name
          'quantity': currentQuantity + 1,
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Moved $finalItemName from unorganized to $deviceName');
      } else {
        // Normal quantity update
        int newQuantity;
        if (direction == 'in') {
          newQuantity = currentQuantity + 1;
        } else {
          newQuantity = (currentQuantity - 1).clamp(0, 999);
        }

        await inventoryDoc.reference.update({
          'quantity': newQuantity,
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Updated inventory: $finalItemName ($currentQuantity → $newQuantity)');
      }
    }

    // Mark detection as processed
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('detections')
        .doc(detectionId)
        .update({
      'processed': true,
      'processedAt': FieldValue.serverTimestamp(),
      'finalItemName': finalItemName,
      'inventoryUpdated': true,
      'deviceId': deviceId,
      'deviceName': deviceName,
    });
  }

  /// Marks a detection as ignored (false positive)
  /// 
  /// Parameters:
  /// - deviceId: Device that made the detection
  /// - detectionId: ID of detection event to ignore
  /// 
  /// The detection is marked with:
  /// - processed: true
  /// - ignored: true
  /// - processedAt: timestamp
  /// 
  /// Example:
  /// ```dart
  /// await deviceService.ignoreDetection('AA:BB:CC:DD:EE:FF', 'det_456');
  /// ```
  Future<void> ignoreDetection(String deviceId, String detectionId) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('detections')
        .doc(detectionId)
        .update({
      'processed': true,
      'ignored': true,
      'processedAt': FieldValue.serverTimestamp(),
    });
  }
}
