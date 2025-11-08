import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PermissionRecordsPage extends StatefulWidget {
  final String empId;
  const PermissionRecordsPage({super.key, required this.empId});

  @override
  State<PermissionRecordsPage> createState() => _PermissionRecordsPageState();
}

class _PermissionRecordsPageState extends State<PermissionRecordsPage> {
  String? selectedMonth;
  Map<String, String> lastSixMonths = {};

  @override
  void initState() {
    super.initState();
    _generateLastSixMonths();
  }

  /// Generate last 6 months dynamically
  void _generateLastSixMonths() {
    final now = DateTime.now();
    for (int i = 0; i < 6; i++) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('yyyy-MM').format(month);
      final label = DateFormat('MMMM yyyy').format(month);
      lastSixMonths[key] = label;
    }
    selectedMonth = lastSixMonths.keys.first;
  }

  /// Convert Timestamp → dd MMM yyyy, hh:mm a
  String _formatDateTime(Timestamp? timestamp) {
    if (timestamp == null) return '-';
    return DateFormat('dd MMM yyyy, hh:mm a').format(timestamp.toDate());
  }

  /// Status color mapping
  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;
    final isLarge = screenWidth > 900;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Permission Records"),
        backgroundColor: const Color.fromARGB(255, 247, 126, 227),
      ),
      backgroundColor: const Color.fromARGB(255, 220, 255, 250),

      body: Column(
        children: [
          // 🗓️ Month Filter Dropdown
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 3)],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Select Month:",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                DropdownButton<String>(
                  value: selectedMonth,
                  items: lastSixMonths.entries
                      .map(
                        (entry) => DropdownMenuItem<String>(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedMonth = value;
                    });
                  },
                ),
              ],
            ),
          ),

          // 📄 Permission Records Stream
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('Users')
                  .doc(widget.empId)
                  .collection('permission_request')
                  .orderBy('fromTime', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No permission records found.",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                final allPermissions = snapshot.data!.docs;

                // 🧭 Filter by selected month based on fromTime
                final filteredPermissions = allPermissions.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['fromTime'] is Timestamp) {
                    final from = (data['fromTime'] as Timestamp).toDate();
                    final key = DateFormat('yyyy-MM').format(from);
                    return key == selectedMonth;
                  }
                  return false;
                }).toList();

                if (filteredPermissions.isEmpty) {
                  return Center(
                    child: Text(
                      "No permission records for ${lastSixMonths[selectedMonth]!}.",
                      style: const TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.symmetric(
                    horizontal: isLarge ? 120 : isTablet ? 40 : 12,
                    vertical: 10,
                  ),
                  itemCount: filteredPermissions.length,
                  itemBuilder: (context, index) {
                    final permission =
                        filteredPermissions[index].data() as Map<String, dynamic>;

                    final reason = permission['reason'] ?? '-';
                    final fromTime = _formatDateTime(permission['fromTime']);
                    final toTime = _formatDateTime(permission['toTime']);
                    final status = permission['status'] ?? 'Pending';
                    final createdAt = permission['createdAt'] is Timestamp
                        ? _formatDateTime(permission['createdAt'])
                        : '-';
                    final empName = permission['name'] ?? 'Unknown';
                    final empId = permission['employeeId'] ?? widget.empId;

                    return Card(
                      elevation: 5,
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 20 : 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 🧍 Employee Info
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    empName,
                                    style: TextStyle(
                                      fontSize: isTablet ? 20 : 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.deepPurple,
                                    ),
                                  ),
                                ),
                                Text(
                                  "ID: $empId",
                                  style: TextStyle(
                                    fontSize: isTablet ? 15 : 13,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // 📝 Reason & Status
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Text(
                                    reason.toString().toUpperCase(),
                                    style: TextStyle(
                                      fontSize: isTablet ? 18 : 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color:
                                        _statusColor(status).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status,
                                    style: TextStyle(
                                      color: _statusColor(status),
                                      fontWeight: FontWeight.w600,
                                      fontSize: isTablet ? 16 : 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // ⏰ Time Info
                            Text(
                              "From: $fromTime → To: $toTime",
                              style: TextStyle(
                                fontSize: isTablet ? 16 : 14,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Applied on: $createdAt",
                              style: TextStyle(
                                fontSize: isTablet ? 15 : 13,
                                color: Colors.grey[700],
                              ),
                            ),
                            const Divider(height: 18),

                            // 🏢 Department & Company
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  permission['department'] ?? '',
                                  style: TextStyle(
                                    fontSize: isTablet ? 15 : 13,
                                    color: Colors.deepPurple,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  permission['companyName'] ?? '',
                                  style: TextStyle(
                                    fontSize: isTablet ? 15 : 13,
                                    color: Colors.teal,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
