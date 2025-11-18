import 'package:flutter/material.dart';
import 'device_model.dart';
import 'device_service.dart';
import 'add_device_screen.dart';
import 'camera_screen.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final deviceService = DeviceService();

    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 248, 207, 255),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'My Devices',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<DeviceModel>>(
        stream: deviceService.getUserDevices(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final devices = snapshot.data ?? [];

          if (devices.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.devices, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No devices paired yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap + to add your first device',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: devices.length,
            itemBuilder: (context, index) {
              final device = devices[index];
              return _DeviceCard(device: device);
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddDeviceScreen(),
            ),
          );
        },
        backgroundColor: Colors.pinkAccent.shade100,
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final DeviceModel device;

  const _DeviceCard({required this.device});

  @override
  Widget build(BuildContext context) {
    final isOnline = device.status == 'online';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(
          Icons.camera_alt,
          size: 40,
          color: isOnline ? Colors.green : Colors.grey,
        ),
        title: Text(
          'Device ${device.deviceId.substring(0, 8)}...',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isOnline ? Colors.green : Colors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(isOnline ? 'Online' : 'Offline'),
              ],
            ),
            if (device.detectionEnabled)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  '🎯 Detection Active',
                  style: TextStyle(color: Colors.green, fontSize: 12),
                ),
              ),
          ],
        ),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CameraScreen(deviceId: device.deviceId),
            ),
          );
        },
      ),
    );
  }
}
