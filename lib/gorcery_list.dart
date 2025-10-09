import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// GroceryList is a StatefulWidget because we need to manage state (edit mode, input dialog, etc.)
class GroceryList extends StatefulWidget {
  const GroceryList({super.key});

  @override
  State<GroceryList> createState() => _GroceryListState();
}

class _GroceryListState extends State<GroceryList> {
  // Firestore and FirebaseAuth instances for database & authentication
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  // Controller to manage input field in Add Item dialog
  final _newItemController = TextEditingController();

  // Boolean to toggle edit mode (show delete buttons)
  bool _isEditing = false;

  // Fetches grocery list as a real-time stream from Firestore
  Stream<QuerySnapshot> _getGroceryList() {
    final user = _auth.currentUser; // Get logged-in user
    if (user == null) return const Stream.empty(); // Return empty if no user

    return _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .snapshots(); // Listen for changes in grocery list
  }

  // Fetches low quantity items from inventory (quantity <= 1)
  Stream<QuerySnapshot> _getLowQuantityItems() {
    final user = _auth.currentUser;
    if (user == null) return const Stream.empty();

    return _firestore
        .collection('User')
        .doc(user.uid)
        .collection('inventory')
        .where('quantity', isLessThanOrEqualTo: 1)
        .snapshots();
  }

  // Adds a new item to grocery_list subcollection
  Future<void> _addItemToGroceryList(String itemName) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .add({
      'name': itemName,
      'checked': false, // Initially unchecked
      'addedAt': FieldValue.serverTimestamp(), // Timestamp for ordering
    });
  }

  // Removes item from grocery_list using its document ID
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

  // Toggles the checked status of an item (true <-> false)
  Future<void> _toggleChecked(String itemId, bool currentValue) async {
    final user = _auth.currentUser;
    if (user == null) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .doc(itemId)
        .update({
      'checked': !currentValue,
    });
  }

  // Show dialog to add new grocery item
  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Item'),
        content: TextField(
          controller: _newItemController,
          decoration: const InputDecoration(
            hintText: 'Enter item name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              _newItemController.clear();
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (_newItemController.text.isNotEmpty) {
                _addItemToGroceryList(_newItemController.text.trim());
                Navigator.pop(context); // Close dialog
                _newItemController.clear();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
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
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Section showing low-quantity inventory items
              StreamBuilder<QuerySnapshot>(
                stream: _getLowQuantityItems(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text('Error: ${snapshot.error}');
                  }

                  // If there are low-quantity items, show them
                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.yellow[100], // Highlighted background
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Low Quantity Items",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Display each low-quantity item
                          ...snapshot.data!.docs.map((doc) {
                            final data = doc.data() as Map<String, dynamic>;
                            return ListTile(
                              title: Text(data['name'] ?? ''),
                              subtitle: Text('Quantity: ${data['quantity']}'),
                              trailing: TextButton(
                                child: const Text('Add to List'),
                                onPressed: () => _addItemToGroceryList(data['name']),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink(); // If no low quantity items, show nothing
                },
              ),

              // Main grocery list container
              Container(
                constraints: const BoxConstraints(minHeight: 100),
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 250, 249, 246),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row with title and add/edit buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Grocery List",
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _showAddItemDialog,
                            ),
                            IconButton(
                              icon: Icon(_isEditing ? Icons.check : Icons.edit),
                              onPressed: () {
                                setState(() {
                                  _isEditing = !_isEditing; // Toggle edit mode
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Grocery list items (real-time updates)
                    StreamBuilder<QuerySnapshot>(
                      stream: _getGroceryList(),
                      builder: (context, snapshot) {
                        if (snapshot.hasError) {
                          return Text('Error: ${snapshot.error}');
                        }

                        if (!snapshot.hasData) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }

                        final docs = snapshot.data!.docs;

                        if (docs.isEmpty) {
                          // Show message if grocery list is empty
                          return const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text('No items in grocery list'),
                            ),
                          );
                        }

                        // Build list of items
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: docs.length,
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;

                            return CheckboxListTile(
                              title: Text(data['name'] ?? ''),
                              value: data['checked'] ?? false,
                              onChanged: (bool? value) =>
                                  _toggleChecked(doc.id, data['checked'] ?? false),
                              controlAffinity: ListTileControlAffinity.leading,
                              secondary: _isEditing
                                  ? IconButton(
                                      icon: const Icon(Icons.delete),
                                      onPressed: () => _removeItem(doc.id),
                                    )
                                  : null,
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _newItemController.dispose(); // Dispose controller to avoid memory leaks
    super.dispose();
  }
}