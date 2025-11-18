# Cloud Detection Server

## Overview
This server runs on your laptop/computer to receive video frames from the Raspberry Pi, perform YOLO object detection, and log detection events to Firebase.

## Setup

### 1. Install Dependencies

```bash
pip install -r requirements.txt
```

### 2. Download YOLO Model

Place your YOLO model files in the appropriate directory (update path in `cloud_detection_server.py`).

### 3. Firebase Configuration

1. Download your Firebase service account credentials JSON file
2. Place it as `firebase-credentials.json` in this directory

### 4. Find Your IP Address

**Windows:**
```cmd
ipconfig
```
Look for "IPv4 Address" (usually 192.168.x.x)

**Mac/Linux:**
```bash
ifconfig
```
Look for "inet" under your active network interface

### 5. Run the Server

```bash
python cloud_detection_server.py --firebase-creds firebase-credentials.json
```

The server will start listening on port 8485 by default.

## How It Works

### 1. TCP Socket Server
- Listens on port 8485 for connections from Raspberry Pi
- Receives video frames via TCP
- Each frame is prefixed with 8-byte length header

### 2. Object Detection
- Uses YOLO model to detect objects in frames
- Tracks objects as they move across the boundary line
- Direction detection: "in" or "out"

### 3. Boundary Line Logic
- Reads boundary coordinates from Firestore device document
- Tracks when objects cross the line
- Prevents duplicate detections with cooldown period

### 4. Firebase Integration
- Logs detection events to `devices/{deviceId}/detections/` subcollection
- Includes:
  - Timestamp
  - Item name (from YOLO)
  - Confidence score
  - Direction (in/out)
  - Snapshot image (base64)

## Configuration in Flutter App

1. Open your device in the app
2. Tap "Configure Server"
3. Enter your laptop's IP address
4. Port defaults to 8485 (change if needed)
5. Save configuration

## Detection Event Structure

```
devices/{deviceId}/detections/{detectionId}/
  ├─ timestamp: timestamp
  ├─ item_name: string
  ├─ confidence: number (0-1)
  ├─ direction: 'in' | 'out'
  ├─ image_base64: string
  └─ deviceId: string
```

## Troubleshooting

### Connection Issues
- Ensure Pi and laptop are on the same network
- Check firewall settings (allow port 8485)
- Verify IP address is correct
- Test with: `telnet <your-ip> 8485`

### Detection Issues
- Verify boundary line is set in app
- Check YOLO model is loaded correctly
- Review detection logs in console
- Adjust confidence threshold if needed

### Performance Issues
- Lower frame rate from Pi if CPU usage is high
- Use GPU acceleration if available
- Reduce YOLO model size for faster inference

## Architecture

```
Raspberry Pi  →  (TCP Socket)  →  Cloud Server  →  (Firebase)  →  Flutter App
   Camera            Port 8485        YOLO Detection    Firestore      Display
```

## Notes

- Server must be running before enabling detection on Pi
- All devices on same network can connect
- Detection events are stored permanently in Firestore
- Review detection history in the Flutter app
