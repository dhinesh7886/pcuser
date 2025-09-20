import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  GoogleMapController? _mapController;
  LatLng? _pickedLocation;
  String? _pickedAddress;

  LatLng? _currentLocation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentLocation();
  }

  Future<void> _fetchCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Location permissions are denied")),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Location permissions is required to continue"),
          ),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error getting location: $e")));
    }
  }

  Future<void> _onMapTap(LatLng position) async {
    setState(() {
      _pickedLocation = position;
      _pickedAddress = null; // reset while loading
    });

    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _pickedAddress =
              "${place.name}, ${place.subLocality}, ${place.locality},  ${place.administrativeArea}, ${place.country}";
        });
      }
    } catch (e) {
      setState(() {
        _pickedAddress = "Unknown location";
      });
    }
  }

  void _onConfirm() {
    if (_pickedLocation != null && _pickedAddress != null) {
      Navigator.pop(context, {
        "latLng": _pickedLocation,
        "address": _pickedAddress,
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please pick a location on the map")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Pick Location"),
        backgroundColor: Colors.deepPurple,
        actions: [
          TextButton(
            onPressed: _onConfirm,
            child: const Text(
              "CONFIRM",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body:
          _loading
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target:
                      _currentLocation ??
                      const LatLng(12.9716, 77.5946), // Chennai Location
                  zoom: 14,
                ),
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                onTap: _onMapTap,
                markers:
                    _pickedLocation == null
                        ? {}
                        : {
                          Marker(
                            markerId: const MarkerId("picked"),
                            position: _pickedLocation!,
                          ),
                        },
              ),
    );
  }
}
