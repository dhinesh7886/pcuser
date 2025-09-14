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
    getFunction();
  }

  void getFunction() async{
    var userId = FirebaseAuth.instance.currentUser?.uid;
    await Future.delayed(Duration(seconds: 3)).then((value) {
      if(userId == null){
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => StylishLoginPage(),));
      } else {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (context) => UsersHomePage(),));
      }
    },);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: CircularProgressIndicator(),),
    );
  }
}