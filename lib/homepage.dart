import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intellicab/add_item_page.dart';
import 'package:intellicab/gorcery_list.dart';
import 'profile_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0; // controls nav state
  late final DocumentReference userDoc;

  @override
  void initState() {
    super.initState();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      userDoc = FirebaseFirestore.instance.collection("User").doc(currentUser.uid);
    }
  }

  Future<DocumentSnapshot> _getUserData() async {
    return await userDoc.get(); // Loads once instead of streaming
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      return const Scaffold(
        body: Center(child: Text("Not logged in")),
      );
    }

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      body: IndexedStack(
        index: _selectedIndex == 2 ? 1 : 0,
        children: [
          SafeArea(
            child: FutureBuilder<DocumentSnapshot>(
              future: _getUserData(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final username = userData["username"] ?? "User";
                final profilePic = userData["profilePicture"];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header - only loads once
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
                                  backgroundImage: profilePic != null ? NetworkImage(profilePic) : null,
                                  child: profilePic == null ? Text(username[0].toUpperCase()) : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text("Hi $username!", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Row(
                            children: [
                              IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
                              IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
                            ],
                          )
                        ],
                      ),
                    ),

                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.0),
                      child: Text("My Inventory", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 16),

                    // Inventory section - still uses real-time updates
                    Expanded(
                      child: StreamBuilder<QuerySnapshot>(
                        stream: userDoc.collection("inventory").snapshots(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          final products = snapshot.data!.docs;
                          if (products.isEmpty) {
                            return const Center(
                              child: Text("Nothing in inventory yet.",
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                            );
                          }

                          final Map<String, List<Map<String, dynamic>>> cabinetGroups = {};
                          for (var doc in products) {
                            final data = doc.data() as Map<String, dynamic>;
                            final cabinetId = data["cabinetId"] ?? "Uncategorized";
                            cabinetGroups.putIfAbsent(cabinetId, () => []).add(data);
                          }

                          return ListView(
                            padding: const EdgeInsets.all(16),
                            children: cabinetGroups.entries.map((entry) {
                              return InventorySection(
                                title: entry.key,
                                labels: entry.value.map((p) => "${p["brand"] ?? ""} ${p["name"] ?? ""}").toList(),
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
          const GorceryList(),
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
        backgroundColor: Colors.white,
        selectedItemColor: const Color.fromARGB(225, 224, 15, 255),
        unselectedItemColor: Colors.black,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.qr_code_scanner), label: "Scan"),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: "Grocery List"),
        ],
      ),
    );
  }
}

class InventorySection extends StatelessWidget {
  final String title;
  final List<String> labels;

  const InventorySection({super.key, required this.title, required this.labels});

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
            child: Text("Nothing in inventory yet.",
                style: TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w500)),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(labels.length, (index) {
                return Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.pink.shade100,
                      child: Text(labels[index][0].toUpperCase(),
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
