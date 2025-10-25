import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LeaveRequestScreen extends StatefulWidget {
  final String userId;

  const LeaveRequestScreen({super.key, required this.userId});

  @override
  State<LeaveRequestScreen> createState() => _LeaveRequestScreenState();
}

class _LeaveRequestScreenState extends State<LeaveRequestScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  bool _submitting = false;

  late AnimationController _animationController;

  String? _userName;
  String? _subDivision;
  String? _companyName;
  String? _department;
  String? _designation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _fetchUserDetails();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  /// ✅ Fetch user details from Firestore using userId
  Future<void> _fetchUserDetails() async {
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection("Users")
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        final data = userDoc.data()!;
        setState(() {
          _userName = data['name'] ?? '';
          _companyName = data['companyName'] ?? '';
          _department = data['department'] ?? '';
          _designation = data['designation'] ?? '';
          _subDivision = data['subDivision'] ?? '';
        });

        // Store details in SharedPreferences for later use
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("name", _userName ?? '');
        await prefs.setString("companyName", _companyName ?? '');
        await prefs.setString("department", _department ?? '');
        await prefs.setString("designation", _designation ?? '');
        await prefs.setString("subDivision", _subDivision ?? '');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("User not found in Firestore")),
        );
      }
    } catch (e) {
      debugPrint("Error fetching user details: $e");
    }
  }

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? today,
      firstDate: _startDate ?? today,
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null) setState(() => _endDate = picked);
  }

  /// ✅ Submit leave request and store full user details in Firestore
  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() ||
        _startDate == null ||
        _endDate == null) return;

    setState(() => _submitting = true);

    try {
      final userRef =
          FirebaseFirestore.instance.collection("Users").doc(widget.userId);

      // Check overlapping leave dates
      final existingLeavesSnapshot =
          await userRef.collection("leave_requests").get();
      bool overlap = existingLeavesSnapshot.docs.any((doc) {
        final data = doc.data();
        final existingStart = (data['startDate'] as Timestamp).toDate();
        final existingEnd = (data['endDate'] as Timestamp).toDate();
        return !(_endDate!.isBefore(existingStart) ||
            _startDate!.isAfter(existingEnd));
      });

      if (overlap) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text("Leave request overlaps with an existing request")),
        );
        setState(() => _submitting = false);
        return;
      }

      // Add leave request with all user details
      await userRef.collection("leave_requests").add({
        "startDate": Timestamp.fromDate(_startDate!),
        "endDate": Timestamp.fromDate(_endDate!),
        "reason": _reasonController.text.trim(),
        "status": "Waiting for Approval",
        "createdAt": FieldValue.serverTimestamp(),
        "id": widget.userId,
        "name": _userName ?? '',
        "subDivision": _subDivision ?? '',
        "companyName": _companyName ?? '',
        "department": _department ?? '',
        "designation": _designation ?? '',
      });

      _reasonController.clear();
      setState(() {
        _startDate = null;
        _endDate = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Leave request submitted successfully")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error submitting leave request: $e")),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  /// ✅ Stream only current + upcoming month leaves
  Stream<QuerySnapshot> _leaveRequestsStream() {
    final now = DateTime.now();
    final startOfCurrentMonth = DateTime(now.year, now.month, 1);
    final startOfNextMonth =
        DateTime(now.year, now.month + 2, 1); // include next month

    return FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.userId)
        .collection("leave_requests")
        .where("startDate",
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfCurrentMonth))
        .where("startDate", isLessThan: Timestamp.fromDate(startOfNextMonth))
        .orderBy("startDate", descending: false)
        .snapshots();
  }

  Widget _buildRequestList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _leaveRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              "No leave requests for current or upcoming month",
              style: TextStyle(fontSize: 14, color: Colors.white70),
            ),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final startDate = (data['startDate'] as Timestamp).toDate();
            final endDate = (data['endDate'] as Timestamp).toDate();
            final reason = data['reason'] ?? "";
            final status = data['status'] ?? "Waiting for Approval";

            Color statusColor;
            if (status == "Approved") {
              statusColor = Colors.green;
            } else if (status == "Not Approved") {
              statusColor = Colors.red;
            } else {
              statusColor = Colors.orange;
            }

            return Card(
              margin:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 8,
              shadowColor: Colors.black45,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: statusColor.withOpacity(0.2),
                          child: Icon(Icons.pending_actions,
                              color: statusColor),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            "${DateFormat("dd MMM yyyy").format(startDate)} - ${DateFormat("dd MMM yyyy").format(endDate)}",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            status,
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(reason, style: const TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Leave Requests"),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.blueAccent.shade700,
                      Colors.purpleAccent.shade200,
                      Colors.orangeAccent.shade200,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    stops: [
                      _animationController.value * 0.5,
                      0.5 + _animationController.value * 0.5,
                      1.0,
                    ],
                  ),
                ),
              );
            },
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.black.withOpacity(0)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Card(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      elevation: 12,
                      shadowColor: Colors.black38,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            children: [
                              GestureDetector(
                                onTap: _pickStartDate,
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: _startDate == null
                                          ? "Start Date"
                                          : DateFormat("dd MMM yyyy")
                                              .format(_startDate!),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      suffixIcon:
                                          const Icon(Icons.calendar_today),
                                    ),
                                    validator: (value) {
                                      if (_startDate == null) {
                                        return "Please select start date";
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              GestureDetector(
                                onTap: _pickEndDate,
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: _endDate == null
                                          ? "End Date"
                                          : DateFormat("dd MMM yyyy")
                                              .format(_endDate!),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      suffixIcon:
                                          const Icon(Icons.calendar_today),
                                    ),
                                    validator: (value) {
                                      if (_endDate == null) {
                                        return "Please select end date";
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _reasonController,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: "Reason",
                                  border: OutlineInputBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return "Please enter reason";
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : _submitRequest,
                                  icon: const Icon(Icons.send),
                                  label: Text(_submitting
                                      ? "Submitting..."
                                      : "Submit Request"),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildRequestList(),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
