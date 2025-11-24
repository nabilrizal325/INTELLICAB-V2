import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class CabinetDetailsPage extends StatefulWidget {
  final String title;
  final String deviceId; // Device ID or 'unorganized'
  final bool isUnorganized; // True if viewing unorganized items

  const CabinetDetailsPage({
    super.key,
    required this.title,
    required this.deviceId,
    this.isUnorganized = false,
  });

  @override
  State<CabinetDetailsPage> createState() => _CabinetDetailsPageState();
}

class _CabinetDetailsPageState extends State<CabinetDetailsPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Map itemId -> detection status ('in'/'out'/'unknown')
  final Map<String, String> _itemStatus = {};
  StreamSubscription<QuerySnapshot>? _detectionSub;
  
  String? _editingDeviceName;

  // Helper method to safely format timestamp
  String _formatDate(dynamic timeStamp) {
    if (timeStamp == null) return 'Unknown';
    if (timeStamp is Timestamp) {
      final dt = timeStamp.toDate();
      return DateFormat('dd/MM/yyyy').format(dt);
    } else if (timeStamp is String) {
      final s = timeStamp.trim();
      // Try parsing common date formats, fallback to returning the raw string
      final formats = ['dd/MM/yyyy', 'yyyy-MM-dd', 'MM/dd/yyyy'];
      for (final fmt in formats) {
        try {
          final dt = DateFormat(fmt).parseStrict(s);
          return DateFormat('dd/MM/yyyy').format(dt);
        } catch (_) {
          // try next
        }
      }
      // If parsing failed but string is non-empty, return it as-is
      return s;
    } else {
      return 'Unknown';
    }
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isUnorganized) {
      _initDetectionListener();
    }
  }

  void _initDetectionListener() {
    if (widget.deviceId.isEmpty) return;
    
    // Listen to device detections
    final coll = FirebaseFirestore.instance
        .collection('devices')
        .doc(widget.deviceId)
        .collection('detections');

    // Listen to detection events and calculate status
    _detectionSub = coll
        .orderBy('timestamp', descending: true)
        .snapshots()
        .listen((snapshot) async {
      final Map<String, String> newStatus = {};
      
      // Get user's inventory to match with detections
      final userId = _auth.currentUser?.uid;
      if (userId == null) return;
      
      final inventorySnapshot = await FirebaseFirestore.instance
          .collection('User')
          .doc(userId)
          .collection('inventory')
          .where('deviceId', isEqualTo: widget.deviceId)
          .get();
      
      // For each inventory item, find latest matching detection
      for (var invDoc in inventorySnapshot.docs) {
        final invData = invDoc.data();
        final itemId = invDoc.id;
        final itemName = invData['name'] as String? ?? '';
        
        // Find latest detection that matches this item
        String? latestDirection;
        DateTime? latestTime;
        
        for (var detDoc in snapshot.docs) {
          final detData = detDoc.data() as Map<String, dynamic>?;
          if (detData == null) continue;
          
          final matchedItemName = detData['matchedItemName'] as String?;
          final direction = detData['direction'] as String?;
          final timestamp = detData['timestamp'] as Timestamp?;
          
          // Check if this detection matches current inventory item
          if (matchedItemName != null && matchedItemName == itemName) {
            if (timestamp != null) {
              final detTime = timestamp.toDate();
              if (latestTime == null || detTime.isAfter(latestTime)) {
                latestTime = detTime;
                latestDirection = direction;
              }
            }
          }
        }
        
        if (latestDirection != null) {
          newStatus[itemId] = latestDirection == 'in' ? 'in' : 'out';
        } else {
          newStatus[itemId] = 'unknown';
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
  
  Future<void> _updateDeviceName(String newName) async {
    if (newName.trim().isEmpty || widget.isUnorganized) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('devices')
          .doc(widget.deviceId)
          .update({'name': newName.trim()});
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Device name updated to "$newName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _showEditDeviceNameDialog() {
    final controller = TextEditingController(text: widget.title);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Device Name'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Device Name',
            border: OutlineInputBorder(),
            hintText: 'e.g., Kitchen Cabinet',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateDeviceName(controller.text);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _detectionSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userId = _auth.currentUser?.uid;
    
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 250, 249, 246),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (!widget.isUnorganized)
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.black, size: 20),
                onPressed: _showEditDeviceNameDialog,
                tooltip: 'Edit device name',
              ),
          ],
        ),
      ),
      body: userId == null
          ? const Center(child: Text('Please log in'))
          : StreamBuilder<QuerySnapshot>(
              stream: widget.isUnorganized
                  ? FirebaseFirestore.instance
                      .collection('User')
                      .doc(userId)
                      .collection('inventory')
                      .snapshots()
                  : FirebaseFirestore.instance
                      .collection('User')
                      .doc(userId)
                      .collection('inventory')
                      .where('deviceId', isEqualTo: widget.deviceId)
                      .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                var allItems = snapshot.data?.docs ?? [];
                
                // Filter items based on type
                List<QueryDocumentSnapshot> items;
                if (widget.isUnorganized) {
                  // For unorganized: include items WITHOUT a deviceId or with empty/unorganized deviceId
                  items = allItems.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final cabinetId = data['cabinetId']?.toString() ?? '';
                    final deviceId = data['deviceId']?.toString() ?? '';
                    
                    // Item is unorganized if:
                    // 1. cabinetId is 'unorganized', OR
                    // 2. deviceId is empty, 'null', or 'unorganized'
                    // 3. cabinetId is empty or 'null' AND deviceId is also empty/null
                    return cabinetId == 'unorganized' || 
                           deviceId == 'unorganized' ||
                           deviceId.isEmpty ||
                           deviceId == 'null' ||
                           (cabinetId.isEmpty || cabinetId == 'null');
                  }).toList();
                } else {
                  // For device: already filtered by query
                  items = allItems;
                }

                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, 
                             size: 64, 
                             color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          widget.isUnorganized 
                              ? 'No unorganized items'
                              : 'This cabinet is empty',
                          style: TextStyle(
                            fontSize: 18, 
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.isUnorganized
                              ? 'Scan items to add them here'
                              : 'Items will appear when detected',
                          style: TextStyle(
                            fontSize: 14, 
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final doc = items[index];
                    final item = doc.data() as Map<String, dynamic>;
                    final itemId = doc.id;
                    final status = _itemStatus[itemId] ?? 'unknown';

                    Color statusColor;
                    String statusText;
                    if (status == 'in') {
                      statusColor = Colors.green;
                      statusText = 'In';
                    } else if (status == 'out') {
                      statusColor = Colors.red;
                      statusText = 'Out';
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
                          // Image
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
                                    child: Image.network(
                                      item['imageUrl'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) =>
                                          const Icon(Icons.broken_image, color: Colors.grey),
                                    ),
                                  )
                                : const Icon(Icons.image_not_supported, color: Colors.grey),
                          ),
                          const SizedBox(width: 12),

                          // Info
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
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Qty: ${item['quantity'] ?? 0}',
                                  style: const TextStyle(fontSize: 14),
                                ),
                                // Expiry date
                                if ((item['expiryDates'] != null && 
                                     item['expiryDates'] is List && 
                                     (item['expiryDates'] as List).isNotEmpty) ||
                                    (item['expiryDate'] != null && 
                                     item['expiryDate'] != ""))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      'Expiry: ${_formatDate((item['expiryDates'] is List && (item['expiryDates'] as List).isNotEmpty) ? (item['expiryDates'] as List).first : item['expiryDate'])}',
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

                          // Status indicator (only for device items, not unorganized)
                          if (!widget.isUnorganized)
                            Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8, 
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: statusColor),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.edit_outlined, 
                                    color: Colors.black,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    // TODO: Implement edit item functionality
                                  },
                                ),
                              ],
                            ),
                          
                          // For unorganized items, just show edit button
                          if (widget.isUnorganized)
                            IconButton(
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: Colors.black,
                              ),
                              onPressed: () {
                                // TODO: Implement edit item functionality
                              },
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
