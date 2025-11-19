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

  /// Processes detection with AUTOMATIC inventory matching
  /// 
  /// MATCHING LOGIC:
  /// 1. Get detected item name from YOLO (e.g., "bottle", "coca_cola_can")
  /// 2. Query user's inventory for ALL items
  /// 3. Try to match using multiple strategies:
  ///    a) Exact match: item_name == inventory.name
  ///    b) Brand match: detected_brand matches inventory.brand
  ///    c) Fuzzy match: similar words in name
  /// 4. If match found and direction='in' from unorganized → move to device
  /// 5. Update quantity based on direction
  /// 
  /// EXAMPLE FLOW:
  /// ```
  /// User's Inventory:
  ///   - name: "Coca Cola", brand: "Coca Cola", deviceId: "unorganized"
  ///   - name: "Sprite", brand: "Sprite", deviceId: "unorganized"
  /// 
  /// Camera detects: "coca_cola_bottle" going IN
  ///   ↓
  /// Matching: "coca cola" contains "Coca Cola" ✅
  ///   ↓
  /// Action: Move "Coca Cola" from unorganized to device AA:BB:CC:DD:EE:FF
  ///         Increase quantity by 1
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

    // Get device info
    final deviceDoc = await _firestore
        .collection('devices')
        .doc(deviceId)
        .get();
    
    if (!deviceDoc.exists) {
      throw Exception('Device not found');
    }

    final deviceData = deviceDoc.data()!;
    final deviceName = deviceData['name'] as String? ?? deviceId.substring(0, 8);

    // Use corrected name if provided, otherwise use detected name
    final finalItemName = correctedItemName ?? itemName;
    
    final userDocRef = _firestore.collection('User').doc(userId);

    // Get detection details for better matching
    final detectionDoc = await _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('detections')
        .doc(detectionId)
        .get();
    
    final detectionData = detectionDoc.data();
    final detectedBrand = detectionData?['detected_brand'] as String?;

    // SMART MATCHING: Get ALL inventory items (not just by name)
    final allInventoryItems = await userDocRef
        .collection('inventory')
        .get();

    // Try to find matching item using multiple strategies
    QueryDocumentSnapshot? matchedItem;
    double bestMatchScore = 0.0;

    for (var doc in allInventoryItems.docs) {
      final itemData = doc.data();
      final inventoryName = (itemData['name'] as String?)?.toLowerCase() ?? '';
      final inventoryBrand = (itemData['brand'] as String?)?.toLowerCase() ?? '';
      
      // Calculate match score
      double score = _calculateMatchScore(
        detectedName: finalItemName.toLowerCase(),
        detectedBrand: detectedBrand?.toLowerCase(),
        inventoryName: inventoryName,
        inventoryBrand: inventoryBrand,
      );

      if (score > bestMatchScore) {
        bestMatchScore = score;
        matchedItem = doc;
      }
    }

    // Require at least 60% match confidence
    if (matchedItem != null && bestMatchScore >= 0.6) {
      final itemData = matchedItem.data() as Map<String, dynamic>;
      final currentDeviceId = itemData['deviceId'] as String?;
      final currentQuantity = itemData['quantity'] as int? ?? 0;
      final inventoryItemName = itemData['name'] as String;

      print('🎯 Matched detected "$finalItemName" with inventory "$inventoryItemName" (${(bestMatchScore * 100).toStringAsFixed(0)}% confidence)');

      // If item is in unorganized and detection is 'in', move it to this device
      if (currentDeviceId == 'unorganized' && direction == 'in') {
        await matchedItem.reference.update({
          'deviceId': deviceId,
          'deviceName': deviceName,
          'quantity': currentQuantity + 1,
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Moved $inventoryItemName from unorganized to $deviceName');
      } else {
        // Normal quantity update
        int newQuantity;
        if (direction == 'in') {
          newQuantity = currentQuantity + 1;
        } else {
          newQuantity = (currentQuantity - 1).clamp(0, 999);
        }

        await matchedItem.reference.update({
          'quantity': newQuantity,
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Updated inventory: $inventoryItemName ($currentQuantity → $newQuantity)');
      }

      // Mark detection as processed with match info
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('detections')
          .doc(detectionId)
          .update({
        'processed': true,
        'processedAt': FieldValue.serverTimestamp(),
        'matchScore': bestMatchScore,
        'matchedItemName': inventoryItemName,
        'inventoryUpdated': true,
        'deviceId': deviceId,
        'deviceName': deviceName,
      });
    } else {
      // No match found - log for manual review
      print('⚠️ No inventory match for "$finalItemName" (best score: ${(bestMatchScore * 100).toStringAsFixed(0)}%)');
      
      // If direction is 'in', create new item at this device
      if (direction == 'in') {
        await userDocRef.collection('inventory').add({
          'name': finalItemName,
          'brand': detectedBrand ?? '',
          'deviceId': deviceId,
          'deviceName': deviceName,
          'quantity': 1,
          'category': 'Auto-detected',
          'added_date': FieldValue.serverTimestamp(),
          'last_updated': FieldValue.serverTimestamp(),
        });
        print('✅ Created new inventory item: $finalItemName at $deviceName');
      }

      // Mark detection as processed (no match)
      await _firestore
          .collection('devices')
          .doc(deviceId)
          .collection('detections')
          .doc(detectionId)
          .update({
        'processed': true,
        'processedAt': FieldValue.serverTimestamp(),
        'matchScore': bestMatchScore,
        'matchedItemName': null,
        'inventoryUpdated': direction == 'in',
        'deviceId': deviceId,
        'deviceName': deviceName,
      });
    }
  }

  /// Calculates match score between detected item and inventory item
  /// 
  /// SCORING SYSTEM:
  /// - Exact name match: 1.0
  /// - Brand exact match: +0.4
  /// - Name contains detected words: 0.7
  /// - Detected name contains inventory name: 0.6
  /// - Word overlap: 0.3-0.8 based on percentage
  /// 
  /// Returns: Score from 0.0 to 1.0
  double _calculateMatchScore({
    required String detectedName,
    String? detectedBrand,
    required String inventoryName,
    required String inventoryBrand,
  }) {
    double score = 0.0;

    // Clean and normalize strings
    final cleanDetected = detectedName.replaceAll('_', ' ').trim();
    final cleanInventory = inventoryName.trim();

    // 1. EXACT MATCH (best case)
    if (cleanDetected == cleanInventory) {
      return 1.0;
    }

    // 2. BRAND MATCH (very strong signal)
    if (detectedBrand != null && 
        detectedBrand.isNotEmpty && 
        inventoryBrand.isNotEmpty) {
      if (inventoryBrand.contains(detectedBrand) || 
          detectedBrand.contains(inventoryBrand)) {
        score += 0.4;
      }
    }

    // 3. SUBSTRING MATCH (one contains the other)
    if (cleanInventory.contains(cleanDetected)) {
      score += 0.7;
    } else if (cleanDetected.contains(cleanInventory)) {
      score += 0.6;
    }

    // 4. WORD OVERLAP (count matching words)
    final detectedWords = cleanDetected.split(' ').toSet();
    final inventoryWords = cleanInventory.split(' ').toSet();
    
    final commonWords = detectedWords.intersection(inventoryWords);
    final totalWords = detectedWords.union(inventoryWords);
    
    if (totalWords.isNotEmpty) {
      final wordOverlapScore = commonWords.length / totalWords.length;
      score += wordOverlapScore * 0.5;
    }

    // 5. BRAND IN NAME (brand mentioned in product name)
    if (inventoryBrand.isNotEmpty && 
        cleanDetected.contains(inventoryBrand)) {
      score += 0.3;
    }

    return score.clamp(0.0, 1.0);
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
