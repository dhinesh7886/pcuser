import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String? empId;

  @override
  void initState() {
    super.initState();
    _loadEmpId();
  }

  Future<void> _loadEmpId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      empId = prefs.getString("id"); // ✅ Employee ID from login
    });
  }

  @override
  Widget build(BuildContext context) {
    if (empId == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Profile"),
        backgroundColor: Colors.deepPurple,
      ),
      body: StreamBuilder<QuerySnapshot>(
        // ✅ Fetch user based on Employee ID saved in SharedPreferences
        stream: FirebaseFirestore.instance
            .collection("Users")
            .where("id", isEqualTo: empId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("Profile data not found"));
          }

          var data = snapshot.data!.docs.first.data() as Map<String, dynamic>;

          return SingleChildScrollView(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Profile Image Top Center
                CircleAvatar(
                  radius: 60,
                  backgroundImage: (data['imageUrl'] != null &&
                          data['imageUrl'].toString().isNotEmpty)
                      ? NetworkImage(data['imageUrl'])
                      : const NetworkImage("https://via.placeholder.com/150"),
                ),
                const SizedBox(height: 20),

                // Details Row by Row
                _buildProfileRow("Employee ID", data['id']),
                _buildProfileRow("Name", data['name']),
                _buildProfileRow("Gender", data['gender']),
                _buildProfileRow("Email", data['email']),
                _buildProfileRow("Contact Number", data['contact']),
                _buildProfileRow("Address", data['address']),
                _buildProfileRow("Designation", data['designation']),
                _buildProfileRow("Department", data['department']),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              "$label:",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.toString() ?? "-",
              style: const TextStyle(fontSize: 16, color: Colors.black54),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
