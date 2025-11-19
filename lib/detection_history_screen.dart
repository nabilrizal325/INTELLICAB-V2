// ============================================================================
// FILE: detection_history_screen.dart
// PURPOSE: Display and manage detection events from smart cabinet camera
// 
// This screen shows all object detection events for a specific device,
// allowing users to review, edit, apply to inventory, or ignore detections.
// 
// FEATURES:
// - Real-time list of detection events (StreamBuilder)
// - Detection thumbnails (base64 decoded images)
// - Item name, confidence score, timestamp display
// - Direction indicators (IN=green arrow, OUT=orange arrow)
// - Status badges (APPLIED, IGNORED)
// - Action buttons for unprocessed detections (Edit, Apply, Ignore)
// 
// DETECTION WORKFLOW:
// 1. Pi/cloud server logs detection to Firestore:
//    - devices/{deviceId}/detections/{detectionId}
// 2. This screen displays all detections in real-time
// 3. User can:
//    - Edit: Correct item name before applying
//    - Apply: Update inventory based on detection
//    - Ignore: Mark as false positive
// 4. Processed detections show badges and hide action buttons
// 
// FIRESTORE STRUCTURE (per detection):
// {
//   timestamp: Timestamp,
//   item_name: String,        // Detected item from YOLO
//   confidence: double,       // Detection confidence (0.0-1.0)
//   direction: String,        // 'in' or 'out'
//   image_base64: String,     // Thumbnail of detected object
//   processed: bool,          // Has user taken action?
//   ignored: bool,            // Is this a false positive?
//   processedAt: Timestamp,   // When user processed it
//   finalItemName: String,    // Corrected name (if edited)
//   inventoryUpdated: bool    // Did it update inventory?
// }
// 
// NAVIGATION:
// - From: CameraScreen → History icon button
// - To: (Modal) Edit dialog, Apply confirmation, Ignore confirmation
// 
// UI COMPONENTS:
// - StreamBuilder for real-time detection list
// - Card-based detection items with thumbnails
// - AlertDialogs for edit/confirm actions
// - SnackBars for success/error feedback
// - Status badges for processed detections
// ============================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'device_service.dart';

/// Screen displaying detection history for a specific device
/// 
/// Shows all detection events with thumbnails, confidence scores,
/// and allows users to edit, apply, or ignore each detection.
class DetectionHistoryScreen extends StatelessWidget {
  /// Device ID whose detection history to display
  final String deviceId;

  const DetectionHistoryScreen({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Detection History',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('devices')
            .doc(deviceId)
            .collection('detections')
            .orderBy('timestamp', descending: true)
            .limit(50)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final detections = snapshot.data?.docs ?? [];

          if (detections.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No detections yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Enable detection to start monitoring',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: detections.length,
            itemBuilder: (context, index) {
              final doc = detections[index];
              final detection = doc.data() as Map<String, dynamic>;
              return _DetectionCard(
                detectionId: doc.id,
                deviceId: deviceId,
                detection: detection,
              );
            },
          );
        },
      ),
    );
  }
}

class _DetectionCard extends StatelessWidget {
  final String detectionId;
  final String deviceId;
  final Map<String, dynamic> detection;

  const _DetectionCard({
    required this.detectionId,
    required this.deviceId,
    required this.detection,
  });

  @override
  Widget build(BuildContext context) {
    final timestamp = (detection['timestamp'] as Timestamp?)?.toDate();
    final imageBase64 = detection['image_base64'] as String?;
    final itemName = detection['item_name'] as String? ?? 'Unknown item';
    final confidence = detection['confidence'] as double? ?? 0.0;
    final direction = detection['direction'] as String? ?? 'unknown';
    final processed = detection['processed'] as bool? ?? false;
    final ignored = detection['ignored'] as bool? ?? false;
    final matchScore = detection['matchScore'] as double?;
    final matchedItemName = detection['matchedItemName'] as String?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          // Show full image dialog
          if (imageBase64 != null) {
            _showImageDialog(context, imageBase64, itemName, timestamp);
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Thumbnail
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: imageBase64 != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _buildImageFromBase64(imageBase64),
                      )
                    : const Icon(Icons.image_not_supported),
              ),
              const SizedBox(width: 12),
              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            itemName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _DirectionIcon(direction: direction),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'Confidence: ${(confidence * 100).toStringAsFixed(1)}%',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        if (processed) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: ignored ? Colors.grey[300] : Colors.green[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ignored ? 'IGNORED' : 'APPLIED',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: ignored ? Colors.grey[700] : Colors.green[700],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (matchedItemName != null && matchScore != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.link, size: 12, color: Colors.green[600]),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Matched: $matchedItemName (${(matchScore * 100).toStringAsFixed(0)}%)',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.green[700],
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (timestamp != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, y - h:mm a').format(timestamp),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                    if (!processed) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ActionButton(
                            label: 'Edit',
                            icon: Icons.edit,
                            onPressed: () => _showEditDialog(context),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'Apply',
                            icon: Icons.check,
                            onPressed: () => _confirmApply(context),
                          ),
                          const SizedBox(width: 8),
                          _ActionButton(
                            label: 'Ignore',
                            icon: Icons.close,
                            onPressed: () => _confirmIgnore(context),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: detection['item_name'] as String? ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Item Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Item Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applyDetection(context, correctedItemName: controller.text.trim());
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  void _confirmApply(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Apply Detection'),
        content: Text(
          'This will update your inventory based on this detection:\n\n'
          'Item: ${detection['item_name']}\n'
          'Direction: ${detection['direction']}\n\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applyDetection(context);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyDetection(BuildContext context, {String? correctedItemName}) async {
    try {
      final deviceService = DeviceService();
      await deviceService.processDetection(
        detectionId: detectionId,
        deviceId: deviceId,
        itemName: detection['item_name'] as String? ?? 'Unknown',
        direction: detection['direction'] as String? ?? 'unknown',
        correctedItemName: correctedItemName,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Detection applied to inventory'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _confirmIgnore(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ignore Detection'),
        content: const Text(
          'Mark this detection as a false positive?\n\n'
          'This will not affect your inventory.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _ignoreDetection(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
            child: const Text('Ignore'),
          ),
        ],
      ),
    );
  }

  Future<void> _ignoreDetection(BuildContext context) async {
    try {
      final deviceService = DeviceService();
      await deviceService.ignoreDetection(deviceId, detectionId);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Detection ignored'),
            backgroundColor: Colors.grey,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildImageFromBase64(String base64String) {
    try {
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',').last;
      }
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.broken_image);
        },
      );
    } catch (e) {
      return const Icon(Icons.error_outline, color: Colors.red);
    }
  }

  void _showImageDialog(BuildContext context, String imageBase64, String itemName, DateTime? timestamp) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(maxHeight: 500),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _buildImageFromBase64(imageBase64),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  if (timestamp != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('MMMM d, y - h:mm:ss a').format(timestamp),
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 14),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          minimumSize: const Size(0, 28),
          side: BorderSide(color: Colors.grey[400]!),
        ),
      ),
    );
  }
}

class _DirectionIcon extends StatelessWidget {
  final String direction;

  const _DirectionIcon({required this.direction});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (direction.toLowerCase()) {
      case 'in':
        icon = Icons.arrow_downward;
        color = Colors.green;
        break;
      case 'out':
        icon = Icons.arrow_upward;
        color = Colors.orange;
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 16, color: color),
    );
  }
}
