import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CabinetDetailsPage extends StatefulWidget {
  final String title;
  final String cabinetId;
  final List<Map<String, dynamic>> items;

  const CabinetDetailsPage({
    super.key,
    required this.title,
    required this.cabinetId,
    required this.items,
  });

  @override
  State<CabinetDetailsPage> createState() => _CabinetDetailsPageState();
}

class _CabinetDetailsPageState extends State<CabinetDetailsPage> {
  // Map key: itemId (inventory doc id) or brand|name fallback -> 'in'/'out'/'unknown'
  final Map<String, String> _itemStatus = {};
  StreamSubscription<QuerySnapshot>? _detectionSub;

  // Helper method to safely format timestamp
  String _formatDate(dynamic timeStamp) {
    if (timeStamp == null) return 'Unknown';
    if (timeStamp is Timestamp) {
      return timeStamp.toDate().toString().split(' ')[0];
    } else if (timeStamp is String) {
      return timeStamp.split(' ')[0];
    } else {
      return 'Unknown';
    }
  }

  @override
  void initState() {
    super.initState();
    _initDetectionListener();
  }

  void _initDetectionListener() {
    // Prefer listening to raspberry_pi/{deviceId}/detections if any item has a deviceId.
    // Otherwise fall back to cabinet/{cabinetId}/detection.
    String? deviceId;
    for (final item in widget.items) {
      if (item['deviceId'] != null && item['deviceId'].toString().isNotEmpty) {
        deviceId = item['deviceId'].toString();
        break;
      }
    }

    late final CollectionReference coll;
    if (deviceId != null && deviceId.isNotEmpty) {
      // YOLO script writes to: raspberry_pi/{device_id}/detections
      coll = FirebaseFirestore.instance.collection('raspberry_pi').doc(deviceId).collection('detections');
    } else {
      if (widget.cabinetId.isEmpty) return;
      coll = FirebaseFirestore.instance.collection('cabinet').doc(widget.cabinetId).collection('detection');
    }

    // Listen to real-time detection events
    _detectionSub = coll.snapshots().listen((snapshot) {
      // Build latest status per item.
      // Detection documents are expected to have at least: 'itemId' (inventory doc id) or 'label', 'status' ('in'/'out'), and 'timestamp'.
      final Map<String, Map<String, dynamic>> latestByKey = {};

      for (var doc in snapshot.docs) {
        final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final ts = data['timestamp'];
        // key preference: itemId, then item (YOLO script uses 'item'), then label/name
        String key = '';
        if (data['itemId'] != null) {
          key = data['itemId'].toString();
        } else if (data['item'] != null) {
          // YOLO script sends detected class name in 'item'
          key = data['item'].toString();
        } else if (data['label'] != null) {
          key = data['label'].toString();
        } else if (data['name'] != null) {
          key = data['name'].toString();
        }

        if (key.isEmpty) continue;

        final existing = latestByKey[key];
        if (existing == null) {
          final map = Map<String, dynamic>.from(data);
          map['_docId'] = doc.id;
          latestByKey[key] = map;
        } else {
          // Compare timestamps if available
          try {
            final existingTs = existing['timestamp'];
            DateTime e = existingTs is Timestamp ? existingTs.toDate() : DateTime.tryParse(existingTs.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            DateTime c = ts is Timestamp ? ts.toDate() : DateTime.tryParse(ts.toString()) ?? DateTime.fromMillisecondsSinceEpoch(0);
            if (c.isAfter(e)) {
              final map = Map<String, dynamic>.from(data);
              map['_docId'] = doc.id;
              latestByKey[key] = map;
            }
          } catch (_) {
            final map = Map<String, dynamic>.from(data);
            map['_docId'] = doc.id;
            latestByKey[key] = map;
          }
        }
      }

      // Map detection keys to inventory items. Use item['id'] if available, otherwise brand|name.
      final Map<String, String> newStatus = {};
      for (final item in widget.items) {
        final id = item['id']?.toString() ?? '';
        final fallback = '${item['brand'] ?? ''}|${item['name'] ?? ''}';

        if (id.isNotEmpty && latestByKey.containsKey(id)) {
          var raw = latestByKey[id]?['status']?.toString() ?? 'unknown';
          // Map YOLO script statuses to app statuses
          if (raw == 'added') raw = 'in';
          if (raw == 'removed') raw = 'out';
          newStatus[id] = raw;
        } else if (latestByKey.containsKey(fallback)) {
          var raw = latestByKey[fallback]?['status']?.toString() ?? 'unknown';
          if (raw == 'added') raw = 'in';
          if (raw == 'removed') raw = 'out';
          newStatus[fallback] = raw;
        } else {
          // not found -> unknown
          if (id.isNotEmpty) {
            newStatus[id] = 'unknown';
          } else {
            newStatus[fallback] = 'unknown';
          }
        }
      }

      if (mounted) {
        setState(() {
          _itemStatus.clear();
          _itemStatus.addAll(newStatus);
        });
      }
    }, onError: (e) {
      debugPrint('Detection listener error: $e');
    });
  }

  @override
  void dispose() {
    _detectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 250, 249, 246),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.items.length,
        itemBuilder: (context, index) {
          final item = widget.items[index];
          final id = item['id']?.toString() ?? '';
          final fallback = '${item['brand'] ?? ''}|${item['name'] ?? ''}';
          final status = _itemStatus[id.isNotEmpty ? id : fallback] ?? 'unknown';

          Color statusColor;
          String statusText;
          if (status == 'in') {
            statusColor = Colors.green;
            statusText = 'In cabinet';
          } else if (status == 'out') {
            statusColor = Colors.red;
            statusText = 'Out of cabinet';
          } else {
            statusColor = Colors.grey;
            statusText = 'Unknown';
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 248, 207, 255),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 🖼 Image
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: item['imageUrl'] != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(item['imageUrl'], fit: BoxFit.cover),
                        )
                      : const Icon(Icons.image_not_supported, color: Colors.grey),
                ),
                const SizedBox(width: 12),

                // 🧾 Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['brand'] ?? 'Unknown Brand',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item['name'] ?? 'Unnamed Item',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Qty: ${item['quantity'] ?? 0}',
                        style: const TextStyle(fontSize: 14),
                      ),
                      if (item['expiryDate'] != null && item['expiryDate'] != "")
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Expiry: ${_formatDate(item['expiryDate'])}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                    // Status indicator + Edit button
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: statusColor),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Colors.black),
                          onPressed: () {
                            // TODO: Implement edit functionality
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              
            );
        },
      ),
    );
  }
}
