// ============================================================================
// FILE: detection_processor_service.dart
// PURPOSE: Automatic detection processing service
// 
// This service listens to new detection events from all user devices and
// automatically processes them by matching with inventory and updating quantities.
// 
// FEATURES:
// - Real-time detection monitoring
// - Automatic label-based matching
// - Inventory quantity updates
// - Device assignment for 'in' detections from unorganized
// ============================================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'device_service.dart';

class DetectionProcessorService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final DeviceService _deviceService = DeviceService();
  
  final Map<String, StreamSubscription> _deviceListeners = {};
  StreamSubscription? _deviceListSubscription;

  /// Start listening to all user devices for new detections
  void startListening() {
    final userId = _auth.currentUser?.uid;
    if (userId == null) {
      print('⚠️ Cannot start detection processor: User not logged in');
      return;
    }

    print('\n🎧 ========================================');
    print('🎧 DETECTION PROCESSOR: STARTING');
    print('🎧 User ID: $userId');
    print('🎧 ========================================\n');

    // Listen to user's devices
    _deviceListSubscription = _firestore
        .collection('devices')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snapshot) {
      for (var doc in snapshot.docs) {
        final deviceId = doc.id;
        
        // Skip if already listening to this device
        if (_deviceListeners.containsKey(deviceId)) continue;
        
        _startDeviceListener(deviceId);
      }
    });
  }

  /// Start listening to detections for a specific device
  void _startDeviceListener(String deviceId) {
    print('🎧 Starting detection listener for device: $deviceId');
    print('   Listening for detections with processed=false');

    final detectionStream = _firestore
        .collection('devices')
        .doc(deviceId)
        .collection('detections')
        .where('processed', isEqualTo: false)
        .snapshots();

    _deviceListeners[deviceId] = detectionStream.listen((snapshot) {
      print('   📡 Detection snapshot received for $deviceId: ${snapshot.docChanges.length} changes');
      
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final detection = change.doc.data();
          final detectionId = change.doc.id;
          print('   ➕ New unprocessed detection found: $detectionId');
          print('      Label: ${detection?['label']}');
          print('      Direction: ${detection?['direction']}');
          print('      Processed: ${detection?['processed']}');
          if (detection != null) {
            _processDetection(deviceId, detectionId, detection);
          }
        }
      }
    }, onError: (error) {
      print('   ❌ Error listening to detections for $deviceId: $error');
    });
  }

  /// Process a single detection automatically
  Future<void> _processDetection(
    String deviceId,
    String detectionId,
    Map<String, dynamic> detection,
  ) async {
    try {
      final itemName = detection['label'] as String?;
      final direction = detection['direction'] as String?;

      if (itemName == null || direction == null) {
        print('⚠️ Detection missing label or direction: $detectionId');
        return;
      }

      print('\n🤖 AUTO-PROCESSING DETECTION:');
      print('   Device: $deviceId');
      print('   Detection: $detectionId');
      print('   Item (YOLO label): $itemName');
      print('   Direction: $direction');

      await _deviceService.processDetection(
        detectionId: detectionId,
        deviceId: deviceId,
        itemName: itemName,
        direction: direction,
      );

      print('✅ Auto-processed detection: $itemName ($direction)');
    } catch (e) {
      print('❌ Error auto-processing detection $detectionId: $e');
    }
  }

  /// Stop all detection listeners
  void stopListening() {
    print('🛑 Detection Processor: Stopping automatic processing');
    
    for (var listener in _deviceListeners.values) {
      listener.cancel();
    }
    _deviceListeners.clear();
    
    _deviceListSubscription?.cancel();
    _deviceListSubscription = null;
  }
}
