import 'package:flutter/material.dart';
import 'package:pcuser/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:pcuser/home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class StylishLoginPage extends StatefulWidget {
  const StylishLoginPage({super.key});

  @override
  State<StylishLoginPage> createState() => _StylishLoginPageState();
}

class _StylishLoginPageState extends State<StylishLoginPage> {
  final TextEditingController empIdController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  String? firestoreName;
  String? firestoreDob;
  String? passwordHint;
  bool passwordVisible = false; // ✅ toggle password visibility

  @override
  void dispose() {
    empIdController.dispose();
    otpController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _fetchUserDetails(String empId) async {
    if (empId.isEmpty) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: empId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        setState(() {
          firestoreName = data['name'];
          firestoreDob = data['dob']; // e.g., '7-8-1986'
          passwordHint = _generatePasswordHint(firestoreName!, firestoreDob!);
        });
      } else {
        setState(() {
          firestoreName = null;
          firestoreDob = null;
          passwordHint = null;
        });
      }
    } catch (e) {
      debugPrint("Error fetching user details: $e");
      setState(() {
        firestoreName = null;
        firestoreDob = null;
        passwordHint = null;
      });
    }
  }

  String generatePassword(String name, String dob) {
    final first4 = name.length >= 4 ? name.substring(0, 4).toUpperCase() : name.toUpperCase();
    try {
      List<String> parts = dob.split('-');
      String day = parts[0].padLeft(2, '0');   // '7' -> '07'
      String month = parts[1].padLeft(2, '0'); // '8' -> '08'
      return '$first4$day$month';
    } catch (e) {
      debugPrint("Error parsing DOB: $e");
      return '$first4${dob.replaceAll("-", "")}';
    }
  }

  String _generatePasswordHint(String name, String dob) {
    String pwd = generatePassword(name, dob);
    return "Hint: First 4 letters of your name + DOB in DDMM format (e.g., $pwd)";
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.teal[50],
      body: LayoutBuilder(
        builder: (context, constraints) {
          double maxWidth = constraints.maxWidth;
          double cardWidth = maxWidth > 600 ? 500 : maxWidth * 0.9;

          return Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 10,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  width: cardWidth,
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.person, size: 50, color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        "Welcome to PC Users",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 30),

                      // Employee ID
                      TextField(
                        controller: empIdController,
                        decoration: InputDecoration(
                          labelText: "Employee ID",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.badge),
                        ),
                        onChanged: (val) {
                          _fetchUserDetails(val.trim());
                        },
                      ),
                      const SizedBox(height: 20),

                      // OTP field
                      if (userProvider.otpSent) ...[
                        TextField(
                          controller: otpController,
                          decoration: InputDecoration(
                            labelText: "Enter OTP",
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            prefixIcon: const Icon(Icons.lock),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Password field with toggle
                      TextField(
                        controller: passwordController,
                        obscureText: !passwordVisible,
                        decoration: InputDecoration(
                          labelText: "Enter Password (Optional)",
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          prefixIcon: const Icon(Icons.key),
                          suffixIcon: IconButton(
                            icon: Icon(
                              passwordVisible ? Icons.visibility : Icons.visibility_off,
                            ),
                            onPressed: () {
                              setState(() {
                                passwordVisible = !passwordVisible;
                              });
                            },
                          ),
                        ),
                      ),

                      if (passwordHint != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          passwordHint!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),

                      // Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          if (!userProvider.otpSent)
                            ElevatedButton(
                              onPressed: userProvider.isSendingOtp
                                  ? null
                                  : () async {
                                      await userProvider.getOtp(
                                        empIdController.text.trim(),
                                        context,
                                        autoFillController: otpController,
                                      );
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: userProvider.isSendingOtp
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "GET OTP",
                                      style: TextStyle(color: Colors.white),
                                    ),
                            ),

                          ElevatedButton(
                            onPressed: () async {
                              String enteredPassword = passwordController.text.trim();
                              bool success = false;

                              // Check password
                              if (firestoreName != null &&
                                  firestoreDob != null &&
                                  enteredPassword.isNotEmpty) {
                                String generatedPwd =
                                    generatePassword(firestoreName!, firestoreDob!);
                                if (enteredPassword == generatedPwd) {
                                  success = true;
                                }
                              }

                              // Check OTP
                              if (userProvider.otpSent &&
                                  otpController.text.trim().isNotEmpty) {
                                success = await userProvider.submit(
                                  otpController.text.trim(),
                                  empIdController.text.trim(),
                                  context,
                                );
                              }

                              if (success) {
                                var sharedInstance = await SharedPreferences.getInstance();
                                sharedInstance.setString("id", empIdController.text.trim());
                                if (mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => const UsersHomePage(),
                                    ),
                                  );
                                }
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Invalid OTP or Password"),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "SUBMIT",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),

                          ElevatedButton(
                            onPressed: () {
                              empIdController.clear();
                              otpController.clear();
                              passwordController.clear();
                              userProvider.clearState();
                              setState(() {
                                passwordHint = null;
                                firestoreName = null;
                                firestoreDob = null;
                                passwordVisible = false;
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              "CANCEL",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
