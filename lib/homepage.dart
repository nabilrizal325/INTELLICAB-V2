import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellicab/add_item_page.dart';
import 'package:intellicab/cabinet_details_page.dart';
import 'package:intellicab/gorcery_list.dart';
import 'package:intellicab/notifications_page.dart'; // Add this import
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
                                onPressed: () {},
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

                    // Inventory per Cabinet
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: userDoc.collection("inventory").snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }

                          final products = snapshot.data!.docs;

                          if (products.isEmpty) {
                            return const Center(
                              child: Text(
                                "Nothing in inventory yet.",
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.black,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }

                          // Group products by cabinetId (so we can use cabinet doc id for detection listening)
                          final Map<String, List<Map<String, dynamic>>> cabinetGroups = {};

                          for (var doc in products) {
                            final data = doc.data() as Map<String, dynamic>;
                            final cabinetId = data["cabinetId"]?.toString() ?? "unorganized";
                            final cabinetName = data["cabinetName"] ?? cabinetId;

                            if (!cabinetGroups.containsKey(cabinetId)) {
                              cabinetGroups[cabinetId] = [];
                            }
                            // include doc id so details page can match detections reliably
                            cabinetGroups[cabinetId]!.add({...data, 'id': doc.id, 'cabinetName': cabinetName});
                          }

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: cabinetGroups.entries.map((entry) {
                              final cabinetId = entry.key;
                              final items = entry.value;
                              final cabinetName = items.isNotEmpty ? (items[0]['cabinetName'] ?? cabinetId) : cabinetId;
                              return InventorySection(
                                title: cabinetName,
                                cabinetId: cabinetId,
                                labels: items.map((p) => "${p["brand"] ?? ""} ${p["name"] ?? ""}").toList(),
                                items: items,
                              );
                            }).toList(),
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