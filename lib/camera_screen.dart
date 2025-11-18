import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'device_model.dart';
import 'device_service.dart';
import 'calibration_screen.dart';
import 'cloud_server_config_screen.dart';
import 'detection_history_screen.dart';

class CameraScreen extends StatefulWidget {
  final String deviceId;

  const CameraScreen({super.key, required this.deviceId});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final DeviceService _deviceService = DeviceService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Device ${widget.deviceId.substring(0, 8)}...',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => DetectionHistoryScreen(
                    deviceId: widget.deviceId,
                  ),
                ),
              );
            },
            tooltip: 'Detection History',
          ),
        ],
      ),
      body: StreamBuilder<DeviceModel>(
        stream: _deviceService.getDevice(widget.deviceId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: Text('Device not found'));
          }

          final device = snapshot.data!;
          final isOnline = device.status == 'online';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Status Card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Spacer(),
                        if (device.lastSeen != null)
                          Text(
                            'Last seen: ${_formatTimestamp(device.lastSeen!)}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Preview Section
                const Text(
                  'Camera Preview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Preview Image
                        Container(
                          height: 300,
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: device.previewImage != null && device.previewImage!.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: _buildImageFromBase64(device.previewImage!),
                                )
                              : Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.videocam_off,
                                          size: 48, color: Colors.grey[400]),
                                      const SizedBox(height: 8),
                                      Text(
                                        device.previewEnabled 
                                            ? 'Waiting for preview...'
                                            : 'No preview available',
                                        style: TextStyle(color: Colors.grey[600]),
                                      ),
                                    ],
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Toggle Preview Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isOnline
                                ? () => _deviceService.togglePreview(
                                      widget.deviceId,
                                      !device.previewEnabled,
                                    )
                                : null,
                            icon: Icon(
                              device.previewEnabled
                                  ? Icons.videocam_off
                                  : Icons.videocam,
                            ),
                            label: Text(
                              device.previewEnabled
                                  ? 'Stop Preview'
                                  : 'Start Preview',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: device.previewEnabled
                                  ? Colors.red.shade100
                                  : Colors.pinkAccent.shade100,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Calibration Section
                const Text(
                  'Calibration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (device.boundary != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.green.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.green.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle,
                                    color: Colors.green.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'Boundary configured',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          )
                        else
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                const Text(
                                  'No boundary set',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        
                        ElevatedButton.icon(
                          onPressed: isOnline
                              ? () async {
                                  try {
                                    await _deviceService.requestCalibration(widget.deviceId);
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Calibration requested. Waiting for image...'),
                                        duration: Duration(seconds: 2),
                                      ),
                                    );
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Error: $e')),
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Request Calibration Frame'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.pinkAccent.shade100,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        
                        if (device.calibrationImage != null)
                          ElevatedButton.icon(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CalibrationScreen(
                                    deviceId: widget.deviceId,
                                    calibrationImageBase64: device.calibrationImage!,
                                    existingBoundary: device.boundary,
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.edit),
                            label: const Text('Draw Boundary'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade100,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Detection Section
                const Text(
                  'Detection',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (device.boundary == null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Please set boundary before enabling detection',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 12),
                        
                        SwitchListTile(
                          title: const Text(
                            'Enable Detection',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            device.detectionEnabled
                                ? 'Pi is monitoring for items'
                                : 'Detection is off',
                            style: TextStyle(
                              color: device.detectionEnabled
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                          ),
                          value: device.detectionEnabled,
                          onChanged: isOnline && device.boundary != null
                              ? (value) => _deviceService.toggleDetection(
                                    widget.deviceId,
                                    value,
                                  )
                              : null,
                          activeColor: Colors.green,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Cabinet Link Section
                _buildCabinetLinkSection(device),
                const SizedBox(height: 20),

                // Cloud Server Section
                const Text(
                  'Cloud Server',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        StreamBuilder<DocumentSnapshot>(
                          stream: FirebaseFirestore.instance
                              .collection('devices')
                              .doc(widget.deviceId)
                              .snapshots(),
                          builder: (context, snapshot) {
                            final data = snapshot.data?.data() as Map<String, dynamic>?;
                            final serverIp = data?['cloud_server_ip'] as String?;
                            final serverPort = data?['cloud_server_port'] as int?;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (serverIp != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.cloud, color: Colors.green.shade700),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text(
                                                'Server configured',
                                                style: TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              Text(
                                                '$serverIp:${serverPort ?? 8485}',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade50,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.cloud_off, color: Colors.orange.shade700),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          child: Text(
                                            'No cloud server configured',
                                            style: TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => CloudServerConfigScreen(
                                  deviceId: widget.deviceId,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('Configure Server'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCabinetLinkSection(DeviceModel device) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Cabinet Link',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('devices')
                  .doc(widget.deviceId)
                  .snapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final cabinetId = data?['cabinetId'] as String?;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cabinetId != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Linked to cabinet',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    cabinetId,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.link_off, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Not linked to a cabinet',
                                    style: TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    'Link this device to enable inventory updates',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showCabinetSelector(context),
                      icon: const Icon(Icons.link),
                      label: Text(cabinetId != null ? 'Change Cabinet' : 'Link to Cabinet'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade100,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showCabinetSelector(BuildContext context) async {
    final user = await FirebaseFirestore.instance
        .collection('User')
        .doc(FirebaseFirestore.instance.collection('User').doc().id)
        .get();

    final userId = user.id;
    final cabinetsSnapshot = await FirebaseFirestore.instance
        .collection('User')
        .doc(userId)
        .collection('inventory')
        .get();

    // Extract unique cabinet IDs
    final cabinetIds = <String>{};
    for (var doc in cabinetsSnapshot.docs) {
      final cabinetId = doc.data()['cabinetId'] as String?;
      if (cabinetId != null && cabinetId.isNotEmpty) {
        cabinetIds.add(cabinetId);
      }
    }

    if (!context.mounted) return;

    if (cabinetIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No cabinets found. Add items to your inventory first.'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Cabinet'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: cabinetIds.length,
            itemBuilder: (context, index) {
              final cabinetId = cabinetIds.elementAt(index);
              return ListTile(
                leading: const Icon(Icons.kitchen),
                title: Text(cabinetId),
                onTap: () async {
                  Navigator.pop(context);
                  try {
                    await _deviceService.linkDeviceToCabinet(
                      widget.deviceId,
                      cabinetId,
                    );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('✅ Device linked to $cabinetId'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('❌ Error: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildImageFromBase64(String base64String) {
    try {
      // Remove data URL prefix if present (e.g., "data:image/jpeg;base64,")
      String cleanBase64 = base64String;
      if (base64String.contains(',')) {
        cleanBase64 = base64String.split(',').last;
      }
      
      // Remove any whitespace
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Image decode error: $error');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 48, color: Colors.grey[600]),
                const SizedBox(height: 8),
                Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Base64 decode error: $e');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 8),
            Text(
              'Invalid image data',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';
    
    try {
      DateTime dateTime;
      if (timestamp is DateTime) {
        dateTime = timestamp;
      } else {
        dateTime = timestamp.toDate();
      }
      
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Unknown';
    }
  }
}
