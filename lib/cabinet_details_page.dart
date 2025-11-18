import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final Map<String, String> _itemStatus = {};
  StreamSubscription<QuerySnapshot>? _detectionSub;
  final _auth = FirebaseAuth.instance;
  List<Map<String, dynamic>> _currentItems = [];

  @override
  void initState() {
    super.initState();
    _currentItems = List.from(widget.items);
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
    String? deviceId;
    for (final item in _currentItems) {
      if (item['deviceId'] != null && item['deviceId'].toString().isNotEmpty) {
        deviceId = item['deviceId'].toString();
        break;
      }
    }

    late final CollectionReference coll;
    if (deviceId != null && deviceId.isNotEmpty) {
      coll = FirebaseFirestore.instance
          .collection('raspberry_pi')
          .doc(deviceId)
          .collection('detections');
    } else {
      if (widget.cabinetId.isEmpty) return;
      coll = FirebaseFirestore.instance
          .collection('cabinet')
          .doc(widget.cabinetId)
          .collection('detection');
    }

    _detectionSub = coll.snapshots().listen((snapshot) {
      final Map<String, Map<String, dynamic>> latestByKey = {};

      for (var doc in snapshot.docs) {
        final Map<String, dynamic>? data = doc.data() as Map<String, dynamic>?;
        if (data == null) continue;
        final ts = data['timestamp'];
        String key = '';
        if (data['itemId'] != null) key = data['itemId'].toString();
        else if (data['item'] != null) key = data['item'].toString();
        else if (data['label'] != null) key = data['label'].toString();
        else if (data['name'] != null) key = data['name'].toString();
        if (key.isEmpty) continue;

        final existing = latestByKey[key];
        if (existing == null) {
          final map = Map<String, dynamic>.from(data);
          map['_docId'] = doc.id;
          latestByKey[key] = map;
        } else {
          try {
            final existingTs = existing['timestamp'];
            DateTime e = existingTs is Timestamp
                ? existingTs.toDate()
                : DateTime.tryParse(existingTs.toString()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
            DateTime c = ts is Timestamp
                ? ts.toDate()
                : DateTime.tryParse(ts.toString()) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
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

      final Map<String, String> newStatus = {};
      for (final item in _currentItems) {
        final id = item['id']?.toString() ?? '';
        final fallback = '${item['brand'] ?? ''}|${item['name'] ?? ''}';
        if (id.isNotEmpty && latestByKey.containsKey(id)) {
          var raw = latestByKey[id]?['status']?.toString() ?? 'unknown';
          if (raw == 'added') raw = 'in';
          if (raw == 'removed') raw = 'out';
          newStatus[id] = raw;
        } else if (latestByKey.containsKey(fallback)) {
          var raw = latestByKey[fallback]?['status']?.toString() ?? 'unknown';
          if (raw == 'added') raw = 'in';
          if (raw == 'removed') raw = 'out';
          newStatus[fallback] = raw;
        } else {
          if (id.isNotEmpty) newStatus[id] = 'unknown';
          else newStatus[fallback] = 'unknown';
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
        // Update in Firestore - using inventory collection
        final updateData = {
          'brand': newBrand,
          'name': newName,
          'quantity': newQty,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // Only update expiryDates array if expiry date is not empty
        if (newExpiry.isNotEmpty) {
          updateData['expiryDates'] = [newExpiry]; // Store as array with single date
          debugPrint('✅ Updating expiryDates to: [$newExpiry]');
        }

        // Also delete old expiryDate field if it exists (cleanup)
        await _getInventoryCollection().doc(id).update({
          ...updateData,
          'expiryDate': FieldValue.delete(),
        });

        // Update local state
        setState(() {
          _currentItems[index] = {
            ..._currentItems[index],
            'brand': newBrand,
            'name': newName,
            'quantity': newQty,
            'expiryDates': newExpiry.isNotEmpty ? [newExpiry] : null,
            'expiryDate': null, // Remove old field
          };
        });

        // Update grocery list
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

    // Clean up controllers
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
        // Get item data before deletion for grocery list update
        final item = _currentItems[index];
        final brand = item['brand'] ?? '';
        final name = item['name'] ?? '';
        final qty = item['quantity'] ?? 0;

        // Delete from Firestore - using inventory collection
        await _getInventoryCollection().doc(itemId).delete();

        // Update local state
        setState(() {
          _currentItems.removeAt(index);
        });

        // Remove from grocery list if needed
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
      body: _currentItems.isEmpty
          ? const Center(
              child: Text(
                'No items in this cabinet',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _currentItems.length,
              itemBuilder: (context, index) {
                final item = _currentItems[index];
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
                                onPressed: () => _deleteItem(id, index),
                              ),
                            ],
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