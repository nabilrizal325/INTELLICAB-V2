import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'device_model.dart';

class DeviceService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get user's devices
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

  // Pair a device with current user
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

  // Toggle preview
  Future<void> togglePreview(String deviceId, bool enabled) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'preview_enabled': enabled});
  }

  // Request calibration frame
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

  // Toggle detection
  Future<void> toggleDetection(String deviceId, bool enabled) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'detection_enabled': enabled});
  }

  // Get single device stream
  Stream<DeviceModel> getDevice(String deviceId) {
    return _firestore
        .collection('devices')
        .doc(deviceId)
        .snapshots()
        .map((doc) => DeviceModel.fromFirestore(doc));
  }

  // Link device to a cabinet
  Future<void> linkDeviceToCabinet(String deviceId, String cabinetId) async {
    await _firestore
        .collection('devices')
        .doc(deviceId)
        .update({'cabinetId': cabinetId});
  }

  // Process detection and update inventory
  Future<void> processDetection({
    required String detectionId,
    required String deviceId,
    required String itemName,
    required String direction,
    String? correctedItemName,
  }) async {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not logged in');

    // Get device to find linked cabinet
    final deviceDoc = await _firestore
        .collection('devices')
        .doc(deviceId)
        .get();
    
    final cabinetId = deviceDoc.data()?['cabinetId'] as String?;
    if (cabinetId == null) {
      throw Exception('Device not linked to a cabinet. Please link it first.');
    }

    // Use corrected name if provided
    final finalItemName = correctedItemName ?? itemName;

    // Find inventory item matching the name and cabinet
    final userDocRef = _firestore.collection('User').doc(userId);
    final inventoryQuery = await userDocRef
        .collection('inventory')
        .where('cabinetId', isEqualTo: cabinetId)
        .get();

    // Search for matching item (case-insensitive)
    DocumentSnapshot? matchingDoc;
    for (var doc in inventoryQuery.docs) {
      final data = doc.data();
      final docName = '${data['brand'] ?? ''} ${data['name'] ?? ''}'.trim().toLowerCase();
      if (docName == finalItemName.toLowerCase() || 
          (data['name'] as String?)?.toLowerCase() == finalItemName.toLowerCase()) {
        matchingDoc = doc;
        break;
      }
    }

    if (matchingDoc == null) {
      // Item not in inventory - create it if direction is 'in'
      if (direction == 'in') {
        await userDocRef.collection('inventory').add({
          'name': finalItemName,
          'brand': '',
          'cabinetId': cabinetId,
          'cabinetName': cabinetId,
          'quantity': 1,
          'location': 'in',
          'created_at': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
        print('✅ Created new inventory item: $finalItemName');
      } else {
        // Item going out but not in inventory - just log it
        print('⚠️ Item "$finalItemName" removed but was not in inventory');
      }
    } else {
      // Item exists - update quantity
      final data = matchingDoc.data() as Map<String, dynamic>;
      final currentQuantity = data['quantity'] as int? ?? 0;
      
      int newQuantity;
      if (direction == 'in') {
        newQuantity = currentQuantity + 1;
      } else {
        newQuantity = (currentQuantity - 1).clamp(0, 9999);
      }

      await matchingDoc.reference.update({
        'quantity': newQuantity,
        'lastUpdated': FieldValue.serverTimestamp(),
      });
      print('✅ Updated inventory: $finalItemName ($currentQuantity → $newQuantity)');
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
    });
  }

  // Ignore a detection (mark as false positive)
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
