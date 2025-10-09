import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isEditing = false;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final userData = await FirebaseFirestore.instance
          .collection('User')
          .doc(user.uid)
          .get();

      if (userData.exists) {
        setState(() {
          _nameController.text = userData.get('name') ?? '';
          _usernameController.text = userData.get('username') ?? '';
          _emailController.text = userData.get('email') ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading profile: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      setState(() => _isLoading = true);

      // Check if username is already taken (if username is changed)
      final existingUser = await FirebaseFirestore.instance
          .collection('User')
          .where('username', isEqualTo: _usernameController.text.trim())
          .where(FieldPath.documentId, isNotEqualTo: user.uid)
          .limit(1)
          .get();

      if (existingUser.docs.isNotEmpty) {
        setState(() {
          _error = 'Username is already taken';
          _isLoading = false;
        });
        return;
      }

      await FirebaseFirestore.instance
          .collection('User')
          .doc(user.uid)
          .update({
        'name': _nameController.text.trim(),
        'username': _usernameController.text.trim(),
      });

      setState(() {
        _isLoading = false;
        _error = null;
      });

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
    } catch (e) {
      setState(() {
        _error = 'Error updating profile: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

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
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: () {
              setState(() {
                if (_isEditing) {
                  // Save changes
                  if (_formKey.currentState?.validate() ?? false) {
                    _saveProfile();
                  }
                }
                _isEditing = !_isEditing;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        // Profile picture and name
                        const CircleAvatar(
                          radius: 50,
                          backgroundImage: AssetImage('assets/profile.jpg'),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _usernameController.text,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.bold),
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
                            children: [
                              const Text("Full Name:",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              if (_isEditing)
                                TextFormField(
                                  controller: _nameController,
                                  decoration: const InputDecoration(
                                    hintText: "Enter your full name",
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "Name is required";
                                    }
                                    return null;
                                  },
                                )
                              else
                                Text(_nameController.text),
                              const SizedBox(height: 10),
                              const Text("Username:",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              if (_isEditing)
                                TextFormField(
                                  controller: _usernameController,
                                  decoration: const InputDecoration(
                                    hintText: "Enter your username",
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return "Username is required";
                                    }
                                    if (value.contains(' ')) {
                                      return "Username cannot contain spaces";
                                    }
                                    return null;
                                  },
                                )
                              else
                                Text(_usernameController.text),
                              const SizedBox(height: 10),
                              const Text("Email:",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              if (_isEditing)
                                TextFormField(
                                  controller: _emailController,
                                  enabled: false, // Email cannot be changed
                                  decoration: const InputDecoration(
                                    hintText: "Enter your email",
                                  ),
                                )
                              else
                                Text(_emailController.text),
                              const SizedBox(height: 10),
                              const Text("Password:",
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                              const Text("********"),
                            ],
                          ),
                        ),
                        const SizedBox(height: 30),

                        // Buttons
                        _buildButton(
              context,
              Icons.person_outline,
              "Personalize",
              () {
                setState(() {
                  _isEditing = true;
                });
              },
            ),
            const SizedBox(height: 10),
            _buildButton(
              context,
              Icons.settings_outlined,
              "Change Password",
              () async {
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(
                    email: _emailController.text,
                  );
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Password reset email sent. Check your inbox.'),
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
            ),
            const SizedBox(height: 10),
            _buildButton(
              context,
              Icons.logout,
              "Logout",
              () async {
                await FirebaseAuth.instance.signOut();
                if (!mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginPage()),
                  (route) => false,
                );
              },
              color: Colors.red,
            ),
                      ],
                    ),
                  ),
                ),
    );
  }

  static Widget _buildButton(
    BuildContext context,
    IconData icon,
    String text,
    VoidCallback onTap, {
    Color color = Colors.black,
  }) {
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
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
