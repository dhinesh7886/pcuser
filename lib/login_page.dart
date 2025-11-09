import 'package:flutter/material.dart';
import 'package:pcuser/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:pcuser/home.dart';
import 'package:pcuser/attendance.dart';
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
  bool? isActiveUser;
  bool passwordVisible = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  @override
  void dispose() {
    empIdController.dispose();
    otpController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkExistingLogin() async {
    final sharedInstance = await SharedPreferences.getInstance();
    final savedId = sharedInstance.getString("id");
    if (savedId != null && savedId.isNotEmpty) {
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const UsersHomePage()),
        );
      }
    } else {
      setState(() {
        _loading = false;
      });
    }
  }

  // Fetch user details + isActive status
  Future<void> _fetchUserDetails(String empId) async {
    if (empId.isEmpty) return;

    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('Users')
          .doc(empId)
          .get();

      if (docSnapshot.exists) {
        final data = docSnapshot.data()!;
        setState(() {
          firestoreName = data['name'];
          var p = data['dob'].split("/");
          firestoreDob = p[0] + p[1];
          passwordHint = _generatePasswordHint(firestoreName!, firestoreDob!);
          isActiveUser = data['isActive'] ?? false; // 👈 check active field
        });
      } else {
        setState(() {
          firestoreName = null;
          firestoreDob = null;
          passwordHint = null;
          isActiveUser = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching user details: $e");
      setState(() {
        firestoreName = null;
        firestoreDob = null;
        passwordHint = null;
        isActiveUser = false;
      });
    }
  }

  // 🧩 Alternative: If "isActive" is in subcollection instead of field
  /*
  Future<bool> _checkUserActive(String empId) async {
    try {
      final subDoc = await FirebaseFirestore.instance
          .collection('Users')
          .doc(empId)
          .collection('Status')
          .doc('isActive')
          .get();

      return subDoc.exists && (subDoc.data()?['active'] == true);
    } catch (e) {
      debugPrint("Error checking active status: $e");
      return false;
    }
  }
  */

  String generatePassword(String name, String dob) {
    final first4 =
        name.length >= 4 ? name.substring(0, 4).toUpperCase() : name.toUpperCase();
    final ddmm = dob.substring(0, 4);
    return '$first4$ddmm';
  }

  String _generatePasswordHint(String name, String dob) {
    String pwd = generatePassword(name, dob);
    return "Hint: First 4 letters of your name + DOB in DDMM format (e.g., $pwd)";
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;
    final isTablet = size.width > 600;

    double cardWidth = isTablet ? 500 : size.width * 0.95;
    double avatarRadius = isTablet ? 60 : 40;
    double iconSize = isTablet ? 60 : 50;
    double fontSizeTitle = isTablet ? 26 : 22;
    double fontSizeHint = isTablet ? 14 : 12;
    double buttonHeight = isTablet ? 55 : 50;

    return Scaffold(
      backgroundColor: Colors.teal[50],
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Card(
              elevation: 10,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Container(
                width: cardWidth,
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 32 : 24,
                  vertical: isTablet ? 40 : 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: avatarRadius,
                      backgroundColor: Colors.teal,
                      child: Icon(Icons.person, size: iconSize, color: Colors.white),
                    ),
                    SizedBox(height: isTablet ? 20 : 16),
                    Text(
                      "Welcome to PC Users",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: fontSizeTitle,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal,
                      ),
                    ),
                    SizedBox(height: isTablet ? 35 : 30),

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
                    SizedBox(height: isTablet ? 25 : 20),

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
                      SizedBox(height: isTablet ? 25 : 20),
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
                            passwordVisible
                                ? Icons.visibility
                                : Icons.visibility_off,
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
                      SizedBox(height: 8),
                      Text(
                        passwordHint!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: fontSizeHint,
                          color: Colors.grey,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    SizedBox(height: isTablet ? 25 : 20),

                    // Buttons
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        if (!userProvider.otpSent)
                          SizedBox(
                            height: buttonHeight,
                            child: ElevatedButton(
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
                          ),

                        SizedBox(
                          height: buttonHeight,
                          child: ElevatedButton(
                            onPressed: () async {
                              String empId = empIdController.text.trim();
                              if (empId.isEmpty) return;

                              // 🔍 Check if user is active before proceeding
                              if (isActiveUser == false) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text("Your account is inactive. Contact admin."),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                                return;
                              }

                              String enteredPassword = passwordController.text.trim();
                              String enteredOtp = otpController.text.trim();
                              bool success = false;

                              if (firestoreName != null &&
                                  firestoreDob != null &&
                                  enteredPassword.isNotEmpty) {
                                String generatedPwd =
                                    generatePassword(firestoreName!, firestoreDob!);
                                if (enteredPassword == generatedPwd) {
                                  success = true;
                                }
                              }

                              if (userProvider.otpSent && enteredOtp.isNotEmpty) {
                                bool otpValid = await userProvider.submit(
                                  enteredOtp,
                                  empId,
                                  context,
                                );
                                if (otpValid) success = true;
                              }

                              if (success) {
                                var sharedInstance =
                                    await SharedPreferences.getInstance();
                                sharedInstance.setString("id", empId);
                                if (mounted) {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          AttendanceScreen(userId: empId),
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
                        ),

                        SizedBox(
                          height: buttonHeight,
                          child: ElevatedButton(
                            onPressed: () async {
                              empIdController.clear();
                              otpController.clear();
                              passwordController.clear();
                              userProvider.clearState();
                              var sharedInstance =
                                  await SharedPreferences.getInstance();
                              sharedInstance.remove("id");
                              setState(() {
                                passwordHint = null;
                                firestoreName = null;
                                firestoreDob = null;
                                passwordVisible = false;
                                isActiveUser = null;
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
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
