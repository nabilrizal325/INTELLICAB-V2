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
    // Use start of today for more accurate day comparisons
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);

    final expiring = <Map<String, dynamic>>[];
    final lowStock = <Map<String, dynamic>>[];

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final itemName = '${data['brand'] ?? ''} ${data['name'] ?? ''}'.trim();
      debugPrint('\n--- Item: $itemName ---');
      debugPrint('Complete item data: $data');

      // Quantity handling
      final qtyField = data['quantity'];
      int qty = 0;
      if (qtyField is num) {
        qty = qtyField.toInt();
      } else if (qtyField is String) {
        qty = int.tryParse(qtyField) ?? 0;
      }
      debugPrint('Quantity: $qty');

      if (qty <= reminderLevel) {
        lowStock.add({...data, 'id': doc.id, 'quantity': qty});
        debugPrint('Added to low stock list: $itemName (qty: $qty)');
      }

      // Expiry handling - check all possible expiry date fields
      String? expiryDateStr;
      
      // Priority 1: Check expiryDates array FIRST (this is the actual expiry date)
      var expiryField = data['expiryDates'];
      if (expiryField is List && expiryField.isNotEmpty) {
        final firstItem = expiryField.first;
        debugPrint('✅ Found expiryDates array, first item type: ${firstItem.runtimeType}, value: $firstItem');
        
        // Handle both Timestamp and String in array
        if (firstItem is Timestamp) {
          expiryDateStr = DateFormat('dd/MM/yyyy').format(firstItem.toDate());
          debugPrint('✅ Converted Timestamp to date string: $expiryDateStr');
        } else if (firstItem != null) {
          expiryDateStr = firstItem.toString().trim();
          debugPrint('✅ Using expiryDates string value: $expiryDateStr');
        }
      } else {
        debugPrint('⏭️ expiryDates array empty or not found');
      }
      
      // Priority 2: Check expiryDate field (if expiryDateStr not set)
      if ((expiryDateStr == null || expiryDateStr.isEmpty)) {
        expiryField = data['expiryDate'];
        if (expiryField != null) {
          debugPrint('Checking expiryDate: $expiryField (type: ${expiryField.runtimeType})');
          if (expiryField is Timestamp) {
            expiryDateStr = DateFormat('dd/MM/yyyy').format(expiryField.toDate());
            debugPrint('✅ Converted expiryDate Timestamp to: $expiryDateStr');
          } else {
            expiryDateStr = expiryField.toString().trim();
          }
        }
      }
      
      // Priority 3: Check timeStamp field (legacy, only if others empty)
      if ((expiryDateStr == null || expiryDateStr.isEmpty)) {
        expiryField = data['timeStamp'];
        if (expiryField != null) {
          debugPrint('Checking timeStamp (legacy): $expiryField (type: ${expiryField.runtimeType})');
          if (expiryField is Timestamp) {
            expiryDateStr = DateFormat('dd/MM/yyyy').format(expiryField.toDate());
            debugPrint('✅ Converted timeStamp Timestamp to: $expiryDateStr');
          } else {
            expiryDateStr = expiryField.toString().trim();
          }
        }
      }
      
      debugPrint('Final expiryDateStr for "$itemName": $expiryDateStr');

      if (expiryDateStr != null && expiryDateStr.isNotEmpty) {
        DateTime? expiryDate;
        try {
          // Try multiple date formats in order of likelihood
          final formats = [
            'dd-MM-yyyy',     // 25-12-2024
            'dd/MM/yyyy',     // 25/12/2024
            'yyyy-MM-dd',     // 2024-12-25
            'yyyy/MM/dd',     // 2024/12/25
            'dd.MM.yyyy',     // 25.12.2024
            'MMM dd, yyyy',   // Dec 25, 2024
          ];
          
          for (final format in formats) {
            try {
              expiryDate = DateFormat(format).parse(expiryDateStr);
              debugPrint('✅ Successfully parsed expiry date "$expiryDateStr" with format "$format"');
              break;
            } catch (e) {
              debugPrint('❌ Failed format "$format": $e');
              continue;
            }
          }

          if (expiryDate != null) {
            // Normalize expiry date to start of day for accurate day comparison
            final startOfExpiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
            final daysUntilExpiry = startOfExpiry.difference(startOfToday).inDays;
            debugPrint('Item: $itemName, Expiry: $expiryDateStr, Parsed Date: $startOfExpiry, Days until: $daysUntilExpiry');

            // Show only items expiring in 3 days or less
            if (daysUntilExpiry <= 3 && daysUntilExpiry >= 0) {
              debugPrint('✅ Added to expiring list: $itemName (expires in $daysUntilExpiry days)');
              expiring.add({
                ...data,
                'id': doc.id,
                'daysUntilExpiry': daysUntilExpiry,
                'expiryDateObj': expiryDate,
              });
            } else {
              debugPrint('⏭️ Not expiring soon: $daysUntilExpiry days until expiry (threshold is 0-3 days)');
            }
          } else {
            debugPrint('❌ Could not parse expiry date: "$expiryDateStr" - no matching format found');
          }
        } catch (e) {
          debugPrint('❌ Error parsing date "$expiryDateStr": $e');
        }
      } else {
        debugPrint('⏭️ No valid expiry date found for item');
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
                    subtitle: Text('Notify when quantity is below than $reminderLevel'),

                    trailing: IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () async {
                        final controller = TextEditingController(text: reminderLevel.toString());
                        final result = await showDialog<int>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Row(
                              children: [
                                
                                Text('Set Reminder Level'),
                              ],
                            ),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 🆕 Explanation text
                                const Text(
                                  'Notify me when my item quantity is below:',
                                  style: TextStyle(fontSize: 14, color: Colors.grey),
                                ),
                                const SizedBox(height: 16),
                                
                                // 🆕 Improved TextField with validation
                                TextField(
                                  controller: controller,
                                  keyboardType: TextInputType.number,
                                  autofocus: true,
                                  decoration: InputDecoration(
                                    labelText: 'Reminder Threshold',
                                    hintText: 'e.g., 5',
                                    prefixIcon: const Icon(Icons.inventory_2_outlined),
                                    suffixText: 'items',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey.shade50,
                                    helperText: 'Recommended: 1-10',
                                    helperStyle: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                
                                // 🆕 Quick selection chips
                                const SizedBox(height: 16),
                                const Text(
                                  'Quick select:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [1, 3, 5, 10].map((value) {
                                    return ChoiceChip(
                                      label: Text(value.toString()),
                                      selected: controller.text == value.toString(),
                                      onSelected: (selected) {
                                        if (selected) {
                                          controller.text = value.toString();
                                          // Trigger rebuild to update selected chip
                                          (context as Element).markNeedsBuild();
                                        }
                                      },
                                      selectedColor: Colors.purple.shade200,
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Cancel'),
                              ),
                              FilledButton.icon(
                                onPressed: () {
                                  final input = controller.text.trim();
                                  
                                  // 🆕 Validate input
                                  if (input.isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please enter a value')),
                                    );
                                    return;
                                  }
                                  
                                  final value = int.tryParse(input);
                                  
                                  if (value == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please enter a valid number')),
                                    );
                                    return;
                                  }
                                  
                                  if (value < 1) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Value must be at least 1')),
                                    );
                                    return;
                                  }
                                  
                                  if (value > 100) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Value cannot exceed 100')),
                                    );
                                    return;
                                  }
                                  
                                  Navigator.pop(context, value);
                                },
                                icon: const Icon(Icons.check),
                                label: const Text('Save'),
                              ),
                            ],
                          ),
                        );

                        if (result != null) {
                          await _saveReminderLevel(result);
                          setState(() {});
                          
                          // 🆕 Show success feedback
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Reminder level updated to $result'),
                                backgroundColor: Colors.green,
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          }
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