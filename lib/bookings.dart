import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:pcuser/mapview.dart';
import 'package:pcuser/razor_pay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CabBookingPage extends StatefulWidget {
  const CabBookingPage({super.key});

  @override
  State<CabBookingPage> createState() => _CabBookingPageState();
}

class _CabBookingPageState extends State<CabBookingPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  final TextEditingController _daysController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  double amount = 0;
  DateTime? _startDate;
  TimeOfDay? _loginTime;
  bool _isLoading = false;
  LatLng? _pickupLatLng;
  LatLng? _dropLatLng;
  double _distance = 0.0;
  final RazorpayService _razorpayService = RazorpayService();

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) {
      setState(() {
        _loginTime = picked;
      });
    }
  }

  void _calculateDistanceAndPrice() {
    if (_pickupLatLng != null && _dropLatLng != null) {
      final distanceInMeters = Geolocator.distanceBetween(
        _pickupLatLng!.latitude,
        _pickupLatLng!.longitude,
        _dropLatLng!.latitude,
        _dropLatLng!.longitude,
      );

      setState(() {
        _distance = distanceInMeters / 1000; // Convert to kilometers
        amount = _distance * 12; // 12 rs per kilometer
      });
    }
  }

  Future<void> _storeBookingToFirebase() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _loginTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date and login time")),
      );
      return;
    }
    try {
      setState(() {
        _isLoading = true;
      });
      var sharedInstance = await SharedPreferences.getInstance();
      final String empId = sharedInstance.getString("id") ?? "";
      final snap = await FirebaseFirestore.instance
          .collection("Users")
          .where("id", isEqualTo: empId)
          .limit(1)
          .get();
      var snapsot = snap.docs.first.data();
      await FirebaseFirestore.instance.collection('bookings').add({
        'userId': empId,
        'name': snapsot["name"],
        'companyName': snapsot['companyName'],
        'department': snapsot['department'],
        'designation': snapsot['designation'],
        'subDivision': snapsot['subDivision'],
        'pickupPlace': _pickupController.text.trim(),
        'pickupLat': _pickupLatLng?.latitude,
        'pickupLng': _pickupLatLng?.longitude,
        'dropPlace': _dropController.text.trim(),
        'dropLat': _dropLatLng?.latitude,
        'dropLng': _dropLatLng?.longitude,
        'daysRequired': int.tryParse(_daysController.text.trim()) ?? 1,
        'notes': _notesController.text.trim(),
        'startDate': _startDate!.toIso8601String(),
        'loginTime': _loginTime!.format(context),
        'distance': _distance,
        'amount': amount,
        'createdAt': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Booking submitted successfully!")),
      );

      // Clear all fields after successful booking
      setState(() {
        // Clear text fields
        _pickupController.clear();
        _dropController.clear();
        _daysController.clear();
        _notesController.clear();

        // Reset locations
        _pickupLatLng = null;
        _dropLatLng = null;

        // Reset date and time
        _startDate = null;
        _loginTime = null;

        // Reset distance and amount
        _distance = 0.0;
        amount = 0;
      });
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _razorpayService.init(); // ✅ initialize once
  }

  @override
  void dispose() {
    _razorpayService.dispose(); // ✅ clear listeners
    super.dispose();
  }

  // ✅ Use the same instance to pay
  void _startPayment() async {
    _calculateDistanceAndPrice();
    _razorpayService.pay(
      amount: amount,
      onSuccess: (response) {
        print("✅ Payment Success: ${response.paymentId}");
        _storeBookingToFirebase();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Payment Successful: ${response.paymentId}")),
        );
      },
      onError: (error) {
        print("❌ Payment failed: ${error.message}");
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text("Payment failed: ${error.message ?? 'Unknown error'}")),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Cab Booking"),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // Trip start date
              ListTile(
                leading: const Icon(
                  Icons.calendar_today,
                  color: Colors.deepPurple,
                ),
                title: Text(
                  _startDate == null
                      ? "Select Trip Start Date"
                      : "Trip Start Date: ${_startDate!.day}-${_startDate!.month}-${_startDate!.year}",
                ),
                trailing: ElevatedButton(
                  onPressed: _pickDate,
                  child: const Text("Pick Date"),
                ),
              ),
              const SizedBox(height: 12),

              // Login time
              ListTile(
                leading: const Icon(
                  Icons.access_time,
                  color: Colors.deepPurple,
                ),
                title: Text(
                  _loginTime == null
                      ? "Select Login Time"
                      : "Login Time: ${_loginTime!.format(context)}",
                ),
                trailing: ElevatedButton(
                  onPressed: _pickTime,
                  child: const Text("Pick Time"),
                ),
              ),
              const SizedBox(height: 12),

              // Number of days
              TextFormField(
                controller: _daysController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Number of Days Required",
                  prefixIcon: const Icon(Icons.calendar_view_day),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter number of days";
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Pickup place
              TextFormField(
                controller: _pickupController,
                decoration: InputDecoration(
                  labelText: "Pickup Place",
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: _pickupController.text.isEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.map,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MapView(),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _pickupLatLng = result["latLng"];
                                _pickupController.text = result["address"];
                              });
                            }
                          },
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            try {
                              final locations = await locationFromAddress(
                                _pickupController.text.trim(),
                              );
                              if (locations.isNotEmpty) {
                                setState(() {
                                  _pickupLatLng = LatLng(
                                    locations.first.latitude,
                                    locations.first.longitude,
                                  );
                                });
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not find location"),
                                ),
                              );
                            }
                          },
                        ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter pickup place";
                  }
                  return null;
                },
              ),
              SizedBox(
                height: 15,
              ),
              // Drop place
              TextFormField(
                controller: _dropController,
                decoration: InputDecoration(
                  labelText: "Dropping Place",
                  prefixIcon: const Icon(Icons.location_on),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  suffixIcon: _dropController.text.isEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.map,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const MapView(),
                              ),
                            );
                            if (result != null) {
                              setState(() {
                                _dropLatLng = result["latLng"];
                                _dropController.text = result["address"];
                              });
                            }

                            _calculateDistanceAndPrice();
                          },
                        )
                      : IconButton(
                          icon: const Icon(
                            Icons.search,
                            color: Colors.deepPurple,
                          ),
                          onPressed: () async {
                            try {
                              final locations = await locationFromAddress(
                                _dropController.text.trim(),
                              );
                              if (locations.isNotEmpty) {
                                setState(() {
                                  _pickupLatLng = LatLng(
                                    locations.first.latitude,
                                    locations.first.longitude,
                                  );
                                });
                                _calculateDistanceAndPrice();
                              }
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text("Could not find location"),
                                ),
                              );
                            }
                          },
                        ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return "Enter pickup place";
                  }
                  return null;
                },
              ),

              //             TextFormField(
              //               controller: _pickupController,
              //               decoration: InputDecoration(
              //                 labelText: "Pickup Place",
              //                 prefixIcon: const Icon(Icons.location_on),
              //                 border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              //                 suffix: TextButton(onPressed: () async {
              //                 var status = await Permission.location.status;
              //                 if(status.isGranted){
              //                  var r = await Geolocator.getCurrentPosition();
              //                  print(r.latitude);
              //                  print(r.longitude);
              //                 } else {
              //                   await Permission.location.request();
              //                 }
              // // Navigator.of(context).push(MaterialPageRoute(builder: (context) => MapView()));
              //                 }, child: Text("Open Map"))
              //               ),
              //               validator: (value) {
              //                 if (value == null || value.isEmpty) {
              //                   return "Enter pickup place";
              //                 }
              //                 return null;
              //               },
              //             ),
              const SizedBox(height: 12),

              // Distance and Price Information
              if (_distance > 0)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Text(
                          'Distance: ${_distance.toStringAsFixed(2)} km',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Price: \$${amount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),

              // Additional notes
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: "Additional Notes (Optional)",
                  prefixIcon: const Icon(Icons.note),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 20),
              // Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      foregroundColor: Colors.white,
                      iconColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _isLoading ? null : _startPayment,
                    icon: _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                          )
                        : const Icon(Icons.send),
                    label: const Text("Submit"),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      // Navigator.pop(context);
                      print(FirebaseAuth.instance.currentUser?.uid);
                    },
                    icon: const Icon(Icons.cancel),
                    label: const Text("Cancel"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
