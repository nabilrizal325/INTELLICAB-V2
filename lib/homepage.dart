import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellicab/add_item_page.dart';
import 'package:intellicab/cabinet_details_page.dart';
import 'package:intellicab/gorcery_list.dart';
import 'package:intellicab/notifications_page.dart';
import 'package:intellicab/devices_screen.dart';
import 'profile_page.dart';
import 'package:intl/intl.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  int _expiringItemsCount = 0;
  StreamSubscription<QuerySnapshot>? _inventorySub;

  @override
  void initState() {
    super.initState();
    _loadExpiringItemsCount();
    _setupInventoryListener();
  }

  void _setupInventoryListener() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final userDocRef = FirebaseFirestore.instance.collection('User').doc(user.uid);
    final invColl = userDocRef.collection('inventory');

    // Listen for inventory changes and auto-add low-stock items to grocery_list
    _inventorySub = invColl.snapshots().listen((snap) async {
      try {
        // read reminderLevel from user doc (default 1)
        final userDoc = await userDocRef.get();
        int reminderLevel = 1;
        if (userDoc.exists) {
          final data = userDoc.data();
          if (data != null && data['reminderLevel'] != null) {
            try {
              reminderLevel = (data['reminderLevel'] as num).toInt();
            } catch (_) {
              try {
                reminderLevel = int.parse(data['reminderLevel'].toString());
              } catch (_) {
                reminderLevel = 1;
              }
            }
          }
        }

        for (var doc in snap.docs) {
          final data = doc.data();
          final qtyField = data['quantity'];
          int qty = 0;
          if (qtyField is num) qty = qtyField.toInt();
          else if (qtyField is String) qty = int.tryParse(qtyField) ?? 0;

          if (qty <= reminderLevel) {
            final itemName = '${data['brand'] ?? ''} ${data['name'] ?? ''}'.trim();
            await _addLowItemToGroceryIfMissing(user.uid, doc.id, itemName);
          }
        }
        // Refresh the notification count after processing inventory changes
        // so the badge combines both low-stock and expiry notifications in real-time.
        await _loadExpiringItemsCount();
      } catch (e) {
        debugPrint('Inventory listener error: $e');
      }
    }, onError: (e) {
      debugPrint('Inventory snapshots error: $e');
    });
  }

  Future<void> _addLowItemToGroceryIfMissing(String userId, String inventoryDocId, String itemName) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final groceryRef = firestore.collection('User').doc(userId).collection('grocery_list');

      // Check if there's already an entry linked to this inventory item
      final q = await groceryRef.where('inventoryId', isEqualTo: inventoryDocId).limit(1).get();
      if (q.docs.isNotEmpty) return;

      // Optional: check by name to be extra safe
      if (itemName.isNotEmpty) {
        final nameQ = await groceryRef.where('name', isEqualTo: itemName).limit(1).get();
        if (nameQ.docs.isNotEmpty) return;
      }

      await groceryRef.add({
        'name': itemName.isNotEmpty ? itemName : 'Unknown item',
        'checked': false,
        'addedAt': FieldValue.serverTimestamp(),
        'inventoryId': inventoryDocId,
        'autoAdded': true,
      });
      debugPrint('Auto-added grocery item for inventory $inventoryDocId');
    } catch (e) {
      debugPrint('Error auto-adding grocery item: $e');
    }
  }

  Future<void> _loadExpiringItemsCount() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final userDocRef = FirebaseFirestore.instance.collection('User').doc(user.uid);

    // Load user-configured reminder level (threshold for low-stock). Default to 1.
    final userDoc = await userDocRef.get();
    int reminderLevel = 1;
    if (userDoc.exists) {
      final data = userDoc.data();
      if (data != null && data['reminderLevel'] != null) {
        try {
          reminderLevel = (data['reminderLevel'] as num).toInt();
        } catch (_) {
          try {
            reminderLevel = int.parse(data['reminderLevel'].toString());
          } catch (_) {
            reminderLevel = 1;
          }
        }
      }
    }

    final snapshot = await userDocRef.collection('inventory').get();
    final now = DateTime.now();

    // Use a set of doc ids so we don't double-count items that are both low-stock and expiring
    final Set<String> notifyIds = {};

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // Check low-stock
      final qtyField = data['quantity'];
      int qty = 0;
      if (qtyField is num) {
        qty = qtyField.toInt();
      } else if (qtyField is String) {
        qty = int.tryParse(qtyField) ?? 0;
      }

      if (qty <= reminderLevel) {
        notifyIds.add(doc.id);
      }

      // Check expiry (support expiryDates array or expiryDate)
      final expiryField = data['expiryDates'] ?? data['expiryDate'];
      String? expiryDateStr;
      if (expiryField is List && expiryField.isNotEmpty) {
        expiryDateStr = expiryField.first?.toString();
      } else if (expiryField != null) {
        expiryDateStr = expiryField.toString();
      }

      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        DateTime? expiryDate;
        try {
          // Try formats in order: dd-MM-yyyy, dd/MM/yyyy
          for (final format in ['dd-MM-yyyy', 'dd/MM/yyyy']) {
            try {
              expiryDate = DateFormat(format).parse(expiryDateStr);
              break;
            } catch (_) {
              continue;
            }
          }

          if (expiryDate != null) {
            // Normalize to start of day for accurate comparison
            final startOfExpiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
            final startOfToday = DateTime(now.year, now.month, now.day);
            final daysUntilExpiry = startOfExpiry.difference(startOfToday).inDays;
            
            if (daysUntilExpiry <= 7 && daysUntilExpiry >= 0) {
              notifyIds.add(doc.id);
              debugPrint('Adding to notify: ${data['name']} (expires in $daysUntilExpiry days)');
            }
          }
        } catch (e) {
          debugPrint('Error parsing date "$expiryDateStr": $e');
        }
      }
    }

    if (mounted) {
      setState(() {
        _expiringItemsCount = notifyIds.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    final userDoc =
        FirebaseFirestore.instance.collection("User").doc(currentUser.uid);

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),

      body: IndexedStack(
        index: _selectedIndex == 2 ? 1 : 0,
        children: [
          // Home Inventory Page
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: userDoc.snapshots(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                final username = userData["username"] ?? "User";
                final profilePic = userData["profilePicture"];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const ProfilePage(),
                                    ),
                                  );
                                },
                                child: CircleAvatar(
                                  backgroundColor: Colors.pink.shade100,
                                  radius: 24,
                                  backgroundImage: profilePic != null
                                      ? NetworkImage(profilePic)
                                      : null,
                                  child: profilePic == null
                                      ? Text(username[0].toUpperCase())
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Hi $username",
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              // Notifications Icon with Badge
                              Stack(
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.notifications_none),
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const NotificationsPage(),
                                        ),
                                      ).then((_) {
                                        // Refresh count when returning from notifications
                                        _loadExpiringItemsCount();
                                      });
                                    },
                                  ),
                                  if (_expiringItemsCount > 0)
                                    Positioned(
                                      right: 8,
                                      top: 8,
                                      child: Container(
                                        padding: const EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        constraints: const BoxConstraints(
                                          minWidth: 16,
                                          minHeight: 16,
                                        ),
                                        child: Text(
                                          _expiringItemsCount > 9 ? '9+' : _expiringItemsCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.settings),
                                onPressed: () {
                                  _showSettingsMenu(context);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text(
                        "My Inventory",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Show expiring items warning banner
                    /*if (_expiringItemsCount > 0)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const NotificationsPage(),
                              ),
                            ).then((_) {
                              _loadExpiringItemsCount();
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange[800]),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$_expiringItemsCount item${_expiringItemsCount > 1 ? 's' : ''} expiring soon!',
                                    style: TextStyle(
                                      color: Colors.orange[800],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, 
                                    color: Colors.orange[800], size: 16),
                              ],
                            ),
                          ),
                        ),
                      ),*/

                    if (_expiringItemsCount > 0) const SizedBox(height: 16),

                    // Replace the inventory section with device-based grouping

                    // Inventory per Device (Device = Cabinet)
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        // Listen to inventory changes
                        stream: userDoc.collection("inventory").snapshots(),
                        builder: (context, inventorySnapshot) {
                          if (!inventorySnapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          return StreamBuilder<QuerySnapshot>(
                            // Get user's devices (each device IS a cabinet)
                            stream: FirebaseFirestore.instance
                                .collection('devices')
                                .where('userId', isEqualTo: currentUser.uid)
                                .snapshots(),
                            builder: (context, devicesSnapshot) {
                              if (!devicesSnapshot.hasData) {
                                return const Center(child: CircularProgressIndicator());
                              }

                              final products = inventorySnapshot.data!.docs;
                              final devices = devicesSnapshot.data!.docs;

                              // Create map of deviceId -> device info
                              final Map<String, Map<String, dynamic>> deviceInfo = {};
                              
                              for (var deviceDoc in devices) {
                                final deviceData = deviceDoc.data() as Map<String, dynamic>;
                                deviceInfo[deviceDoc.id] = {
                                  'name': deviceData['name'] ?? deviceDoc.id,
                                  'status': deviceData['status'] ?? 'offline',
                                  'detection_enabled': deviceData['detection_enabled'] ?? false,
                                };
                              }

                              // Group products by deviceId
                              final Map<String, List<Map<String, dynamic>>> deviceGroups = {};

                              // Always show unorganized first
                              deviceGroups['unorganized'] = [];

                              for (var doc in products) {
                                final data = doc.data() as Map<String, dynamic>;
                                final deviceId = data["deviceId"]?.toString() ?? "unorganized";
                                final deviceName = data["deviceName"] ?? deviceId;

                                if (!deviceGroups.containsKey(deviceId)) {
                                  deviceGroups[deviceId] = [];
                                }
            
                                deviceGroups[deviceId]!.add({
                                  ...data,
                                  'id': doc.id,
                                  'deviceName': deviceName
                                });
                              }

                              // Add empty entries for connected devices with no items
                              for (var deviceId in deviceInfo.keys) {
                                if (!deviceGroups.containsKey(deviceId)) {
                                  deviceGroups[deviceId] = [];
                                }
                              }

                              // Build device/cabinet cards
                              final List<Widget> cabinetCards = [];

                              // Add unorganized first
                              if (deviceGroups.containsKey('unorganized')) {
                                final items = deviceGroups['unorganized']!;
                                cabinetCards.add(
                                  EnhancedInventorySection(
                                    title: 'Unorganized',
                                    deviceId: 'unorganized',
                                    items: items,
                                    hasDevice: false,
                                    deviceInfo: null,
                                  ),
                                );
                              }

                              // Add devices (each device IS a cabinet)
                              for (var entry in deviceGroups.entries) {
                                final deviceId = entry.key;
                                if (deviceId == 'unorganized') continue;

                                final items = entry.value;
                                final info = deviceInfo[deviceId];
            
                                // Only show if device exists (is connected)
                                if (info != null) {
                                  cabinetCards.add(
                                    EnhancedInventorySection(
                                      title: info['name'] as String,
                                      deviceId: deviceId,
                                      items: items,
                                      hasDevice: true,
                                      deviceInfo: info,
                                    ),
                                  );
                                }
                              }

                              if (cabinetCards.isEmpty) {
                                return const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.devices, size: 64, color: Colors.grey),
                                      SizedBox(height: 16),
                                      Text(
                                        "Connect a device to start tracking",
                                        style: TextStyle(
                                          fontSize: 16,
                                          color: Colors.black,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      SizedBox(height: 8),
                                      Text(
                                        "Go to Settings → My Devices",
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              return ListView(
                                padding: const EdgeInsets.all(16),
                                children: cabinetCards,
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Grocery List Page
          GroceryList(),
        ],
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const DevicesScreen(),
            ),
          );
        },
        backgroundColor: Colors.pinkAccent.shade100,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          if (index == 1) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const AddItemPage()),
            );
          } else {
            setState(() => _selectedIndex = index);
          }
        },
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        selectedItemColor: const Color.fromARGB(225, 224, 15, 255),
        unselectedItemColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner), label: "Scan"),
          BottomNavigationBarItem(
              icon: Icon(Icons.list_alt), label: "Grocery List"),
        ],
      ),
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.devices),
              title: const Text('My Devices'),
              subtitle: const Text('Manage Pi cameras'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DevicesScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Close'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _inventorySub?.cancel();
    super.dispose();
  }
}

// Your existing InventorySection class remains the same...
class InventorySection extends StatelessWidget {
  final String title;
  final String cabinetId;
  final List<String> labels;
  final List<Map<String, dynamic>> items;

  const InventorySection({
    super.key,
    required this.title,
    required this.cabinetId,
    required this.labels,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        elevation: 2,
        child: const Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              "Nothing in inventory yet.",
              style: TextStyle(
                color: Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CabinetDetailsPage(
              title: title,
              cabinetId: cabinetId,
              items: items,
            ),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '${items.length} items',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: List.generate(labels.length, (index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: Colors.pink.shade100,
                            child: items[index]['imageUrl'] != null
                                ? ClipOval(
                                    child: Image.network(
                                      items[index]['imageUrl'],
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : Text(
                                    labels[index][0].toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 20, fontWeight: FontWeight.bold),
                                  ),
                          ),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: 80,
                            child: Text(
                              labels[index],
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Enhanced inventory section showing items for a device (which IS a cabinet)
/// 
/// Each device represents a physical storage location. This widget displays:
/// - Device name (e.g., "Kitchen Cabinet")
/// - Connection status (online/offline)
/// - Detection status (active badge)
/// - Items stored at this device's location
/// - "Cabinet is empty" when device connected but no items
/// 
/// The widget is tappable to view detailed inventory for that device.
class EnhancedInventorySection extends StatelessWidget {
  /// Display name for the device/cabinet (e.g., "Kitchen Cabinet")
  final String title;
  
  /// Device ID (MAC address) - represents the storage location
  final String deviceId;
  
  /// List of inventory items at this device's location
  final List<Map<String, dynamic>> items;
  
  /// Whether this location has a connected device
  final bool hasDevice;
  
  /// Device connection and detection info
  final Map<String, dynamic>? deviceInfo;

  const EnhancedInventorySection({
    super.key,
    required this.title,
    required this.deviceId,
    required this.items,
    required this.hasDevice,
    this.deviceInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isOnline = deviceInfo?['status'] == 'online';
    final isDetecting = deviceInfo?['detection_enabled'] == true;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CabinetDetailsPage(
              title: title,
              cabinetId: deviceId,  // Using deviceId as location identifier
              items: items,
            ),
          ),
        );
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        color: Colors.white,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with device name and status
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasDevice) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              // Online/Offline indicator
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isOnline ? Colors.green : Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isOnline ? 'Device Online' : 'Device Offline',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              // Detection badge
                              if (isDetecting) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.radar,
                                        size: 10,
                                        color: Colors.green[700],
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'DETECTING',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green[700],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${items.length} items',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Show items or empty state
              if (items.isEmpty && hasDevice)
                // Empty device location
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Cabinet is empty',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isDetecting 
                              ? 'Camera will detect items added'
                              : 'Enable detection to auto-track items',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else if (items.isEmpty)
                // Unorganized with no items
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Scan items to add them here',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Show items horizontally
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(items.length, (index) {
                      final item = items[index];
                      final label = "${item["brand"] ?? ""} ${item["name"] ?? ""}";
                      
                      return Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Column(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundColor: Colors.pink.shade100,
                              child: item['imageUrl'] != null
                                  ? ClipOval(
                                      child: Image.network(
                                        item['imageUrl'],
                                        width: 60,
                                        height: 60,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) {
                                          return Text(
                                            label[0].toUpperCase(),
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          );
                                        },
                                      ),
                                    )
                                  : Text(
                                      label.isNotEmpty ? label[0].toUpperCase() : '?',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 6),
                            SizedBox(
                              width: 80,
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}