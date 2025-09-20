import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:intl/intl.dart';
import 'package:pcuser/permission_request.dart';
import 'package:pcuser/leave_request.dart';
import 'package:pcuser/attendance_data.dart';

class AttendanceScreen extends StatefulWidget {
  final String userId;

  const AttendanceScreen({super.key, required this.userId});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  bool saving = false;
  String status = "Tap the button to mark attendance";
  String? empName;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  // Load user name from Firestore using 'id' field
  Future<void> _loadUserName() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        empName = data['name'] ?? widget.userId;
      } else {
        empName = "User not found";
      }
    } catch (e) {
      empName = "Error loading user";
    } finally {
      if (mounted) setState(() => _loadingUser = false);
    }
  }

  DateTime _startOfDay() =>
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);

  DateTime _endOfDay() => _startOfDay().add(const Duration(days: 1));

  Stream<QuerySnapshot> _todayRecordsStream() {
    return FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records')
        .where('timestamp', isGreaterThanOrEqualTo: _startOfDay())
        .where('timestamp', isLessThan: _endOfDay())
        .orderBy('timestamp')
        .snapshots();
  }

  Future<void> _markAttendance() async {
    setState(() {
      saving = true;
      status = "Marking attendance...";
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => status = "Location services are disabled.");
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => status = "Location permission denied.");
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => status = "Location permanently denied.");
        return;
      }

      // Get current time
      final now = DateTime.now();

      // Adjust punch date: if time is before 5AM, assign to previous day
      DateTime adjustedDate = now;
      if (now.hour < 5) {
        adjustedDate = now.subtract(const Duration(days: 1));
      }

      final startOfDay =
          DateTime(adjustedDate.year, adjustedDate.month, adjustedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final todayRecordsSnapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThan: endOfDay)
          .get();

      if (todayRecordsSnapshot.docs.length >= 2) {
        setState(() => status = "Already punched in & out today!");
        return;
      }

      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      String address = "Unknown";
      try {
        final placemarks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = [
            p.name,
            p.street,
            p.subLocality,
            p.locality,
            p.subAdministrativeArea,
            p.administrativeArea,
            p.postalCode,
            p.country,
          ].where((e) => e != null && e.trim().isNotEmpty).toList();
          address = parts.join(', ');
        }
      } catch (_) {}

      final type = todayRecordsSnapshot.docs.isEmpty ? 'punch_in' : 'punch_out';

      await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .add({
        'timestamp': Timestamp.fromDate(now),
        'adjustedDate': Timestamp.fromDate(adjustedDate),
        'lat': pos.latitude,
        'lng': pos.longitude,
        'address': address,
        'type': type,
      });

      setState(() {
        status =
            "${type == 'punch_in' ? "Punch In" : "Punch Out"} saved at ${DateFormat('hh:mm a').format(now)}\n$address";
      });
    } catch (e) {
      setState(() => status = "Error saving attendance: $e");
    } finally {
      setState(() => saving = false);
    }
  }

  Widget _buildRecordsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _todayRecordsStream(),
      builder: (context, snapshot) {
        if (_loadingUser) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No attendance marked today",
              style: TextStyle(color: Colors.white),
            ),
          );
        }

        // ✅ Fix for null-safe firstWhere
        QueryDocumentSnapshot? punchInDoc;
        QueryDocumentSnapshot? punchOutDoc;

        try {
          punchInDoc = snapshot.data!.docs
              .firstWhere((doc) => doc['type'] == 'punch_in');
        } catch (_) {
          punchInDoc = null;
        }

        try {
          punchOutDoc = snapshot.data!.docs
              .firstWhere((doc) => doc['type'] == 'punch_out');
        } catch (_) {
          punchOutDoc = null;
        }

        return Column(
          children: [
            if (punchInDoc != null) ...[
              _buildRecordCard(punchInDoc, true),
            ],
            if (punchOutDoc != null) ...[
              _buildRecordCard(punchOutDoc, false),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRecordCard(QueryDocumentSnapshot doc, bool isPunchIn) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('hh:mm a').format(ts) : 'Pending';
    final address = data['address'] ?? 'No address';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      elevation: 5,
      color: Colors.white.withOpacity(0.9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPunchIn ? Colors.green : Colors.red,
          child: Icon(
            isPunchIn ? Icons.login : Icons.logout,
            color: Colors.white,
          ),
        ),
        title: Text(
          "${isPunchIn ? "Punch In" : "Punch Out"} • $timeStr",
        ),
        subtitle: Text(address),
      ),
    );
  }

  Widget _fullWidthButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: const Size.fromHeight(55),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          elevation: 6,
        ),
        icon: Icon(icon, color: Colors.white),
        label: Text(
          label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _loadingUser ? "Loading..." : "${empName ?? widget.userId}";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00BFA6), Color(0xFF00E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            children: [
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(
                    status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Divider(color: Colors.white70, thickness: 1),
              const SizedBox(height: 8),
              const Text(
                "Today's Records",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(height: 300, child: _buildRecordsList()),
              const SizedBox(height: 16),
              _fullWidthButton(
                icon: Icons.request_page,
                label: "Permission Request",
                color: Colors.orange,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          PermissionRequestScreen(userId: widget.userId),
                    ),
                  );
                },
              ),
              _fullWidthButton(
                icon: Icons.leave_bags_at_home,
                label: "Leave Request",
                color: Colors.blue,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          LeaveRequestScreen(userId: widget.userId),
                    ),
                  );
                },
              ),
              _fullWidthButton(
                icon: Icons.data_usage,
                label: "Attendance Data",
                color: Colors.green,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) =>
                          AttendanceDataScreen(userId: widget.userId),
                    ),
                  );
                },
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _todayRecordsStream(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs.length ?? 0;
          String label =
              count == 0 ? "Punch In" : count == 1 ? "Punch Out" : "Completed";

          return FloatingActionButton.extended(
            onPressed: (saving || count >= 2) ? null : _markAttendance,
            icon: const Icon(Icons.fingerprint),
            label: Text(label),
            backgroundColor: Colors.teal,
          );
        },
      ),
    );
  }
}
