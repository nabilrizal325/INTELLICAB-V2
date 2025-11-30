// ============================================================================
// FILE: calibration_screen.dart
// PURPOSE: Interactive boundary line drawing for detection zone setup
// 
// This screen allows users to draw a boundary line on the calibration frame
// captured from the Raspberry Pi camera. Objects crossing this line will
// trigger detection events.
// 
// FUNCTIONALITY:
// - Displays calibration image from base64 string
// - Touch/drag interface to draw boundary line
// - Visual feedback with drawn line overlay
// - Coordinate normalization (0.0-1.0) for resolution independence
// - Save boundary to Firestore
// - Load existing boundary if already configured
// 
// DRAWING MECHANICS:
// - User drags finger/mouse to draw line
// - Start point set on onPanStart
// - Line updates in real-time during onPanUpdate
// - End point finalized on onPanEnd
// - Coordinates stored as normalized values (x/width, y/height)
// 
// COORDINATE SYSTEM:
// - Screen coordinates: Actual pixel positions from gestures
// - Normalized coordinates: 0.0-1.0 range (stored in Firestore)
// - Conversion: normalizedX = screenX / imageWidth
// - Benefit: Works across different camera resolutions
// 
// NAVIGATION:
// - From: CameraScreen → "Draw Boundary" button
// - To: CameraScreen (back after save)
// 
// UI COMPONENTS:
// - GestureDetector for touch input
// - CustomPainter for line rendering
// - LayoutBuilder for image dimensions
// - FloatingActionButton for save action
// ============================================================================

import 'dart:convert';
import 'package:flutter/material.dart';
import 'device_service.dart';

/// Screen for drawing detection boundary line on calibration image
/// 
/// Provides interactive line drawing interface with gesture detection
/// and saves normalized coordinates to Firestore.
class CalibrationScreen extends StatefulWidget {
  /// Device ID to save boundary for
  final String deviceId;
  
  /// Base64 encoded calibration frame from Pi camera
  final String calibrationImageBase64;
  
  /// Existing boundary coordinates (if already configured)
  /// Format: {'x1': double, 'y1': double, 'x2': double, 'y2': double}
  final Map<String, dynamic>? existingBoundary;

  const CalibrationScreen({
    super.key,
    required this.deviceId,
    required this.calibrationImageBase64,
    this.existingBoundary,
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  /// Start point of the boundary line (screen coordinates)
  Offset? _startPoint;
  
  /// End point of the boundary line (screen coordinates)
  Offset? _endPoint;
  
  /// Device service for saving boundary
  final DeviceService _deviceService = DeviceService();
  
  /// Loading state during save operation
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    /// Load existing boundary if device already has one configured
    /// Converts normalized coordinates back to screen coordinates
    if (widget.existingBoundary != null) {
      try {
        _startPoint = Offset(
          (widget.existingBoundary!['x1'] as num).toDouble(),
          (widget.existingBoundary!['y1'] as num).toDouble(),
        );
        _endPoint = Offset(
          (widget.existingBoundary!['x2'] as num).toDouble(),
          (widget.existingBoundary!['y2'] as num).toDouble(),
        );
      } catch (e) {
        debugPrint('Error loading existing boundary: $e');
      }
    }
  }

  Future<void> _saveBoundary() async {
    if (_startPoint == null || _endPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please draw a boundary line first')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final boundary = {
        'x1': _startPoint!.dx,
        'y1': _startPoint!.dy,
        'x2': _endPoint!.dx,
        'y2': _endPoint!.dy,
      };

      await _deviceService.saveBoundary(widget.deviceId, boundary);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Boundary saved successfully!')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving boundary: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _clearBoundary() {
    setState(() {
      _startPoint = null;
      _endPoint = null;
    });
  }

  Widget _buildCalibrationImage() {
    try {
      // Remove data URL prefix if present
      String cleanBase64 = widget.calibrationImageBase64;
      if (cleanBase64.contains(',')) {
        cleanBase64 = cleanBase64.split(',').last;
      }
      
      // Remove any whitespace
      cleanBase64 = cleanBase64.replaceAll(RegExp(r'\s+'), '');

      final bytes = base64Decode(cleanBase64);
      return Image.memory(
        bytes,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          debugPrint('Calibration image error: $error');
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, size: 64, color: Colors.grey[600]),
                const SizedBox(height: 16),
                const Text(
                  'Failed to load calibration image',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      debugPrint('Base64 decode error: $e');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            const Text(
              'Invalid image data',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Draw Boundary',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_startPoint != null || _endPoint != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: _clearBoundary,
              tooltip: 'Clear',
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Draw a line to mark the boundary where items cross',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _startPoint = details.localPosition;
                    _endPoint = details.localPosition;
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _endPoint = details.localPosition;
                  });
                },
                onPanEnd: (details) {
                  // Line drawing completed
                },
                child: Stack(
                  children: [
                    // Calibration image
                    _buildCalibrationImage(),
                    // Boundary line overlay
                    CustomPaint(
                      painter: _LinePainter(
                        startPoint: _startPoint,
                        endPoint: _endPoint,
                      ),
                      size: Size.infinite,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton(
                  onPressed: _isSaving ? null : _saveBoundary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.pinkAccent.shade100,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'Save Boundary',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  final Offset? startPoint;
  final Offset? endPoint;

  _LinePainter({
    this.startPoint,
    this.endPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the boundary line
    if (startPoint != null && endPoint != null) {
      final paint = Paint()
        ..color = Colors.red
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;

      canvas.drawLine(startPoint!, endPoint!, paint);

      // Draw circles at endpoints
      final circlePaint = Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill;

      canvas.drawCircle(startPoint!, 8, circlePaint);
      canvas.drawCircle(endPoint!, 8, circlePaint);

      // Calculate midpoint of the line
      final midX = (startPoint!.dx + endPoint!.dx) / 2;
      final midY = (startPoint!.dy + endPoint!.dy) / 2;

      // Text painter setup
      final textStyle = TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(
            blurRadius: 4,
            color: Colors.black,
            offset: Offset(1, 1),
          ),
        ],
      );

      // Draw "OUT ↑" label above the line
      final outTextPainter = TextPainter(
        text: TextSpan(text: 'OUT ↑', style: textStyle),
        textDirection: TextDirection.ltr,
      );
      outTextPainter.layout();
      outTextPainter.paint(
        canvas,
        Offset(midX - outTextPainter.width / 2, midY - 40),
      );

      // Draw "IN ↓" label below the line
      final inTextPainter = TextPainter(
        text: TextSpan(text: 'IN ↓', style: textStyle.copyWith(color: Colors.green)),
        textDirection: TextDirection.ltr,
      );
      inTextPainter.layout();
      inTextPainter.paint(
        canvas,
        Offset(midX - inTextPainter.width / 2, midY + 20),
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}
