import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart'; // Make sure this path matches your project

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        title: const Text('Profile',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: false,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Profile picture and name
            const CircleAvatar(
              radius: 50,
              backgroundImage: AssetImage('assets/profile.jpg'), 
              // Replace with NetworkImage if loading from URL
            ),
            const SizedBox(height: 10),
            const Text(
              'Arissa',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),

            // User info card
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text("Full Name:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("Arissa Hani Binti Abdul Hadi"),
                  SizedBox(height: 10),
                  Text("Email:", style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("arissahani@gmail.com"),
                  SizedBox(height: 10),
                  Text("Password:",
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  Text("********"),
                ],
              ),
            ),
            const SizedBox(height: 30),

            // Buttons
            _buildButton(context, Icons.person_outline, "Personalize", () {}),
            const SizedBox(height: 10),
            _buildButton(context, Icons.settings_outlined, "Settings", () {}),
            const SizedBox(height: 10),
            _buildButton(context, Icons.logout, "Logout", () async {
              await FirebaseAuth.instance.signOut();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                (route) => false, // Clear all previous routes
              );
            }, color: Colors.red),
          ],
        ),
      ),
    );
  }

  static Widget _buildButton(BuildContext context, IconData icon, String text, VoidCallback onTap, {Color color = Colors.black}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 15),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w500, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
