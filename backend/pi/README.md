# Raspberry Pi Backend

## Overview
This backend runs on your Raspberry Pi to control the camera, capture frames, and communicate with the cloud detection server and Flutter app via Firebase.

## Setup

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Firebase Configuration

1. Download your Firebase service account credentials JSON file from Firebase Console
2. Place it as `firebase-credentials.json` in this directory
3. Update the `storageBucket` in `smart_cabinet_pi_backend.py` (line 33) with your Firebase project ID

### 3. Run the Backend

```bash
python smart_cabinet_pi_backend.py --firebase-creds firebase-credentials.json --device-name "kitchen_cabinet"
```

## How It Works

### Device Registration
- On startup, the Pi registers itself in Firestore using its MAC address as the device ID
- Initial state: `status: 'online'`, `detection_enabled: false`, `preview_enabled: false`

### Firebase Communication
The Pi listens to its device document in Firestore for commands:

1. **Preview Mode** (`preview_enabled: true`)
   - Captures frames every 1-2 seconds
   - Encodes as JPEG (quality 70)
   - Converts to base64 string
   - Writes to Firestore: `preview_image` and `preview_ts`

2. **Calibration** (`calibration_requested: true`)
   - Captures a single frame
   - Encodes as JPEG (quality 75)
   - Converts to base64
   - Writes to Firestore: `calibration_image` and `calibration_ts`
   - Clears the request flag

3. **Detection Mode** (`detection_enabled: true`)
   - Connects to cloud server via TCP socket
   - Streams video frames for object detection
   - Requires `cloud_server_ip` to be configured

### Firestore Document Structure

```
devices/{deviceId}/
  ├─ deviceId: string (MAC address)
  ├─ name: string
  ├─ status: 'online' | 'offline'
  ├─ detection_enabled: boolean
  ├─ preview_enabled: boolean
  ├─ calibration_requested: boolean
  ├─ lastSeen: timestamp
  ├─ preview_image: string (base64)
  ├─ preview_ts: timestamp
  ├─ calibration_image: string (base64)
  ├─ calibration_ts: timestamp
  ├─ boundary: {x1, y1, x2, y2}
  ├─ cloud_server_ip: string
  └─ cloud_server_port: number
```

## Configuration

All configuration is done through the Flutter app:
- ✅ No command-line arguments needed (except initial setup)
- ✅ Enable/disable preview from app
- ✅ Request calibration frames from app
- ✅ Set boundary lines from app
- ✅ Configure cloud server IP from app
- ✅ Start/stop detection from app

## Troubleshooting

### Camera Issues
```bash
# Test camera
libcamera-still -o test.jpg
```

### Firebase Connection Issues
- Verify `firebase-credentials.json` is valid
- Check internet connection
- Ensure Firebase project has Firestore enabled

### Performance Tips
- Lower JPEG quality if Firestore writes are slow
- Increase preview interval to reduce bandwidth
- Use local network for cloud server connection

## Device ID

Your device ID (MAC address) will be printed on startup:
```
📝 Device registered in Firebase
   Add this device in your app using ID: b8:27:eb:xx:xx:xx
```

Use this ID to pair the device in your Flutter app.
