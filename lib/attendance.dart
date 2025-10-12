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
  String? companyName;
  String? subDivision;
  bool _loadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserDetails();
  }

  Future<void> _loadUserDetails() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('Users')
          .where('id', isEqualTo: widget.userId)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        empName = data['name'] ?? widget.userId;
        companyName = data['companyName'];
        subDivision = data['subDivision'];
      } else {
        empName = "User not found";
      }

      await _checkAndCreateHoliday();
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

  Future<void> _checkAndCreateHoliday() async {
    if (companyName == null || subDivision == null) return;

    final now = DateTime.now();
    final dateKey = DateFormat('ddMMyyyy').format(now);

    final holidayMap = {
      'AYCA PC|Corporate': {
        '20102025': 'Deepavali',
        '25122025': 'Christmas',
      },
      'AYCA PC|Isuzu': {
        '20102025': 'Diwali',
        '21102025': 'Additional Holiday for Diwali',
        '25122025': 'Christmas',
      },
    };

    final key = '$companyName|$subDivision';
    final holidays = holidayMap[key];

    if (holidays == null || !holidays.containsKey(dateKey)) return;

    final reason = holidays[dateKey]!;

    final recordRef = FirebaseFirestore.instance
        .collection('attendance')
        .doc(widget.userId)
        .collection('records');

    final existing = await recordRef
        .where('dateKey', isEqualTo: dateKey)
        .where('type', isEqualTo: 'holiday')
        .get();

    if (existing.docs.isEmpty) {
      await recordRef.add({
        'timestamp': Timestamp.fromDate(now),
        'type': 'holiday',
        'reason': reason,
        'dateKey': dateKey,
        'companyName': companyName,
        'subDivision': subDivision,
      });

      if (mounted) {
        setState(() {
          status =
              "Holiday marked automatically: $reason (${DateFormat('dd/MM/yyyy').format(now)})";
        });
      }
    }
  }

  Future<void> _markAttendance() async {
    if (saving) return;
    setState(() {
      saving = true;
      status = "Marking attendance...";
    });

    try {
      // Check location services
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => status = "Location services are disabled.");
        return;
      }

      // Check permissions
      LocationPermission permission = await Geolocator.checkPermission();
      print(permission);
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

      final now = DateTime.now();
      final dateKey = DateFormat('ddMMyyyy').format(now);

      // Adjust early morning punch (before 5 AM)
      DateTime adjustedDate = now;
      if (now.hour < 5) {
        adjustedDate = now.subtract(const Duration(days: 1));
      }

      final startOfDay =
          DateTime(adjustedDate.year, adjustedDate.month, adjustedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // Get today’s existing punches
      final todayRecordsSnapshot = await FirebaseFirestore.instance
          .collection('attendance')
          .doc(widget.userId)
          .collection('records')
          .where('timestamp', isGreaterThanOrEqualTo: startOfDay)
          .where('timestamp', isLessThan: endOfDay)
          .get();

      final punchRecords = todayRecordsSnapshot.docs
          .where(
              (doc) => doc['type'] == 'punch_in' || doc['type'] == 'punch_out')
          .toList();

      if (punchRecords.length >= 2) {
        setState(() => status = "Already punched in & out today!");
        return;
      }

      // Get location (with timeout)
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 15));

      String address = "Unknown location";
      try {
        final placemarks =
            await placemarkFromCoordinates(pos.latitude, pos.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          address = [
            p.name,
            p.street,
            p.locality,
            p.administrativeArea,
            p.country
          ].whereType<String>().where((e) => e.trim().isNotEmpty).join(', ');
        }
      } catch (_) {
        address = "Unable to fetch address";
      }

      final type = punchRecords.isEmpty ? 'punch_in' : 'punch_out';

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
        'dateKey': dateKey,
      });

      if (mounted) {
        setState(() {
          status =
              "${type == 'punch_in' ? "Punch In" : "Punch Out"} saved at ${DateFormat('HH:mm').format(now)}\n$address";
        });
      }
    } catch (e) {
      setState(() => status = "Error saving attendance: $e");
    } finally {
      if (mounted) setState(() => saving = false);
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
            child: Text("No attendance marked today",
                style: TextStyle(color: Colors.white)),
          );
        }

        QueryDocumentSnapshot? punchInDoc;
        QueryDocumentSnapshot? punchOutDoc;
        QueryDocumentSnapshot? holidayDoc;

        try {
          punchInDoc =
              snapshot.data!.docs.firstWhere((d) => d['type'] == 'punch_in');
        } catch (_) {}
        try {
          punchOutDoc =
              snapshot.data!.docs.firstWhere((d) => d['type'] == 'punch_out');
        } catch (_) {}
        try {
          holidayDoc =
              snapshot.data!.docs.firstWhere((d) => d['type'] == 'holiday');
        } catch (_) {}

        return SingleChildScrollView(
          child: Column(
            children: [
              if (holidayDoc != null) _buildHolidayCard(holidayDoc),
              if (punchInDoc != null) _buildRecordCard(punchInDoc, true),
              if (punchOutDoc != null) _buildRecordCard(punchOutDoc, false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHolidayCard(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final reason = data['reason'] ?? 'Holiday';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final dateStr = ts != null ? DateFormat('dd/MM/yyyy').format(ts) : '';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.yellow.shade100,
      child: ListTile(
        leading: const Icon(Icons.beach_access, color: Colors.orange),
        title: Text("Holiday: $reason"),
        subtitle: Text(dateStr),
      ),
    );
  }

  Widget _buildRecordCard(QueryDocumentSnapshot doc, bool isPunchIn) {
    final data = doc.data() as Map<String, dynamic>;
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final timeStr = ts != null ? DateFormat('HH:mm').format(ts) : 'Pending';
    final address = data['address'] ?? 'No address';
    final width = MediaQuery.of(context).size.width;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: Colors.white.withOpacity(0.9),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPunchIn ? Colors.green : Colors.red,
          child: Icon(
            isPunchIn ? Icons.login : Icons.logout,
            color: Colors.white,
            size: width * 0.07,
          ),
        ),
        title: Text("${isPunchIn ? "Punch In" : "Punch Out"} • $timeStr",
            style: TextStyle(fontSize: width * 0.045)),
        subtitle: Text(address, style: TextStyle(fontSize: width * 0.035)),
      ),
    );
  }

  Widget _fullWidthButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    double width = MediaQuery.of(context).size.width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width * 0.04, vertical: 8),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          minimumSize: Size(double.infinity, width * 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
        icon: Icon(icon, color: Colors.white, size: width * 0.06),
        label: Text(
          label,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: width * 0.045),
        ),
        onPressed: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _loadingUser ? "Loading..." : (empName ?? widget.userId);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
        backgroundColor: Colors.teal,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF00BFA6), Color(0xFF00E5FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(status,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black87)),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: Colors.white70, thickness: 1),
                  const Text(
                    "Today's Records",
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                  ),
                  SizedBox(
                      height: MediaQuery.of(context).size.height * 0.45,
                      child: _buildRecordsList()),
                  _fullWidthButton(
                      icon: Icons.request_page,
                      label: "Permission Request",
                      color: Colors.orange,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) => PermissionRequestScreen(
                                    userId: widget.userId)));
                      }),
                  _fullWidthButton(
                      icon: Icons.leave_bags_at_home,
                      label: "Leave Request",
                      color: Colors.blue,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    LeaveRequestScreen(userId: widget.userId)));
                      }),
                  _fullWidthButton(
                      icon: Icons.data_usage,
                      label: "Attendance Data",
                      color: Colors.green,
                      onTap: () {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (context) =>
                                    AttendanceDataScreen(userId: widget.userId)));
                      }),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: StreamBuilder<QuerySnapshot>(
        stream: _todayRecordsStream(),
        builder: (context, snapshot) {
          int count = snapshot.data?.docs
                  .where((d) =>
                      d['type'] == 'punch_in' || d['type'] == 'punch_out')
                  .length ??
              0;
          String label =
              count == 0 ? "Punch In" : count == 1 ? "Punch Out" : "Completed";
          return FloatingActionButton.extended(
            onPressed: (saving || count >= 2) ? null : _markAttendance,
            icon: const Icon(Icons.fingerprint),
            label: Text(label),
            backgroundColor: const Color.fromARGB(255, 240, 217, 87),
          );
        },
      ),
    );
  }
}
