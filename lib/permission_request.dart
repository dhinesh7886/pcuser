import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PermissionRequestScreen extends StatefulWidget {
  final String userId;

  const PermissionRequestScreen({super.key, required this.userId});

  @override
  State<PermissionRequestScreen> createState() =>
      _PermissionRequestScreenState();
}

class _PermissionRequestScreenState extends State<PermissionRequestScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _reasonController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _fromTime;
  TimeOfDay? _toTime;
  bool _submitting = false;

  late AnimationController _animationController;
  String? _resolvedUserId;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);

    _initResolvedUserId();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _initResolvedUserId() async {
    final passed = widget.userId.trim();
    if (passed.isNotEmpty) {
      _resolvedUserId = passed;
    } else {
      try {
        final prefs = await SharedPreferences.getInstance();
        final stored = prefs.getString('id')?.trim();
        if (stored != null && stored.isNotEmpty) _resolvedUserId = stored;
      } catch (_) {}
    }
    setState(() {});
  }

  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickFromTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _fromTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _fromTime = picked);
  }

  Future<void> _pickToTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime ?? _fromTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _toTime = picked);
  }

  String? _getActiveUserId() {
    if (_resolvedUserId != null && _resolvedUserId!.isNotEmpty) return _resolvedUserId;
    if (widget.userId.trim().isNotEmpty) return widget.userId.trim();
    return null;
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _fromTime == null ||
        _toTime == null) return;

    setState(() => _submitting = true);

    final uid = _getActiveUserId();
    if (uid == null || uid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("User ID not found. Please login again.")),
      );
      setState(() => _submitting = false);
      return;
    }

    final doc = await FirebaseFirestore.instance.collection("Users").doc(uid).get();
    final userInfo = doc.exists ? doc.data()! : {};

    final fromDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _fromTime!.hour,
      _fromTime!.minute,
    );
    final toDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _toTime!.hour,
      _toTime!.minute,
    );

    try {
      final userRef = FirebaseFirestore.instance.collection("Users").doc(uid);

      await userRef.collection("permission_request").add({
        "id": uid,
        "name": userInfo['name'] ?? "",
        "companyName": userInfo['companyName'] ?? "",
        "department": userInfo['department'] ?? "",
        "designation": userInfo['designation'] ?? "",
        "subDivision": userInfo['subDivision'] ?? "",
        "date": Timestamp.fromDate(_selectedDate!),
        "fromTime": Timestamp.fromDate(fromDateTime),
        "toTime": Timestamp.fromDate(toDateTime),
        "reason": _reasonController.text.trim(),
        "status": "Pending",
        "createdAt": FieldValue.serverTimestamp(),
      });

      _reasonController.clear();
      setState(() {
        _selectedDate = null;
        _fromTime = null;
        _toTime = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Permission request submitted")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      setState(() => _submitting = false);
    }
  }

  // Only current and future requests
  Stream<QuerySnapshot> _currentAndUpcomingRequestsStream() {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    final uid = _getActiveUserId() ?? widget.userId;

    return FirebaseFirestore.instance
        .collection("Users")
        .doc(uid)
        .collection("permission_request")
        .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
        .orderBy("date", descending: false)
        .snapshots();
  }

  Widget _buildRequestList() {
    final screenWidth = MediaQuery.of(context).size.width;
    return StreamBuilder<QuerySnapshot>(
      stream: _currentAndUpcomingRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No permission requests found",
                style: TextStyle(fontSize: 22, color: Color.fromARGB(255, 5, 4, 0),
                fontWeight: FontWeight.bold)),
          );
        }

        final docs = snapshot.data!.docs;

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final date = (data['date'] as Timestamp).toDate();
            final fromTime = (data['fromTime'] as Timestamp).toDate();
            final toTime = (data['toTime'] as Timestamp).toDate();
            final reason = data['reason'] ?? "";
            final status = data['status'] ?? "Pending";

            Color statusColor;
            if (status == "Approved") {
              statusColor = Colors.green;
            } else if (status == "Rejected") {
              statusColor = Colors.red;
            } else {
              statusColor = Colors.orange;
            }

            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                          radius: screenWidth * 0.035,
                          child: Icon(Icons.pending_actions,
                              color: statusColor, size: screenWidth * 0.065),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat("dd MMM yyyy").format(date),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: screenWidth * 0.048),
                        ),
                        const Spacer(),
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: screenWidth * 0.035,
                              vertical: screenWidth * 0.012),
                          decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            status,
                            style: TextStyle(
                                color: statusColor,
                                fontWeight: FontWeight.bold,
                                fontSize: screenWidth * 0.038),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "From: ${DateFormat('hh:mm a').format(fromTime)} | To: ${DateFormat('hh:mm a').format(toTime)}",
                      style: TextStyle(
                          fontSize: screenWidth * 0.045,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 6),
                    Text(reason, style: TextStyle(fontSize: screenWidth * 0.040)),
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
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("Permission Requests"),
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
                      const Color.fromARGB(255, 230, 241, 70),
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
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: screenWidth * 0.03),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    Card(
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
                                onTap: _pickDate,
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: _selectedDate == null
                                          ? "Select Date"
                                          : DateFormat("dd MMM yyyy")
                                              .format(_selectedDate!),
                                      border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12)),
                                      suffixIcon: const Icon(Icons.calendar_today),
                                    ),
                                    validator: (value) {
                                      if (_selectedDate == null) {
                                        return "Please select a date";
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _pickFromTime,
                                      icon: const Icon(Icons.access_time),
                                      label: Text(_fromTime == null
                                          ? "From Time"
                                          : _fromTime!.format(context),
                                          style: TextStyle(
                                              fontSize: screenWidth * 0.040)),
                                      style: ElevatedButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        backgroundColor:
                                            const Color.fromARGB(255, 111, 228, 236),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: _pickToTime,
                                      icon: const Icon(Icons.access_time),
                                      label: Text(_toTime == null
                                          ? "To Time"
                                          : _toTime!.format(context),
                                          style: TextStyle(
                                              fontSize: screenWidth * 0.040)),
                                      style: ElevatedButton.styleFrom(
                                        padding:
                                            const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12)),
                                        backgroundColor:
                                            const Color.fromARGB(255, 111, 228, 236),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _reasonController,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: "Reason",
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12)),
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
                                  onPressed:
                                      (_submitting || _resolvedUserId == null)
                                          ? null
                                          : _submitRequest,
                                  icon: const Icon(Icons.send),
                                  label: Text(
                                    _submitting ? "Submitting..." : "Submit Request",
                                    style: TextStyle(
                                        fontSize: screenWidth * 0.043),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12)),
                                    backgroundColor:
                                        const Color.fromARGB(255, 111, 228, 236),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Current & Upcoming Requests",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: screenWidth * 0.045,
                            color: const Color.fromARGB(179, 3, 0, 0)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildRequestList(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
