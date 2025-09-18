import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthService {
  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore db = FirebaseFirestore.instance;

  Future<String?> signUp({
    required String email,
    required String password,
    required String name,
    required String username,
  }) async {
    try {

      //Check if username already exists
      final existingUser = await db
          .collection('User')
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();

      if (existingUser.docs.isNotEmpty) {
        return "Username is already taken. Please choose another.";
      }

      //Create user in Firebase Authentication
      UserCredential userCredential = await  auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );

      // Save additional info in Firestore
      await db.collection('User').doc(userCredential.user!.uid).set({
        'name': name.trim(),
        'username': username.trim(),
        'email': email.trim(),
        'created_at': DateTime.now(),
      });

    

      return null; // No error
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An unknown error occurred.";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<String?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password.trim(),
      );
      return null; // No error
    } on FirebaseAuthException catch (e) {
      return e.message ?? "An unknown error occurred.";
    } catch (e) {
      return "Error: $e";
    }
  }

  Future<String?> resetPassword({required String email}) async {
  try {
    await auth.sendPasswordResetEmail(email: email.trim());
    return null; // Success, no error message
  } on FirebaseAuthException catch (e) {
    return e.message ?? "An unknown error occurred.";
  } catch (e) {
    return "Error: $e";
  }
}

}

  
