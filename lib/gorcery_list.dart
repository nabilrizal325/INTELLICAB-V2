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

  bool _isEditing = false;
  bool _isAdding = false;

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

  Future<void> _addItemToGroceryList(String itemName) async {
    final user = _auth.currentUser;
    if (user == null || itemName.trim().isEmpty) return;

    await _firestore
        .collection('User')
        .doc(user.uid)
        .collection('grocery_list')
        .add({
      'name': itemName.trim(),
      'checked': false,
      'addedAt': FieldValue.serverTimestamp(),
    });
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
        child: Container(
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
              const Text(
                "My Grocery List",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 10),

              // 🆕 Add new item input
              if (_isAdding)
                Row(
                  children: [
                    const Checkbox(value: false, onChanged: null),
                    Expanded(
                      child: TextField(
                        controller: _newItemController,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: '',
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

              // 📝 List (auto height)
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
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        'Press + to add your first item!',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.builder(
                    shrinkWrap: true, // ✅ allows list to wrap its content
                    physics: const NeverScrollableScrollPhysics(), // ✅ no scroll
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final controller =
                          TextEditingController(text: data['name'] ?? '');

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
                              icon:
                                  const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _removeItem(doc.id),
                            ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          ),
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
