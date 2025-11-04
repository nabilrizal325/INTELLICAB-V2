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

  Future<List<Map<String, dynamic>>> _getExpiringItems() async {
    final user = _auth.currentUser;
    if (user == null) return [];

    final snapshot = await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('inventory')
        .get();

    final now = DateTime.now();
    final items = <Map<String, dynamic>>[];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final expiryDateStr = data['expiryDate'];
      
      if (expiryDateStr != null) {
        try {
          final expiryDate = DateFormat('dd/MM/yyyy').parse(expiryDateStr);
          final daysUntilExpiry = expiryDate.difference(now).inDays;

          // Show items expiring in 7 days or less
          if (daysUntilExpiry <= 7 && daysUntilExpiry >= 0) {
            items.add({
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

    // Sort by days until expiry (soonest first)
    items.sort((a, b) => a['daysUntilExpiry'].compareTo(b['daysUntilExpiry']));
    
    return items;
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
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _getExpiringItems(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final expiringItems = snapshot.data ?? [];

          if (expiringItems.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No expiring items',
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Items expiring within 7 days will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: expiringItems.length,
            itemBuilder: (context, index) {
              final item = expiringItems[index];
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
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
            },
          );
        },
      ),
    );
  }
}