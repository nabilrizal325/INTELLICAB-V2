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
}
