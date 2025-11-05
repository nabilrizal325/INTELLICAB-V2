import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CabinetDetailsPage extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;

  const CabinetDetailsPage({
    super.key,
    required this.title,
    required this.items,
  });

  // ✅ Helper to format date fields safely
  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'Unknown';
    if (dateValue is Timestamp) {
      return dateValue.toDate().toString().split(' ')[0];
    } else if (dateValue is String) {
      return dateValue.split(' ')[0];
    } else {
      return 'Unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 250, 249, 246), // Off-white background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];

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
                // ✅ Image
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

                // ✅ Info
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

                      // ✅ Added date
                      if (item['created_at'] != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Added: ${_formatDate(item['created_at'])}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.black87,
                            ),
                          ),
                        ),

                      // ✅ Expiry date
                      if (item['expiryDate'] != null && item['expiryDate'] != "")
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Expiry: ${item['expiryDate']}',
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

                // ✅ Edit button placeholder
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.black),
                  onPressed: () {
                    // TODO: Implement edit functionality
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
