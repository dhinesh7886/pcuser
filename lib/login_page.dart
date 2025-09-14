import 'package:flutter/material.dart';
import 'package:pcuser/user_provider.dart';
import 'package:provider/provider.dart';
import 'package:pcuser/home.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StylishLoginPage extends StatefulWidget {
  const StylishLoginPage({super.key});

  @override
  State<StylishLoginPage> createState() => _StylishLoginPageState();
}

class _StylishLoginPageState extends State<StylishLoginPage> {
  final TextEditingController empIdController = TextEditingController();
  final TextEditingController otpController = TextEditingController();

  @override
  void dispose() {
    empIdController.dispose();
    otpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);

    return Scaffold(
      backgroundColor: Colors.teal[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: Padding(
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
                  ),
                  const SizedBox(height: 20),

                  // OTP field (only after otpSent = true)
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

                      if (userProvider.otpSent)
                        ElevatedButton(
                          onPressed: () async {
                            bool success = await userProvider.submit(
                              otpController.text.trim(),       // OTP
                              empIdController.text.trim(),     // Employee ID
                              context,                         // Context
                            );
                            var sharedInstance = await SharedPreferences.getInstance();
                            sharedInstance.setString("id", empIdController.text.trim());
                            if (success && mounted) {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const UsersHomePage(), // Home Page
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
                          userProvider.clearState();
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
      ),
    );
  }
}
