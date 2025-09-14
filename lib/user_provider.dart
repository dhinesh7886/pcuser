import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProvider with ChangeNotifier {
  String verId = "";
  bool isSendingOtp = false;
  bool otpSent = false;

  Future<bool> getOtp(
    String empId,
    BuildContext context, {
    TextEditingController? autoFillController,
  }) async {
    if (empId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter Employee ID")),
      );
      return false;
    }

    try {
      isSendingOtp = true;
      otpSent = false;
      notifyListeners();

      final snap = await FirebaseFirestore.instance
          .collection("Users")
          .where("id", isEqualTo: empId)
          .limit(1)
          .get();

      if (snap.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Access Denied for login, Contact Admin")),
        );
        isSendingOtp = false;
        notifyListeners();
        return false;
      }

      final phoneNumber = snap.docs.first.data()['contact']?.toString();
      if (phoneNumber == null || phoneNumber.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No phone number found for this employee.")),
        );
        isSendingOtp = false;
        notifyListeners();
        return false;
      }

      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          try {
            final code = credential.smsCode;
            if (code != null && code.isNotEmpty) {
              autoFillController?.text = code;
            }
            final userCred = await FirebaseAuth.instance.signInWithCredential(credential);

            // ✅ update display name with empId
            await userCred.user?.updateDisplayName(empId);

            // ✅ save empId in local storage
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('id', empId);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Auto sign-in successful")),
            );
          } catch (_) {}
        },
        verificationFailed: (error) {
          isSendingOtp = false;
          notifyListeners();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Verification failed: ${error.message}")),
          );
        },
        codeSent: (verificationId, _) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("OTP sent to registered mobile number")),
          );
          verId = verificationId;
          otpSent = true;
          isSendingOtp = false;
          notifyListeners();
        },
        codeAutoRetrievalTimeout: (verificationId) {
          verId = verificationId;
          notifyListeners();
        },
      );

      return true;
    } catch (e) {
      isSendingOtp = false;
      notifyListeners();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error sending OTP: $e")),
      );
      return false;
    }
  }

  Future<bool> submit(String otp, String empId, BuildContext context) async {
    if (otp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Enter OTP")),
      );
      return false;
    }
    if (verId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("OTP not requested yet.")),
      );
      return false;
    }

    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: verId,
        smsCode: otp,
      );
      final userCred = await FirebaseAuth.instance.signInWithCredential(cred);

      /// ✅ Update displayName with empId
      await userCred.user?.updateDisplayName(empId);

      /// ✅ Save empId to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('id', empId);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login Successful")),
      );

      clearState();
      return true;
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to sign in: $e")),
      );
      return false;
    }
  }

  void clearState() {
    verId = "";
    isSendingOtp = false;
    otpSent = false;
    notifyListeners();
  }
}
