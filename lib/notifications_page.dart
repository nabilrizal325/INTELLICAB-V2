import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // Return a map with lists: { 'reminderLevel': int, 'expiring': List<...>, 'lowStock': List<...> }
  Future<Map<String, dynamic>> _getAllNotifications() async {
    final user = _auth.currentUser;
    if (user == null) return {'reminderLevel': 1, 'expiring': [], 'lowStock': []};

    final userDocRef = _firestore.collection('User').doc(user.uid);
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

    final expiring = <Map<String, dynamic>>[];
    final lowStock = <Map<String, dynamic>>[];

    for (var doc in snapshot.docs) {
      final data = doc.data();

      // Quantity handling
      final qtyField = data['quantity'];
      int qty = 0;
      if (qtyField is num) {
        qty = qtyField.toInt();
      } else if (qtyField is String) {
        qty = int.tryParse(qtyField) ?? 0;
      }

      if (qty <= reminderLevel) {
        lowStock.add({...data, 'id': doc.id, 'quantity': qty});
      }

      // Expiry handling
      final expiryDateStr = data['expiryDate'];
      if (expiryDateStr != null) {
        try {
          final expiryDate = DateFormat('dd/MM/yyyy').parse(expiryDateStr);
          final daysUntilExpiry = expiryDate.difference(now).inDays;
          if (daysUntilExpiry <= 7 && daysUntilExpiry >= 0) {
            expiring.add({
              ...data,
              'id': doc.id,
              'daysUntilExpiry': daysUntilExpiry,
              'expiryDateObj': expiryDate,
            });
          }
        } catch (e) {
          debugPrint('Error parsing date: $e');
        }
      }
    }

    // Sort lists
    expiring.sort((a, b) => a['daysUntilExpiry'].compareTo(b['daysUntilExpiry']));
    lowStock.sort((a, b) => (a['quantity'] as int).compareTo(b['quantity'] as int));

    return {'reminderLevel': reminderLevel, 'expiring': expiring, 'lowStock': lowStock};
  }

  Future<void> _saveReminderLevel(int newLevel) async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _firestore.collection('User').doc(user.uid).set({'reminderLevel': newLevel}, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color.fromARGB(255, 248, 207, 255),
        elevation: 0,
      ),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _getAllNotifications(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final data = snapshot.data ?? {'reminderLevel': 1, 'expiring': [], 'lowStock': []};
          final int reminderLevel = data['reminderLevel'] as int? ?? 1;
          final List expiringItems = data['expiring'] as List? ?? [];
          final List lowStockItems = data['lowStock'] as List? ?? [];

          return RefreshIndicator(
            onRefresh: () async => setState(() {}),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Reminder level card
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text('Reminder level'),
                    subtitle: Text('Notify when quantity <= $reminderLevel'),
                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final controller = TextEditingController(text: reminderLevel.toString());
                        final result = await showDialog<int>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Set reminder level'),
                            content: TextField(
                              controller: controller,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Quantity threshold'),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                              TextButton(
                                onPressed: () {
                                  final value = int.tryParse(controller.text) ?? reminderLevel;
                                  Navigator.pop(context, value);
                                },
                                child: const Text('Save'),
                              ),
                            ],
                          ),
                        );

                        if (result != null) {
                          await _saveReminderLevel(result);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Low-stock section
                if (lowStockItems.isNotEmpty) ...[
                  const Text('Low stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...lowStockItems.map((item) {
                    final itemName = '${item['brand'] ?? ''} ${item['name'] ?? ''}'.trim();
                    final qty = item['quantity'] ?? 0;
                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.pink.shade100,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: item['imageUrl'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: Image.network(item['imageUrl'], fit: BoxFit.cover),
                                )
                              : const Icon(Icons.inventory, color: Colors.black),
                        ),
                        title: Text(itemName, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('Qty: $qty'),
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                ],

                // Expiring section
                if (expiringItems.isNotEmpty) ...[
                  const Text('Expiring soon', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...expiringItems.map((item) {
                    final daysUntilExpiry = item['daysUntilExpiry'] as int;
                    final itemName = '${item['brand'] ?? ''} ${item['name'] ?? ''}'.trim();
                    final expiryDate = item['expiryDateObj'] as DateTime;

                    Color notificationColor;
                    IconData notificationIcon;
                    String statusText;

                    if (daysUntilExpiry == 0) {
                      notificationColor = Colors.red;
                      notificationIcon = Icons.warning;
                      statusText = 'Expires today!';
                    } else if (daysUntilExpiry <= 3) {
                      notificationColor = Colors.orange;
                      notificationIcon = Icons.warning_amber;
                      statusText = 'Expires in $daysUntilExpiry days';
                    } else {
                      notificationColor = Colors.blue;
                      notificationIcon = Icons.info;
                      statusText = 'Expires in $daysUntilExpiry days';
                    }

                    return Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                      child: ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: Colors.pink.shade100,
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: item['imageUrl'] != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(25),
                                  child: Image.network(
                                    item['imageUrl'],
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  notificationIcon,
                                  color: notificationColor,
                                ),
                        ),
                        title: Text(
                          itemName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Expiry: ${DateFormat('dd/MM/yyyy').format(expiryDate)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: notificationColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: notificationColor),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: notificationColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        trailing: Text(
                          'Qty: ${item['quantity']}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  }),
                ],

                if (expiringItems.isEmpty && lowStockItems.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48.0),
                      child: Column(
                        children: [
                          Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No notifications', style: TextStyle(fontSize: 18, color: Colors.grey)),
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
}