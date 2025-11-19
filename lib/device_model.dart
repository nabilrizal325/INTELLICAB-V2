// ============================================================================
// FILE: device_model.dart
// PURPOSE: Data model representing a Raspberry Pi camera device
// 
// This file defines the DeviceModel class which represents a smart cabinet
// camera device (Raspberry Pi) in the system. It handles serialization and
// deserialization of device data from/to Firestore.
// 
// FIRESTORE STRUCTURE:
// devices/{deviceId} {
//   deviceId: String - Unique identifier (MAC address)
//   userId: String - Owner's Firebase Auth UID
//   status: String - 'online' or 'offline'
//   previewEnabled: bool - Whether preview streaming is active
//   calibrationRequested: bool - Whether calibration frame is requested
//   detectionEnabled: bool - Whether object detection is running
//   previewImage: String? - Base64 encoded JPEG preview image
//   calibrationImage: String? - Base64 encoded JPEG calibration frame
//   boundary: List<Map>? - Boundary line coordinates [{x, y}, {x, y}]
//   lastSeen: Timestamp - Last communication from device
//   cloud_server_ip: String? - Detection server IP address
//   cloud_server_port: int? - Detection server port (default 8485)
// }
// ============================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Model class representing a Raspberry Pi camera device
/// 
/// This class encapsulates all device state and configuration data.
/// It provides methods to convert between Firestore documents and
/// Dart objects (serialization/deserialization).
class DeviceModel {
  final String deviceId;
  final String? userId;
  final Timestamp? lastSeen;
  final String status;
  final bool previewEnabled;
  final bool calibrationRequested;
  final bool detectionEnabled;
  final String? previewImage;
  final Timestamp? previewTs;
  final String? calibrationImage;
  final Timestamp? calibrationTs;
  final Map<String, dynamic>? boundary;

  DeviceModel({
    required this.deviceId,
    this.userId,
    this.lastSeen,
    this.status = 'offline',
    this.previewEnabled = false,
    this.calibrationRequested = false,
    this.detectionEnabled = false,
    this.previewImage,
    this.previewTs,
    this.calibrationImage,
    this.calibrationTs,
    this.boundary,
  });

  /// Creates a DeviceModel from a Firestore DocumentSnapshot
  /// 
  /// This factory method deserializes Firestore document data into a
  /// DeviceModel object. It handles type conversions and null safety.
  /// 
  /// Parameters:
  ///   - doc: Firestore DocumentSnapshot containing device data
  /// 
  /// Returns: DeviceModel instance with data from Firestore
  /// 
  /// Example:
  /// ```dart
  /// final docSnapshot = await FirebaseFirestore.instance
  ///     .collection('devices')
  ///     .doc(deviceId)
  ///     .get();
  /// final device = DeviceModel.fromFirestore(docSnapshot);
  /// ```
  factory DeviceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) {
      return DeviceModel(deviceId: doc.id);
    }

    return DeviceModel(
      deviceId: doc.id,
      userId: data['userId'] as String?,
      lastSeen: data['lastSeen'] as Timestamp?,
      status: data['status'] as String? ?? 'offline',
      previewEnabled: data['preview_enabled'] as bool? ?? false,
      calibrationRequested: data['calibration_requested'] as bool? ?? false,
      detectionEnabled: data['detection_enabled'] as bool? ?? false,
      previewImage: data['preview_image'] as String?,
      previewTs: data['preview_ts'] as Timestamp?,
      calibrationImage: data['calibration_image'] as String?,
      calibrationTs: data['calibration_ts'] as Timestamp?,
      boundary: data['boundary'] as Map<String, dynamic>?,
    );
  }

  /// Converts this DeviceModel to a Firestore-compatible map
  /// 
  /// This method serializes the device data into a Map that can be
  /// written to Firestore. Timestamp fields are converted to Firestore
  /// Timestamp objects.
  /// 
  /// Returns: Map<String, dynamic> ready for Firestore storage
  /// 
  /// Example:
  /// ```dart
  /// await FirebaseFirestore.instance
  ///     .collection('devices')
  ///     .doc(device.deviceId)
  ///     .set(device.toFirestore());
  /// ```
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'lastSeen': lastSeen,
      'status': status,
      'preview_enabled': previewEnabled,
      'calibration_requested': calibrationRequested,
      'detection_enabled': detectionEnabled,
      'preview_image': previewImage,
      'preview_ts': previewTs,
      'calibration_image': calibrationImage,
      'calibration_ts': calibrationTs,
      'boundary': boundary,
    };
  }

  /// Creates a copy of this DeviceModel with updated fields
  /// 
  /// This method implements the immutable data pattern, allowing you to
  /// create a new DeviceModel with some fields changed while keeping
  /// others unchanged.
  /// 
  /// All parameters are optional. Only provided parameters will be updated
  /// in the new instance.
  /// 
  /// Returns: New DeviceModel instance with updated fields
  /// 
  /// Example:
  /// ```dart
  /// final updatedDevice = device.copyWith(
  ///   status: 'offline',
  ///   previewEnabled: false,
  /// );
  /// ```
  DeviceModel copyWith({
    String? userId,
    Timestamp? lastSeen,
    String? status,
    bool? previewEnabled,
    bool? calibrationRequested,
    bool? detectionEnabled,
    String? previewImage,
    Timestamp? previewTs,
    String? calibrationImage,
    Timestamp? calibrationTs,
    Map<String, dynamic>? boundary,
  }) {
    return DeviceModel(
      deviceId: deviceId,
      userId: userId ?? this.userId,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      previewEnabled: previewEnabled ?? this.previewEnabled,
      calibrationRequested: calibrationRequested ?? this.calibrationRequested,
      detectionEnabled: detectionEnabled ?? this.detectionEnabled,
      previewImage: previewImage ?? this.previewImage,
      previewTs: previewTs ?? this.previewTs,
      calibrationImage: calibrationImage ?? this.calibrationImage,
      calibrationTs: calibrationTs ?? this.calibrationTs,
      boundary: boundary ?? this.boundary,
    );
  }
}
