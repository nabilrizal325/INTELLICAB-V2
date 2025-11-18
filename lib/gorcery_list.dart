import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class GroceryList extends StatefulWidget {
  const GroceryList({super.key});

  @override
  State<GroceryList> createState() => _GroceryListState();
}

class _GroceryListState extends State<GroceryList> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _newItemController = TextEditingController();
  final Map<String, DateTime> _lastProcessed = {};

  bool _isEditing = false;
  bool _isAdding = false;
  bool _initialized = false;
  bool _isInitializing = false;

  Stream<QuerySnapshot> _getGroceryList() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();
    return _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .orderBy('addedAt', descending: false)
        .snapshots();
  }

  // Get inventory collection reference
  CollectionReference<Map<String, dynamic>> _getInventoryCollection() {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('User not authenticated');
    }
    
    return _firestore
        .collection('User')
        .doc(user.uid)
        .collection('inventory');
  }

  // COMPLETELY CLEAN UP ALL DUPLICATES - KEEP ONLY ONE PER ITEM
  Future<void> _cleanupAllDuplicates() async {
    final user = _auth.currentUser;
    if (user == null) return;

    final groceryRef = _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list');

    final snapshot = await groceryRef.get();
    final Map<String, List<String>> itemToDocIds = {}; // normalized name -> [docIds]

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final brand = data['brand']?.toString().trim() ?? '';
      final name = data['name']?.toString().trim() ?? '';
      
      // Create normalized key: "brand name" or just "name"
      String key = '';
      if (brand.isNotEmpty && name.isNotEmpty) {
        key = '$brand $name'.toLowerCase();
      } else if (name.isNotEmpty) {
        key = name.toLowerCase();
      }
      
      if (key.isNotEmpty) {
        if (!itemToDocIds.containsKey(key)) {
          itemToDocIds[key] = [];
        }
        itemToDocIds[key]!.add(doc.id);
      }
    }

    // For each item with multiple entries, keep the auto-added one (or first one)
    final List<String> duplicatesToDelete = [];
    for (var entry in itemToDocIds.entries) {
      if (entry.value.length > 1) {
        // Multiple entries for same item - keep auto-added version, delete others
        bool foundAutoAdded = false;
        
        for (var docId in entry.value) {
          final docData = snapshot.docs.firstWhere((d) => d.id == docId).data();
          final isAutoAdded = docData['autoAdded'] == true;
          
          if (isAutoAdded && !foundAutoAdded) {
            foundAutoAdded = true;
            print('✅ KEEPING AUTO-ADDED: ${entry.key} ($docId)');
          } else {
            duplicatesToDelete.add(docId);
            print('🗑️ DELETE DUPLICATE of ${entry.key}: $docId');
          }
        }
      }
    }

    // Delete all duplicates
    for (String docId in duplicatesToDelete) {
      await groceryRef.doc(docId).delete();
    }
    
    if (duplicatesToDelete.isNotEmpty) {
      print('✅ Cleaned up ${duplicatesToDelete.length} duplicates');
    } else {
      print('ℹ️ No duplicates found');
    }
  }

  // STRONG AUTO-MANAGE WITH DUPLICATE PREVENTION
  Future<void> _autoManageGroceryItem(String brand, String name, int quantity) async {
    final user = _auth.currentUser;
    if (user == null) return;

    // ONLY auto-manage items that have BOTH brand AND name
    if (brand.isEmpty || name.isEmpty) {
      return;
    }

    final groceryRef = _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list');

    try {
      // Check for ANY existing items with same brand and name
      final existingQuery = await groceryRef
          .where('brand', isEqualTo: brand)
          .where('name', isEqualTo: name)
          .get();

      final bool itemExists = existingQuery.docs.isNotEmpty;

      if (quantity <= 1) {
        // Only add if NO items exist
        if (!itemExists) {
          await groceryRef.add({
            'brand': brand,
            'name': name,
            'checked': false,
            'addedAt': FieldValue.serverTimestamp(),
            'autoAdded': true,
          });
          print('✅ AUTO-ADDED: $brand $name (Qty: $quantity)');
        } else {
          print('ℹ️ ITEM EXISTS - Skip auto-add: $brand $name (Qty: $quantity)');
        }
      } else {
        // Remove ONLY if item exists and is auto-added
        if (itemExists) {
          for (var doc in existingQuery.docs) {
            final data = doc.data();
            if (data['autoAdded'] == true) {
              await groceryRef.doc(doc.id).delete();
              print('❌ AUTO-REMOVED: $brand $name (Qty: $quantity)');
            } else {
              print('ℹ️ MANUAL ITEM - Keep in list: $brand $name (Qty: $quantity)');
            }
          }
        } else {
          print('ℹ️ ITEM NOT FOUND - Nothing to remove: $brand $name (Qty: $quantity)');
        }
      }
    } catch (e) {
      print('❌ ERROR in autoManage: $e');
    }
  }

  // SIMPLIFIED INVENTORY LISTENER - Only responds to changes, not initial data
  void _setupInventoryListener() {
    final user = _auth.currentUser;
    if (user == null) return;

    _getInventoryCollection().snapshots().listen((snapshot) {
      // SKIP if still initializing
      if (_isInitializing) {
        print('⏭️ SKIP: Still initializing...');
        return;
      }
      
      // Process ONLY document changes (modified, added, removed)
      for (var docChange in snapshot.docChanges) {
        final data = docChange.doc.data();
        if (data == null) continue;
        
        final brand = data['brand']?.toString().trim() ?? '';
        final name = data['name']?.toString().trim() ?? '';
        final quantity = (data['quantity'] as num?)?.toInt() ?? 0;
        
        if (brand.isNotEmpty && name.isNotEmpty) {
          // Use normalized key matching _cleanupAllDuplicates
          final itemKey = '$brand $name'.toLowerCase();
          
          // For MODIFIED changes, always process (remove from debounce)
          if (docChange.type == DocumentChangeType.modified) {
            _lastProcessed.remove(itemKey); // Reset debounce for modified items
            print('🔄 LISTENER UPDATE (MODIFIED): $brand $name (Qty: $quantity)');
            _autoManageGroceryItem(brand, name, quantity);
          } else if (docChange.type == DocumentChangeType.added) {
            // For added items, respect debounce
            final now = DateTime.now();
            if (!_lastProcessed.containsKey(itemKey) || 
                now.difference(_lastProcessed[itemKey]!).inSeconds > 3) {
              _lastProcessed[itemKey] = now;
              print('🔄 LISTENER UPDATE (ADDED): $brand $name (Qty: $quantity)');
              _autoManageGroceryItem(brand, name, quantity);
            }
          }
        }
      }
    }, onError: (error) {
      print('❌ Inventory listener error: $error');
    });
  }

  Future<void> _addItemToGroceryList(String itemName) async {
    final user = _auth.currentUser;
    if (user == null || itemName.trim().isEmpty) return;

    final groceryRef = _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list');

    // STRONG duplicate check for manual items
    final existingQuery = await groceryRef
        .where('name', isEqualTo: itemName.trim())
        .get();

    if (existingQuery.docs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Item is already in your grocery list'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    await groceryRef.add({
      'name': itemName.trim(),
      'checked': false,
      'addedAt': FieldValue.serverTimestamp(),
      'autoAdded': false,
    });
    
    // Clean up after adding
    await _cleanupAllDuplicates();
  }

  Future<void> _updateItem(String itemId, String name) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .doc(itemId)
        .update({'name': name.trim()});
  }

  Future<void> _removeItem(String itemId) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .doc(itemId)
        .delete();
  }

  Future<void> _toggleChecked(String itemId, bool currentValue) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .doc(itemId)
        .update({'checked': !currentValue});
  }

  // Initialize grocery list from inventory - ONLY called once during startup
  Future<void> _initializeGroceryListFromInventory() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      _isInitializing = true;
      print('🔄 START INITIALIZATION...');
      
      // First clean up any existing duplicates
      await _cleanupAllDuplicates();
      
      final inventorySnapshot = await _getInventoryCollection().get();
      
      // Process each inventory item with debounce to prevent duplicates
      for (var doc in inventorySnapshot.docs) {
        final data = doc.data();
        final brand = data['brand']?.toString().trim() ?? '';
        final name = data['name']?.toString().trim() ?? '';
        final quantity = (data['quantity'] as num?)?.toInt() ?? 0;
        
        if (brand.isNotEmpty && name.isNotEmpty) {
          // Use normalized key matching _cleanupAllDuplicates
          final itemKey = '$brand $name'.toLowerCase();
          final now = DateTime.now();
          
          // Only process if not recently processed (strong debounce)
          if (!_lastProcessed.containsKey(itemKey) || 
              now.difference(_lastProcessed[itemKey]!).inSeconds > 5) {
            _lastProcessed[itemKey] = now;
            print('📝 INIT PROCESSING: $brand $name (Qty: $quantity)');
            await _autoManageGroceryItem(brand, name, quantity);
          }
        }
      }
      
      // Final cleanup after all processing
      await _cleanupAllDuplicates();
      print('✅ INITIALIZATION COMPLETE');
      
      _isInitializing = false;
    } catch (e) {
      print('❌ Error initializing grocery list: $e');
      _isInitializing = false;
    }
  }

  @override
  void initState() {
    super.initState();
    // ONLY run initialization once on first load
    if (!_initialized) {
      print('🔄 INITIALIZING GROCERY LIST...');
      _initialized = true;
      // Initialize from existing inventory, THEN listen for changes
      _initializeGroceryListFromInventory().then((_) {
        print('✅ SETUP COMPLETE - Starting listener now');
        _setupInventoryListener();
      }).catchError((e) {
        print('❌ Initialization error: $e');
        _isInitializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Grocery List',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Colors.black),
            onPressed: () {
              setState(() {
                _isAdding = !_isAdding;
              });
            },
          ),
          IconButton(
            icon: Icon(
              _isEditing ? Icons.check : Icons.edit_note,
              color: Colors.black,
            ),
            onPressed: () {
              setState(() {
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Add new item input
            if (_isAdding)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    const Checkbox(value: false, onChanged: null),
                    Expanded(
                      child: TextField(
                        controller: _newItemController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Add new item',
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                        ),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (value) async {
                          if (value.trim().isNotEmpty) {
                            await _addItemToGroceryList(value);
                            _newItemController.clear();
                            setState(() {
                              _isAdding = false;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),

            if (_isAdding) const SizedBox(height: 12),

            // Grocery list
            StreamBuilder<QuerySnapshot>(
              stream: _getGroceryList(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text('Error: ${snapshot.error}');
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final docs = snapshot.data!.docs;

                if (docs.isEmpty && !_isAdding) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Press + to add your first item!',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  );
                }

                // Separate auto and manual items
                final autoItems = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['autoAdded'] == true;
                }).toList();

                final manualItems = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  return data['autoAdded'] != true;
                }).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Auto-added section
                    if (autoItems.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "My Grocery List",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const Text(
                                  "auto",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: autoItems.length,
                              itemBuilder: (context, index) {
                                final doc = autoItems[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final displayName = data['brand'] != null && data['brand'].toString().isNotEmpty
                                    ? '${data['brand']} ${data['name']}'
                                    : data['name'] ?? '';
                                final controller = TextEditingController(text: displayName);

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Checkbox(
                                      value: data['checked'] ?? false,
                                      onChanged: (val) => _toggleChecked(
                                          doc.id, data['checked'] ?? false),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(vertical: 6),
                                        ),
                                        style: TextStyle(
                                          fontSize: 16,
                                          decoration: (data['checked'] ?? false)
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: (data['checked'] ?? false)
                                              ? Colors.grey
                                              : Colors.black,
                                        ),
                                        readOnly: !_isEditing,
                                        onSubmitted: (value) async {
                                          await _updateItem(doc.id, value);
                                        },
                                      ),
                                    ),
                                    if (_isEditing)
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _removeItem(doc.id),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Manual-added section
                    if (manualItems.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  "My Grocery List",
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const Text(
                                  "manual",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: manualItems.length,
                              itemBuilder: (context, index) {
                                final doc = manualItems[index];
                                final data = doc.data() as Map<String, dynamic>;
                                final displayName = data['brand'] != null && data['brand'].toString().isNotEmpty
                                    ? '${data['brand']} ${data['name']}'
                                    : data['name'] ?? '';
                                final controller = TextEditingController(text: displayName);

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Checkbox(
                                      value: data['checked'] ?? false,
                                      onChanged: (val) => _toggleChecked(
                                          doc.id, data['checked'] ?? false),
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: controller,
                                        decoration: const InputDecoration(
                                          border: InputBorder.none,
                                          isDense: true,
                                          contentPadding:
                                              EdgeInsets.symmetric(vertical: 6),
                                        ),
                                        style: TextStyle(
                                          fontSize: 16,
                                          decoration: (data['checked'] ?? false)
                                              ? TextDecoration.lineThrough
                                              : TextDecoration.none,
                                          color: (data['checked'] ?? false)
                                              ? Colors.grey
                                              : Colors.black,
                                        ),
                                        readOnly: !_isEditing,
                                        onSubmitted: (value) async {
                                          await _updateItem(doc.id, value);
                                        },
                                      ),
                                    ),
                                    if (_isEditing)
                                      IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () => _removeItem(doc.id),
                                      ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _newItemController.dispose();
    super.dispose();
  }
}