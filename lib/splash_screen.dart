import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pcuser/home.dart';
import 'package:pcuser/login_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {

  @override
  void initState() {
    super.initState();
    _checkLogin();
  }

  void _checkLogin() async {
    // Ensure Firebase is initialized before using FirebaseAuth
    await Future.delayed(const Duration(seconds: 3));

    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => StylishLoginPage()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const UsersHomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
