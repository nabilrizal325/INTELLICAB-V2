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
  final FirebaseAuth _auth = FirebaseAuth.instance;
  
  // Map itemId -> detection status ('in'/'out'/'unknown')
  final Map<String, String> _itemStatus = {};
  StreamSubscription<QuerySnapshot>? _detectionSub;

  @override
  void initState() {
    super.initState();
    _initDetectionListener();
    _migrateExpiryDateFormat(); // One-time migration to clean up data
  }

  /// Migrate all items from expiryDate to expiryDates array format
  Future<void> _migrateExpiryDateFormat() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final snapshot = await _getInventoryCollection().get();
      int migratedCount = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final hasExpiryDate = data['expiryDate'] != null;
        final hasExpiryDates = data['expiryDates'] is List && (data['expiryDates'] as List).isNotEmpty;

        if (hasExpiryDate && !hasExpiryDates) {
          // Migrate expiryDate to expiryDates
          final expiryDateStr = data['expiryDate'].toString();
          debugPrint('🔄 Migrating ${data['brand']} ${data['name']}: expiryDate "$expiryDateStr" → expiryDates');
          
          await _getInventoryCollection().doc(doc.id).update({
            'expiryDates': [expiryDateStr],
            'expiryDate': FieldValue.delete(),
          });
          migratedCount++;
        }
      }

      if (migratedCount > 0) {
        debugPrint('✅ Migration complete: $migratedCount items migrated to expiryDates format');
      }
    } catch (e) {
      debugPrint('❌ Migration error: $e');
    }
  }

  String _formatDate(dynamic timeStamp) {
    if (timeStamp == null) return 'Unknown';
    if (timeStamp is Timestamp) {
      final dt = timeStamp.toDate();
      return DateFormat('dd/MM/yyyy').format(dt);
    } else if (timeStamp is String) {
      final s = timeStamp.trim();
      final formats = [
        'dd-MM-yyyy',
        'dd/MM/yyyy',
        'yyyy-MM-dd',
        'yyyy/MM/dd',
        'dd.MM.yyyy',
        'MMM dd, yyyy'
      ];
      for (final fmt in formats) {
        try {
          final dt = DateFormat(fmt).parseStrict(s);
          return DateFormat('dd/MM/yyyy').format(dt);
        } catch (_) {}
      }
      return s;
    } else {
      return 'Unknown';
    }
  }

  // Helper to get first expiry date from either expiryDate or expiryDates
  String _getExpiryDate(Map<String, dynamic> item) {
    // Try expiryDate field first (single date)
    if (item['expiryDate'] != null && item['expiryDate'].toString().isNotEmpty) {
      return _formatDate(item['expiryDate']);
    }

    // Try expiryDates field (array of dates)
    if (item['expiryDates'] is List && (item['expiryDates'] as List).isNotEmpty) {
      final dates = item['expiryDates'] as List;
      if (dates.isNotEmpty && dates[0] != null) {
        return _formatDate(dates[0]);
      }
    }

    return '';
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

  // ---------------- AUTO-ADD / REMOVE GROCERY ----------------
  Future<void> _updateGroceryList(String brand, String name, int qty) async {
    final user = _auth.currentUser;
    if (user == null) return;

    debugPrint('📋 _updateGroceryList called: $brand $name (Qty: $qty)');

    final groceryRef = FirebaseFirestore.instance
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list');

    final existing = await groceryRef
        .where('brand', isEqualTo: brand)
        .where('name', isEqualTo: name)
        .limit(1)
        .get();

    debugPrint('📋 Found existing items: ${existing.docs.length}');

    if (qty <= 1) {
      // Add to grocery list if quantity is low and not already there
      if (existing.docs.isEmpty) {
        await groceryRef.add({
          'brand': brand,
          'name': name,
          'checked': false,
          'addedAt': FieldValue.serverTimestamp(),
          'autoAdded': true,
        });
        debugPrint('✅ Added to grocery list: $brand $name');
      } else {
        debugPrint('ℹ️ Item already in grocery list: $brand $name');
      }
    } else {
      // Remove from grocery list if quantity is sufficient
      if (existing.docs.isNotEmpty) {
        for (var doc in existing.docs) {
          final data = doc.data();
          // Only remove if it was auto-added (not manually added by user)
          if (data['autoAdded'] == true) {
            await groceryRef.doc(doc.id).delete();
            debugPrint('❌ Removed from grocery list: $brand $name');
          } else {
            debugPrint('ℹ️ Item was manually added, keeping in grocery list: $brand $name');
          }
        }
      } else {
        debugPrint('ℹ️ Item not in grocery list (nothing to remove): $brand $name');
      }
    }
  }

  // Get the correct inventory collection reference
  CollectionReference<Map<String, dynamic>> _getInventoryCollection() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    
    return FirebaseFirestore.instance
        .collection('User')
        .doc(user.uid)
        .collection('inventory');
  }

  Future<void> _editItem(Map<String, dynamic> item, int index) async {
    final id = item['id']?.toString();
    if (id == null || id.isEmpty) return;

    final brandController = TextEditingController(text: item['brand'] ?? '');
    final nameController = TextEditingController(text: item['name'] ?? '');
    final qtyController = TextEditingController(
        text: (item['quantity'] ?? 0).toString());
    
    // Get expiry date from expiryDates array first, then fallback to expiryDate
    String expiryDateValue = '';
    final expiryDates = item['expiryDates'];
    if (expiryDates is List && expiryDates.isNotEmpty) {
      final firstItem = expiryDates.first;
      if (firstItem is Timestamp) {
        expiryDateValue = DateFormat('dd/MM/yyyy').format(firstItem.toDate());
      } else {
        expiryDateValue = firstItem.toString().trim();
      }
    } else if (item['expiryDate'] != null && item['expiryDate'].toString().isNotEmpty) {
      expiryDateValue = item['expiryDate'].toString().trim();
    }
    
    final expiryController = TextEditingController(text: expiryDateValue);

    final result = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: brandController,
                  decoration: const InputDecoration(
                    labelText: 'Brand',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: qtyController,
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: expiryController,
                  decoration: const InputDecoration(
                    labelText: 'Expiry Date (dd/MM/yyyy)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.pop(context, false),
            ),
            ElevatedButton(
              child: const Text('Save'),
              onPressed: () {
                final newBrand = brandController.text.trim();
                final newName = nameController.text.trim();
                final newQty = int.tryParse(qtyController.text.trim()) ?? 0;
                final newExpiry = expiryController.text.trim();

                if (newBrand.isEmpty || newName.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Brand and name cannot be empty'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                if (newQty < 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Quantity cannot be negative'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Validate date format
                if (newExpiry.isNotEmpty) {
                  try {
                    DateFormat('dd/MM/yyyy').parseStrict(newExpiry);
                  } catch (_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter date in dd/MM/yyyy format'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                Navigator.pop(context, true);
              },
            ),
          ],
        );
      },
    );

    if (result == true) {
      final newBrand = brandController.text.trim();
      final newName = nameController.text.trim();
      final newQty = int.tryParse(qtyController.text.trim()) ?? 0;
      final newExpiry = expiryController.text.trim();

      try {
        final updateData = {
          'brand': newBrand,
          'name': newName,
          'quantity': newQty,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (newExpiry.isNotEmpty) {
          updateData['expiryDates'] = [newExpiry];
          debugPrint('✅ Updating expiryDates to: [$newExpiry]');
        }

        await _getInventoryCollection().doc(id).update({
          ...updateData,
          'expiryDate': FieldValue.delete(),
        });

        await _updateGroceryList(newBrand, newName, newQty);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    brandController.dispose();
    nameController.dispose();
    qtyController.dispose();
    expiryController.dispose();
  }

  Future<void> _deleteItem(String itemId, int index) async {
    if (itemId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Item'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Instead, get item data from Firestore
        final itemDoc = await _getInventoryCollection().doc(itemId).get();
        if (!itemDoc.exists) return;
        
        final item = itemDoc.data()!;
        final brand = item['brand'] ?? '';
        final name = item['name'] ?? '';
        final qty = item['quantity'] ?? 0;

        await _getInventoryCollection().doc(itemId).delete();

        if (qty <= 1) {
          final user = _auth.currentUser;
          if (user != null) {
            final groceryRef = FirebaseFirestore.instance
                .collection('User')
                .doc(user.uid)
                .collection('grocery_list');

            final existing = await groceryRef
                .where('brand', isEqualTo: brand)
                .where('name', isEqualTo: name)
                .limit(1)
                .get();

            for (var doc in existing.docs) {
              await groceryRef.doc(doc.id).delete();
            }
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Item deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete item: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                                  item['imageUrl']!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      const Icon(Icons.image_not_supported,
                                          color: Colors.grey),
                                ),
                              )
                            : const Icon(Icons.image_not_supported,
                                color: Colors.grey),
                      ),
                      const SizedBox(width: 12),
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
                            // Check both expiryDate and expiryDates
                            if (_getExpiryDate(item).isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  'Expiry: ${_getExpiryDate(item)}',
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
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
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
                                  fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    color: Colors.black, size: 20),
                                onPressed: () => _editItem(item, index),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete,
                                    color: Colors.red, size: 20),
                                onPressed: () => _deleteItem(itemId, index),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            );
              }
    )
    );
  }
}