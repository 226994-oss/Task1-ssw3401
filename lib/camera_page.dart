import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraPage extends StatefulWidget {
  const CameraPage({super.key});

  @override
  State<CameraPage> createState() => _CameraPageState();
}

class _CameraPageState extends State<CameraPage> {
  static const _keyImagePath = 'cached_image_path';
  static const _keyLatitude = 'cached_latitude';
  static const _keyLongitude = 'cached_longitude';
  static const _keyLocationStatus = 'cached_location_status';
  static const _keySavedAt = 'cached_saved_at';

  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  double? _latitude;
  double? _longitude;
  String _locationStatus = 'No GPS data yet';
  String? _savedAt;
  bool _isLoading = false;
  bool _showSettingsButton = false;

  @override
  void initState() {
    super.initState();
    _loadCachedData();
  }

  // Restore last saved photo and coordinates from SharedPreferences on startup.
  Future<void> _loadCachedData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPath = prefs.getString(_keyImagePath);
    final validPath =
        (savedPath != null && File(savedPath).existsSync()) ? savedPath : null;

    if (!mounted) return;
    setState(() {
      _imagePath = validPath;
      _latitude = prefs.getDouble(_keyLatitude);
      _longitude = prefs.getDouble(_keyLongitude);
      _locationStatus =
          prefs.getString(_keyLocationStatus) ?? 'No GPS data yet';
      _savedAt = prefs.getString(_keySavedAt);
    });
  }

  Future<void> _saveToCache({
    required String imagePath,
    required double? latitude,
    required double? longitude,
    required String locationStatus,
    required String savedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyImagePath, imagePath);
    await prefs.setString(_keyLocationStatus, locationStatus);
    await prefs.setString(_keySavedAt, savedAt);

    if (latitude != null && longitude != null) {
      await prefs.setDouble(_keyLatitude, latitude);
      await prefs.setDouble(_keyLongitude, longitude);
    } else {
      await prefs.remove(_keyLatitude);
      await prefs.remove(_keyLongitude);
    }
  }

  Future<void> _captureAndTag() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _showSettingsButton = false;
    });

    try {
      // Request camera permission before opening the camera.
      final cameraStatus = await Permission.camera.request();
      if (!cameraStatus.isGranted) {
        if (!mounted) return;
        setState(() {
          _showSettingsButton = cameraStatus.isPermanentlyDenied;
        });
        _showMessage(
          cameraStatus.isPermanentlyDenied
              ? 'Camera permission permanently denied. Enable it in Settings.'
              : 'Camera permission denied.',
        );
        return;
      }

      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (photo == null) {
        return;
      }

      // Copy image to app documents directory so it persists across restarts.
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedFile = await File(photo.path).copy('${appDir.path}/$fileName');

      final gpsResult = await _getCurrentCoordinates();
      final timestamp = _formatTimestamp(DateTime.now());

      await _saveToCache(
        imagePath: savedFile.path,
        latitude: gpsResult.latitude,
        longitude: gpsResult.longitude,
        locationStatus: gpsResult.status,
        savedAt: timestamp,
      );

      if (!mounted) return;
      setState(() {
        _imagePath = savedFile.path;
        _latitude = gpsResult.latitude;
        _longitude = gpsResult.longitude;
        _locationStatus = gpsResult.status;
        _savedAt = timestamp;
        _showSettingsButton = gpsResult.permanentlyDenied;
      });

      if (gpsResult.latitude == null) {
        _showMessage(gpsResult.status);
      }
    } catch (e) {
      _showMessage('Failed to capture photo: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Request location permission and return coordinates, or a status message on denial.
  Future<_GpsResult> _getCurrentCoordinates() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const _GpsResult(
        status: 'GPS is turned off on this device.',
      );
    }

    final locationStatus = await Permission.locationWhenInUse.request();
    if (!locationStatus.isGranted) {
      return _GpsResult(
        status: locationStatus.isPermanentlyDenied
            ? 'Location permission permanently denied.'
            : 'Location permission denied. Saved photo without GPS.',
        permanentlyDenied: locationStatus.isPermanentlyDenied,
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _GpsResult(
        latitude: position.latitude,
        longitude: position.longitude,
        status: 'GPS location captured',
      );
    } on TimeoutException {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        return _GpsResult(
          latitude: lastKnown.latitude,
          longitude: lastKnown.longitude,
          status: 'GPS timed out; used last known location',
        );
      }
      return const _GpsResult(
        status: 'GPS timed out. Saved photo without coordinates.',
      );
    } catch (_) {
      return const _GpsResult(
        status: 'Unable to read GPS location.',
      );
    }
  }

  Future<void> _clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyImagePath);
    await prefs.remove(_keyLatitude);
    await prefs.remove(_keyLongitude);
    await prefs.remove(_keyLocationStatus);
    await prefs.remove(_keySavedAt);

    if (!mounted) return;
    setState(() {
      _imagePath = null;
      _latitude = null;
      _longitude = null;
      _locationStatus = 'No GPS data yet';
      _savedAt = null;
      _showSettingsButton = false;
    });
  }

  String _formatTimestamp(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
        '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasImage = _imagePath != null && File(_imagePath!).existsSync();

    return Scaffold(
      appBar: AppBar(
        title: const Text('GeoPhoto Tag'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Photo preview container
              Container(
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade400),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasImage
                    ? Image.file(
                        File(_imagePath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_camera_outlined,
                            size: 48,
                            color: Colors.black45,
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No photo captured yet',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),

              // GPS coordinates & status container
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueGrey.shade100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _CoordItem(
                            label: 'Latitude',
                            value: _latitude != null
                                ? _latitude!.toStringAsFixed(6)
                                : '--',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _CoordItem(
                            label: 'Longitude',
                            value: _longitude != null
                                ? _longitude!.toStringAsFixed(6)
                                : '--',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _locationStatus,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                    if (_savedAt != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.schedule, size: 18),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Cached at: $_savedAt',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _captureAndTag,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt),
                      label: Text(_isLoading ? 'Processing...' : 'Take Photo'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _isLoading ? null : _clearCache,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ],
              ),

              if (_showSettingsButton) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: openAppSettings,
                  icon: const Icon(Icons.settings),
                  label: const Text('Open App Settings'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CoordItem extends StatelessWidget {
  final String label;
  final String value;

  const _CoordItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _GpsResult {
  final double? latitude;
  final double? longitude;
  final String status;
  final bool permanentlyDenied;

  const _GpsResult({
    this.latitude,
    this.longitude,
    required this.status,
    this.permanentlyDenied = false,
  });
}
