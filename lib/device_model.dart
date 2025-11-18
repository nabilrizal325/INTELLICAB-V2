import 'package:cloud_firestore/cloud_firestore.dart';

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
