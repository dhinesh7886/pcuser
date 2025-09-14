import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  // Pick Date
  Future<void> _pickDate() async {
    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: DateTime(today.year + 1),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // Pick From Time
  Future<void> _pickFromTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _fromTime = picked);
  }

  // Pick To Time
  Future<void> _pickToTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _fromTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _toTime = picked);
  }

  // Submit Permission Request
  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _fromTime == null ||
        _toTime == null) return;

    setState(() => _submitting = true);

    final fromDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _fromTime!.hour,
        _fromTime!.minute);
    final toDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _toTime!.hour,
        _toTime!.minute);

    try {
      final userRef =
          FirebaseFirestore.instance.collection("Users").doc(widget.userId);

      await userRef.collection("permission_requests").add({
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

  // Stream of current month requests
  Stream<QuerySnapshot> _currentMonthRequestsStream() {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    return FirebaseFirestore.instance
        .collection("Users")
        .doc(widget.userId)
        .collection("permission_requests")
        .where("date", isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where("date", isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .orderBy("date", descending: true)
        .snapshots();
  }

  // Build List of Requests
  Widget _buildRequestList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _currentMonthRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text("No permission requests this month",
                style: TextStyle(fontSize: 14, color: Colors.white70)),
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
                          child: Icon(Icons.pending_actions, color: statusColor),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat("dd MMM yyyy").format(date),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: Text(
                            status,
                            style: TextStyle(
                                color: statusColor, fontWeight: FontWeight.bold),
                          ),
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "From: ${DateFormat('hh:mm a').format(fromTime)} | To: ${DateFormat('hh:mm a').format(toTime)}",
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(height: 4),
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
      extendBodyBehindAppBar: true, // allows gradient behind AppBar
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
          // Animated Gradient Background
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
          // Blur effect
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.black.withOpacity(0)),
          ),
          SafeArea(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Permission Form
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
                                onTap: _pickDate,
                                child: AbsorbPointer(
                                  child: TextFormField(
                                    decoration: InputDecoration(
                                      labelText: _selectedDate == null
                                          ? "Select Date"
                                          : DateFormat("dd MMM yyyy")
                                              .format(_selectedDate!),
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12)),
                                      suffixIcon:
                                          const Icon(Icons.calendar_today),
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
                                          : _fromTime!.format(context)),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        backgroundColor: Colors.blueAccent,
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
                                          : _toTime!.format(context)),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 14),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        backgroundColor: Colors.blueAccent,
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
                                      _submitting ? null : _submitRequest,
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
                                    backgroundColor: Colors.blueAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Current Month Permission Requests
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          "Current Month Requests",
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Colors.white70),
                        )),
                  ),
                  const SizedBox(height: 8),
                  _buildRequestList(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
