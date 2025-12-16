# IntelliCab Technical Installation Guide

## Table of Contents
1. [System Architecture](#system-architecture)
2. [Prerequisites](#prerequisites)
3. [Firebase Setup](#firebase-setup)
4. [Cloud Detection Server Setup](#cloud-detection-server-setup)
5. [Raspberry Pi Setup](#raspberry-pi-setup)
6. [Mobile App Setup](#mobile-app-setup)
7. [Network Configuration](#network-configuration)
8. [Testing & Verification](#testing--verification)
9. [Deployment Checklist](#deployment-checklist)
10. [Troubleshooting](#troubleshooting)

---

## System Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   Mobile App    │◄───────►│    Firebase     │
│   (Flutter)     │         │  (Firestore +   │
└─────────────────┘         │   Storage +     │
                            │   Auth)         │
                            └─────────────────┘
                                    ▲
                                    │
                            ┌───────┴────────┐
                            │                │
                    ┌───────▼──────┐  ┌──────▼──────┐
                    │ Cloud Server │  │ Raspberry Pi│
                    │  (YOLO GPU)  │◄─┤  + Camera   │
                    └──────────────┘  └─────────────┘
                         Port 8485      TCP Stream
```

**Component Roles:**
- **Firebase**: Central data store, authentication, real-time sync
- **Cloud Server**: GPU-accelerated YOLO detection, direction tracking
- **Raspberry Pi**: Camera control, frame capture, TCP streaming
- **Mobile App**: User interface, inventory management, notifications

---

## Prerequisites

### Hardware Requirements

**Cloud Detection Server:**
- Computer with NVIDIA GPU (GTX 1060 or better recommended)
- Alternative: CPU-only mode (slower, ~10-20 FPS vs 200+ FPS)
- 8GB+ RAM
- Ubuntu 20.04+ / Windows 10+ / macOS
- 10GB free disk space

**Raspberry Pi Setup:**
- Raspberry Pi 3B+ or newer (Pi 4 recommended)
- Raspberry Pi Camera Module v2 or compatible USB webcam
- MicroSD card (16GB minimum, 32GB recommended)
- Power supply (5V 3A for Pi 4)
- Internet connectivity (WiFi or Ethernet)

**Mobile Device:**
- Android 6.0+ or iOS 12.0+
- 100MB free space
- Internet connectivity

### Software Requirements

**Cloud Server:**
- Python 3.8+
- pip package manager
- CUDA 11.8+ and cuDNN (for GPU acceleration)
- Git

**Raspberry Pi:**
- Raspberry Pi OS (64-bit recommended)
- Python 3.8+
- libcamera tools
- Git

**Development Machine (for mobile app):**
- Flutter SDK 3.0+
- Android Studio / Xcode
- Git

---

## Firebase Setup

### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Click **"Add project"** or **"Create a project"**
3. Enter project name: `intellicab-project` (or your preferred name)
4. Disable Google Analytics (optional)
5. Click **"Create project"**

### 2. Enable Firestore Database

1. In Firebase Console, go to **Firestore Database**
2. Click **"Create database"**
3. Choose **"Start in production mode"** (we'll configure rules later)
4. Select Firestore location (choose closest to your users)
5. Click **"Enable"**

### 3. Configure Firestore Security Rules

1. Go to **Firestore Database** → **Rules**
2. Replace with:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // User must be authenticated
    match /{document=**} {
      allow read, write: if request.auth != null;
    }
    
    // Users collection
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
    
    // Devices collection
    match /devices/{deviceId} {
      allow read, write: if request.auth != null;
      
      // Device detections subcollection
      match /detections/{detectionId} {
        allow read, write: if request.auth != null;
      }
    }
    
    // Inventory collection
    match /inventory/{inventoryId} {
      allow read, write: if request.auth != null;
    }
  }
}
```

3. Click **"Publish"**

### 4. Enable Firebase Authentication

1. Go to **Authentication** → **Get started**
2. Click **"Sign-in method"** tab
3. Enable **Email/Password** provider:
   - Click on "Email/Password"
   - Toggle "Enable"
   - Click "Save"

### 5. Enable Firebase Storage

1. Go to **Storage** → **Get started**
2. Click **"Start in production mode"**
3. Choose storage location (same as Firestore)
4. Click **"Done"**

### 6. Configure Storage Security Rules

1. Go to **Storage** → **Rules**
2. Replace with:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

3. Click **"Publish"**

### 7. Generate Service Account Credentials

**For Cloud Server & Raspberry Pi:**

1. Go to **Project Settings** (gear icon) → **Service accounts**
2. Click **"Generate new private key"**
3. Click **"Generate key"** (downloads JSON file)
4. Rename file to `firebase-credentials.json`
5. **CRITICAL SECURITY**: This file contains sensitive credentials
   - ⚠️ **NEVER commit to Git**
   - ⚠️ **Already included in .gitignore**
   - ⚠️ Keep secure and private

**Setup credentials:**

**Cloud Server:**
```bash
# Copy your downloaded credentials file
cp ~/Downloads/your-firebase-key.json backend/cloud_server/firebase-credentials.json

# Or use the template as a guide
cp backend/cloud_server/firebase-credentials.json.template backend/cloud_server/firebase-credentials.json
# Then edit with your actual credentials
```

**Raspberry Pi:**
```bash
# Copy your downloaded credentials file
cp ~/Downloads/your-firebase-key.json backend/pi/firebase-credentials.json

# Or use the template as a guide
cp backend/pi/firebase-credentials.json.template backend/pi/firebase-credentials.json
# Then edit with your actual credentials
```

**Template files are provided at:**
- `backend/cloud_server/firebase-credentials.json.template`
- `backend/pi/firebase-credentials.json.template`

### 8. Get Firebase Config for Mobile App

1. In **Project Settings** → **General**
2. Scroll to **"Your apps"** section
3. Click **Android icon** (or iOS):
   - Package name: `com.intellicab.app` (or your package)
   - Download `google-services.json` (Android) or `GoogleService-Info.plist` (iOS)
4. Place files in Flutter project:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

---

## Cloud Detection Server Setup

### 1. Install System Dependencies

**Ubuntu/Debian:**
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Python and development tools
sudo apt install -y python3 python3-pip python3-dev git

# Install CUDA (for GPU acceleration) - Optional but recommended
# Follow NVIDIA CUDA installation guide for your system
# https://developer.nvidia.com/cuda-downloads

# Install system libraries
sudo apt install -y libgl1-mesa-glx libglib2.0-0
```

**Windows:**
- Install Python 3.8+ from [python.org](https://www.python.org/)
- Install CUDA Toolkit from [NVIDIA](https://developer.nvidia.com/cuda-downloads)
- Install Git from [git-scm.com](https://git-scm.com/)

**macOS:**
```bash
# Install Homebrew if not installed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install Python and Git
brew install python git
```

### 2. Clone Repository

```bash
cd ~
git clone <your-repository-url> intellicab
cd intellicab/backend/cloud_server
```

### 3. Create Virtual Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
# Linux/Mac:
source venv/bin/activate
# Windows:
.\venv\Scripts\activate
```

### 4. Install Python Dependencies

```bash
pip install --upgrade pip

# Install requirements
pip install -r requirements.txt

# Verify installations
pip list | grep -E "ultralytics|opencv|firebase|torch"
```

**Expected packages:**
- `ultralytics` (YOLO)
- `opencv-python`
- `firebase-admin`
- `torch` (PyTorch)
- `numpy`

### 5. Download YOLO Model

```bash
# Model should be in the cloud_server directory
# If you have a custom model:
# Place your-model.pt in backend/cloud_server/

# Default model file: my_model.pt
# Verify it exists:
ls -lh my_model.pt
```

### 6. Configure Firebase Credentials

```bash
# Place firebase-credentials.json in cloud_server directory
ls firebase-credentials.json

# Test Firebase connection
python3 -c "
import firebase_admin
from firebase_admin import credentials, firestore

cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()
print('✅ Firebase connected successfully!')
"
```

### 7. Find Your Server IP Address

**Linux/Mac:**
```bash
# Find IP address
ifconfig | grep "inet "
# Or:
ip addr show | grep "inet "
```

**Windows (PowerShell):**
```powershell
# Find IP address
ipconfig | Select-String "IPv4"
```

Look for your local IP (usually `192.168.x.x` or `10.x.x.x`)

### 8. Start Detection Server

```bash
# Start server with default settings (port 8485)
python3 cloud_detection_server.py --firebase-creds firebase-credentials.json

# Or specify custom port:
python3 cloud_detection_server.py --firebase-creds firebase-credentials.json --port 5000

# With verbose logging:
python3 cloud_detection_server.py --firebase-creds firebase-credentials.json --verbose
```

**Expected output:**
```
🔥 Firebase initialized
🚀 YOLO model loaded: my_model.pt
🖥️  GPU detected: CUDA
📡 Server listening on 0.0.0.0:8485
⏳ Waiting for Raspberry Pi connections...
```

### 9. Configure Server as System Service (Optional)

**Linux systemd service:**

Create `/etc/systemd/system/intellicab-server.service`:

```ini
[Unit]
Description=IntelliCab Detection Server
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/home/your-username/intellicab/backend/cloud_server
Environment="PATH=/home/your-username/intellicab/backend/cloud_server/venv/bin"
ExecStart=/home/your-username/intellicab/backend/cloud_server/venv/bin/python3 cloud_detection_server.py --firebase-creds firebase-credentials.json
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable intellicab-server
sudo systemctl start intellicab-server
sudo systemctl status intellicab-server
```

---

## Raspberry Pi Setup

### 1. Install Raspberry Pi OS

1. Download [Raspberry Pi Imager](https://www.raspberrypi.com/software/)
2. Insert microSD card into computer
3. Open Raspberry Pi Imager
4. Choose OS: **"Raspberry Pi OS (64-bit)"** recommended
5. Choose Storage: Your microSD card
6. Click ⚙️ (Settings) and configure:
   - ✅ Enable SSH
   - Set username and password
   - Configure WiFi (SSID and password)
   - Set locale settings
7. Click **"Write"** and wait for completion
8. Insert SD card into Raspberry Pi and power on

### 2. Connect to Raspberry Pi

**Find Pi IP address:**
```bash
# From your computer, scan network:
# Linux/Mac:
arp -a | grep -i "b8:27:eb\|dc:a6:32"
# Or check your router's connected devices

# Or connect monitor/keyboard to Pi and run:
hostname -I
```

**SSH into Pi:**
```bash
ssh pi@<raspberry-pi-ip>
# Enter password you set during imaging
```

### 3. Update System

```bash
# Update package lists
sudo apt update

# Upgrade packages
sudo apt upgrade -y

# Install essential tools
sudo apt install -y git python3-pip python3-venv
```

### 4. Install Camera Support

**For Raspberry Pi Camera Module:**
```bash
# Enable camera interface
sudo raspi-config
# Navigate to: Interface Options → Camera → Enable

# Test camera
libcamera-hello
# Should show camera preview for 5 seconds

# Capture test image
libcamera-still -o test.jpg

# View test image info
ls -lh test.jpg
```

**For USB Camera:**
```bash
# Install v4l-utils
sudo apt install -y v4l-utils

# List cameras
v4l2-ctl --list-devices

# Test USB camera
ffmpeg -f v4l2 -i /dev/video0 -frames 1 test.jpg
```

### 5. Clone Repository

```bash
cd ~
git clone <your-repository-url> intellicab
cd intellicab/backend/pi
```

### 6. Create Virtual Environment

```bash
# Create virtual environment
python3 -m venv venv

# Activate
source venv/bin/activate
```

### 7. Install Python Dependencies

```bash
# Upgrade pip
pip install --upgrade pip

# Install requirements
pip install -r requirements.txt

# This installs:
# - picamera2 (camera control)
# - firebase-admin (Firebase SDK)
# - opencv-python (image processing)
# - numpy
```

### 8. Configure Firebase

```bash
# Copy firebase-credentials.json to Pi
# From your computer:
scp firebase-credentials.json pi@<raspberry-pi-ip>:~/intellicab/backend/pi/

# On Pi, verify file exists:
ls -lh firebase-credentials.json

# Test Firebase connection
python3 -c "
import firebase_admin
from firebase_admin import credentials, firestore
cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
print('✅ Firebase connected!')
"
```

### 9. Get MAC Address

```bash
# Get MAC address (this will be device ID)
cat /sys/class/net/eth0/address
# Or for WiFi:
cat /sys/class/net/wlan0/address

# Example output: b8:27:eb:12:34:56
# Save this - you'll need it in the mobile app!
```

### 10. Configure Backend Script

Edit `smart_cabinet_pi_backend.py`:

```bash
nano smart_cabinet_pi_backend.py
```

Update line ~33 with your Firebase Storage bucket:
```python
storageBucket='your-project-id.appspot.com'
```

Save: `Ctrl+O`, `Enter`, `Ctrl+X`

### 11. Test Backend

```bash
# Run backend
python3 smart_cabinet_pi_backend.py --firebase-creds firebase-credentials.json --device-name "test_device"

# Expected output:
# 🔥 Firebase initialized
# 📷 Camera initialized
# 📡 Device registered: b8:27:eb:12:34:56
# ✅ Backend running...
```

Press `Ctrl+C` to stop.

### 12. Configure as System Service

Create `/etc/systemd/system/intellicab-pi.service`:

```bash
sudo nano /etc/systemd/system/intellicab-pi.service
```

Content:
```ini
[Unit]
Description=IntelliCab Pi Backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/intellicab/backend/pi
Environment="PATH=/home/pi/intellicab/backend/pi/venv/bin"
ExecStart=/home/pi/intellicab/backend/pi/venv/bin/python3 smart_cabinet_pi_backend.py --firebase-creds firebase-credentials.json --device-name kitchen_cabinet
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable intellicab-pi
sudo systemctl start intellicab-pi
sudo systemctl status intellicab-pi

# View logs:
sudo journalctl -u intellicab-pi -f
```

### 13. Mount Camera

**Physical Installation:**
1. Position camera above cabinet entrance
2. Ensure clear view of entire entrance area
3. Camera should point downward (~45° angle)
4. Cable length: keep Pi within 15cm for ribbon cable
5. Secure with mounting bracket or 3M tape
6. Add LED lighting if needed (improves detection)

**Cable management:**
- Ribbon cable: Handle carefully, don't bend sharply
- USB cable: Can use extension up to 3 meters
- Power cable: Route separately from data cables

---

## Mobile App Setup

### 1. Install Flutter

**Follow official guide:** https://docs.flutter.dev/get-started/install

**Verify installation:**
```bash
flutter doctor -v
```

Fix any issues reported by `flutter doctor`.

### 2. Clone Repository

```bash
# If not already cloned:
cd ~
git clone <your-repository-url> intellicab
cd intellicab
```

### 3. Install Dependencies

```bash
# Get Flutter packages
flutter pub get

# Verify no issues
flutter pub outdated
```

### 4. Configure Firebase

**Android:**
1. Place `google-services.json` in `android/app/`
2. Verify `android/app/build.gradle` has:
   ```gradle
   apply plugin: 'com.google.gms.google-services'
   ```

**iOS:**
1. Place `GoogleService-Info.plist` in `ios/Runner/`
2. Open `ios/Runner.xcworkspace` in Xcode
3. Add `GoogleService-Info.plist` to project (drag & drop)
4. Verify it's in the Runner target

### 5. Update App Package Name (Optional)

**Android** (`android/app/build.gradle`):
```gradle
applicationId "com.yourdomain.intellicab"
```

**iOS** (`ios/Runner/Info.plist`):
```xml
<key>CFBundleIdentifier</key>
<string>com.yourdomain.intellicab</string>
```

### 6. Build for Android

```bash
# Debug build
flutter build apk --debug

# Release build (for production)
flutter build apk --release

# App Bundle (for Google Play)
flutter build appbundle --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### 7. Build for iOS

```bash
# Requires macOS and Xcode

# Open iOS project
open ios/Runner.xcworkspace

# In Xcode:
# 1. Select Runner > Signing & Capabilities
# 2. Choose your Team
# 3. Adjust Bundle Identifier if needed

# Build from command line
flutter build ios --release

# Or build in Xcode (Product > Archive)
```

### 8. Install on Device

**Android (via ADB):**
```bash
# Connect phone via USB with USB debugging enabled
adb devices

# Install APK
adb install build/app/outputs/flutter-apk/app-release.apk
```

**Android (via file transfer):**
1. Copy APK to phone
2. Open file manager
3. Tap APK and install
4. Enable "Install from unknown sources" if prompted

**iOS:**
- Requires Apple Developer account ($99/year)
- Use Xcode to install on device
- Or distribute via TestFlight

### 9. Run in Development Mode

```bash
# Connect device via USB
flutter devices

# Run app
flutter run

# Run with specific device
flutter run -d <device-id>

# Hot reload during development
# Press 'r' in terminal
```

---

## Network Configuration

### 1. Same Network Requirement

**All devices must be on the same local network:**
- ✅ Cloud Server: `192.168.1.100`
- ✅ Raspberry Pi: `192.168.1.101`
- ✅ Mobile Phone: `192.168.1.102`
- ❌ Mobile on cellular data: Won't work (unless using VPN/port forwarding)

### 2. Port Forwarding (Optional)

**For remote access outside local network:**

1. Access your router admin panel (usually `192.168.1.1`)
2. Find "Port Forwarding" or "Virtual Server" settings
3. Add rule:
   - **External Port**: 8485
   - **Internal IP**: Cloud server IP (e.g., `192.168.1.100`)
   - **Internal Port**: 8485
   - **Protocol**: TCP
4. Note your public IP: Visit https://whatismyipaddress.com/
5. Use public IP in mobile app (format: `203.0.113.5:8485`)

**Security considerations:**
- Change default port
- Use strong passwords
- Enable firewall rules
- Consider VPN instead

### 3. Firewall Configuration

**Cloud Server (Linux):**
```bash
# Allow port 8485
sudo ufw allow 8485/tcp

# Enable firewall
sudo ufw enable

# Check status
sudo ufw status
```

**Cloud Server (Windows):**
1. Open Windows Defender Firewall
2. Advanced Settings → Inbound Rules
3. New Rule → Port → TCP → 8485
4. Allow connection → Done

**Raspberry Pi:**
```bash
# Usually no firewall by default
# If needed:
sudo ufw allow 8485/tcp
```

### 4. Static IP Assignment (Recommended)

**Configure router DHCP reservation:**
1. Access router admin panel
2. Find DHCP settings
3. Add reservations:
   - Cloud Server: Assign fixed IP based on MAC address
   - Raspberry Pi: Assign fixed IP based on MAC address
4. This prevents IP changes after reboot

**Or configure static IP on device:**

**Raspberry Pi:**
```bash
sudo nano /etc/dhcpcd.conf
```

Add:
```
interface wlan0
static ip_address=192.168.1.101/24
static routers=192.168.1.1
static domain_name_servers=192.168.1.1 8.8.8.8
```

Reboot:
```bash
sudo reboot
```

---

## Testing & Verification

### 1. Test Firebase Connectivity

**From Cloud Server:**
```bash
cd backend/cloud_server
source venv/bin/activate
python3 -c "
from firebase_admin import credentials, firestore
import firebase_admin

cred = credentials.Certificate('firebase-credentials.json')
firebase_admin.initialize_app(cred)
db = firestore.client()

# Test write
doc_ref = db.collection('test').document('connectivity')
doc_ref.set({'status': 'connected', 'timestamp': firestore.SERVER_TIMESTAMP})

# Test read
doc = doc_ref.get()
print(f'✅ Firebase test: {doc.to_dict()}')
"
```

**From Raspberry Pi:**
```bash
cd backend/pi
source venv/bin/activate
# Run same test as above
```

### 2. Test Camera on Pi

```bash
# Capture image
libcamera-still -o /tmp/test.jpg

# Verify file created
ls -lh /tmp/test.jpg

# View image (if connected to monitor)
feh /tmp/test.jpg

# Or transfer to computer to view
scp pi@<pi-ip>:/tmp/test.jpg ./
```

### 3. Test Pi-to-Cloud Connection

**Start Cloud Server:**
```bash
cd backend/cloud_server
source venv/bin/activate
python3 cloud_detection_server.py --firebase-creds firebase-credentials.json
```

**On Raspberry Pi, test TCP connection:**
```bash
# Test with telnet
telnet <cloud-server-ip> 8485

# If successful, you'll see:
# Connected to <cloud-server-ip>
# Press Ctrl+] then type 'quit' to exit
```

**Start Pi backend:**
```bash
cd backend/pi
source venv/bin/activate
python3 smart_cabinet_pi_backend.py --firebase-creds firebase-credentials.json --device-name test
```

**Check logs:**
- Cloud Server should show: `✅ New connection from <pi-ip>`
- Pi should show: `📡 Connected to cloud server`

### 4. Test Mobile App

**Create test account:**
1. Open app
2. Sign up with test email
3. Verify account created in Firebase Console (Authentication section)

**Add test device:**
1. Go to Devices
2. Add Device
3. Enter:
   - Name: "Test Cabinet"
   - MAC Address: (Pi MAC address)
   - Server IP: (Cloud server IP)
   - Port: 8485
4. Save

**Request calibration:**
1. Open device details
2. Tap "Calibrate"
3. Wait for camera feed
4. Draw boundary line
5. Save

**Check in Firebase Console:**
- Go to Firestore
- Check `devices/{mac-address}/`
- Verify `boundary` field has coordinates

### 5. End-to-End Detection Test

**Preparation:**
1. Ensure cloud server is running
2. Ensure Pi backend is running
3. Ensure mobile app is logged in
4. Device should show "Online" status

**Test detection:**
1. In mobile app, go to device details
2. Enable detection (toggle switch)
3. Place a known item in front of camera
4. Slowly move item across boundary line
5. Wait 2-3 seconds

**Verify results:**
1. Open "Detection History" in app
2. You should see new detection entry with:
   - Timestamp
   - Item label
   - Confidence score
   - Direction (IN or OUT)
   - Snapshot image

**Check Firestore:**
- `devices/{mac}/detections/` should have new document
- Verify all fields are populated

### 6. Performance Monitoring

**Cloud Server Performance:**
```bash
# Monitor GPU usage
nvidia-smi -l 1

# Monitor CPU/RAM
htop

# Check network connections
netstat -an | grep 8485
```

**Raspberry Pi Performance:**
```bash
# CPU/RAM usage
top

# Temperature
vcgencmd measure_temp

# Network stats
ifstat 1
```

**Expected Performance:**
- Cloud Server: 200+ FPS with GPU, 10-20 FPS with CPU
- Pi Camera: 30 FPS capture
- Detection latency: <100ms
- Firebase sync: <500ms

---

## Deployment Checklist

### Pre-Deployment

- [ ] Firebase project created and configured
- [ ] Firestore security rules deployed
- [ ] Firebase Authentication enabled
- [ ] Firebase Storage configured
- [ ] Service account credentials downloaded
- [ ] All credentials kept secure (not in Git)

### Cloud Server

- [ ] Python 3.8+ installed
- [ ] CUDA installed (for GPU)
- [ ] Dependencies installed (requirements.txt)
- [ ] YOLO model file present
- [ ] Firebase credentials configured
- [ ] Server starts without errors
- [ ] Firewall port opened
- [ ] Static IP assigned (or DHCP reservation)
- [ ] System service configured (optional)
- [ ] Tested connectivity with Pi

### Raspberry Pi

- [ ] Raspberry Pi OS installed
- [ ] Camera module connected and tested
- [ ] Python dependencies installed
- [ ] Firebase credentials configured
- [ ] Backend script configured (storage bucket)
- [ ] MAC address documented
- [ ] System service configured
- [ ] Auto-start on boot enabled
- [ ] Camera physically mounted
- [ ] Power supply stable

### Mobile App

- [ ] Firebase config files added (google-services.json, GoogleService-Info.plist)
- [ ] App builds successfully
- [ ] APK/IPA generated
- [ ] App installed on test device
- [ ] Firebase authentication works
- [ ] Can add devices
- [ ] Can view camera feed
- [ ] Can calibrate boundary
- [ ] Detection history displays
- [ ] Notifications working

### Network

- [ ] All devices on same network
- [ ] Static IPs assigned
- [ ] Firewall rules configured
- [ ] Port forwarding set up (if remote access needed)
- [ ] DNS resolution working
- [ ] Internet connectivity stable

### Testing

- [ ] Firebase read/write operations work
- [ ] Camera captures images
- [ ] Pi-to-Cloud TCP connection established
- [ ] Mobile app connects to Firebase
- [ ] End-to-end detection works
- [ ] Direction detection accurate
- [ ] Inventory updates automatically
- [ ] Notifications delivered
- [ ] Performance acceptable

---

## Troubleshooting

### Firebase Issues

**Problem: "Permission denied" errors**
```bash
# Check Firestore rules allow authenticated access
# Verify user is logged in
# Check Firebase credentials are valid

# Test authentication:
firebase auth:export users.json --project your-project-id
```

**Problem: "Service account credentials invalid"**
- Re-download credentials from Firebase Console
- Verify JSON file is not corrupted
- Check file path is correct
- Ensure service account has correct permissions

**Problem: "Quota exceeded"**
- Check Firebase Console → Usage
- Upgrade to Blaze plan if on Spark plan
- Optimize Firestore queries
- Reduce preview image update frequency

### Cloud Server Issues

**Problem: "CUDA not available"**
```bash
# Check CUDA installation
nvcc --version

# Check PyTorch CUDA support
python3 -c "import torch; print(torch.cuda.is_available())"

# Reinstall PyTorch with CUDA:
pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu118
```

**Problem: "Model file not found"**
```bash
# Verify model exists
ls -lh my_model.pt

# Check path in script (cloud_detection_server.py)
# Update model path if needed
```

**Problem: "Port already in use"**
```bash
# Find process using port
lsof -i :8485
# Or on Windows:
netstat -ano | findstr :8485

# Kill process
kill -9 <PID>
```

**Problem: Server crashes on connection**
- Check Pi is sending valid frame data
- Verify boundary coordinates in Firestore
- Check logs for stack trace
- Test with lower camera resolution

### Raspberry Pi Issues

**Problem: "Camera not detected"**
```bash
# Check camera is enabled
sudo raspi-config
# Interface Options → Camera → Enable

# Check cable connection
# Reconnect cable firmly

# Test with:
libcamera-hello

# Check kernel modules
lsmod | grep camera
```

**Problem: "Failed to connect to cloud server"**
```bash
# Verify cloud server IP is correct
ping <cloud-server-ip>

# Test port accessibility
telnet <cloud-server-ip> 8485

# Check firewall
sudo ufw status

# Verify both on same network
ip route | grep default
```

**Problem: "Firebase connection timeout"**
```bash
# Check internet connectivity
ping google.com

# Test DNS
nslookup firestore.googleapis.com

# Verify credentials
cat firebase-credentials.json | jq .project_id

# Check system time (must be accurate)
timedatectl
```

**Problem: High CPU usage / overheating**
```bash
# Check temperature
vcgencmd measure_temp

# If >70°C:
# - Add heatsinks
# - Improve ventilation
# - Reduce camera frame rate in script

# Monitor CPU
htop
```

### Mobile App Issues

**Problem: "Build failed" errors**
```bash
# Clean build
flutter clean
flutter pub get

# Update Flutter
flutter upgrade

# Check for plugin conflicts
flutter pub outdated

# Android: Clean Gradle cache
cd android
./gradlew clean
cd ..
```

**Problem: "Google Services" errors**
- Verify google-services.json is in android/app/
- Check package name matches Firebase project
- Rebuild app completely
- Check android/build.gradle has correct plugin version

**Problem: "Camera permission denied"**
- Check AndroidManifest.xml has camera permission
- On iOS, check Info.plist has camera usage description
- Request permissions at runtime

**Problem: App crashes on detection**
- Check Firebase security rules
- Verify device document exists in Firestore
- Check network connectivity
- Review app logs: `flutter logs`

### Network Issues

**Problem: "Cannot reach devices on network"**
```bash
# Verify same subnet
ip addr show
# All devices should have 192.168.x.x (same x)

# Check router configuration
# Ensure no AP isolation enabled

# Test connectivity
ping <device-ip>
```

**Problem: Connection drops frequently**
- Check WiFi signal strength
- Use Ethernet if possible (Pi 4 has Gigabit Ethernet)
- Update router firmware
- Change WiFi channel (less congestion)
- Disable WiFi power saving:
  ```bash
  sudo iwconfig wlan0 power off
  ```

### Performance Issues

**Problem: Slow detection speed**
- Verify GPU is being used on cloud server
- Reduce camera resolution on Pi
- Lower JPEG quality for network transmission
- Optimize YOLO model (use smaller variant)
- Increase detection confidence threshold

**Problem: High latency**
- Use wired connection instead of WiFi
- Reduce frame rate on Pi
- Place cloud server closer to Pi
- Check for network congestion
- Monitor bandwidth usage

**Problem: Firebase writes are slow**
- Reduce preview image update frequency
- Lower JPEG quality for preview
- Batch writes when possible
- Check Firebase region (use closest)
- Upgrade Firebase plan

---

## Security Best Practices

### 1. Credentials Management

```bash
# NEVER commit credentials to Git
echo "firebase-credentials.json" >> .gitignore
echo "google-services.json" >> .gitignore
echo "GoogleService-Info.plist" >> .gitignore

# Use environment variables for sensitive data
export FIREBASE_CREDS_PATH="/secure/path/firebase-credentials.json"

# Set file permissions
chmod 600 firebase-credentials.json
```

### 2. Firebase Security

- Enable App Check in Firebase Console
- Use strong authentication requirements
- Implement rate limiting in Firestore rules
- Regularly review security rules
- Monitor for suspicious activity in Firebase Console

### 3. Network Security

- Change default ports
- Use VPN for remote access instead of port forwarding
- Enable SSH key authentication, disable password auth
- Keep all systems updated
- Use firewall rules to restrict access

### 4. Raspberry Pi Security

```bash
# Change default password
passwd

# Update system regularly
sudo apt update && sudo apt upgrade -y

# Enable automatic security updates
sudo apt install unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Disable unnecessary services
sudo systemctl disable bluetooth
```

---

## Maintenance

### Regular Tasks

**Weekly:**
- Check system logs for errors
- Verify all devices online
- Test end-to-end detection
- Review Firebase usage/quota

**Monthly:**
- Update system packages (Pi, Server)
- Update Python dependencies
- Clean up old detection history
- Backup Firebase data
- Check disk space usage

**Quarterly:**
- Review and update security rules
- Update YOLO model if available
- Performance optimization review
- User feedback and feature planning

### Backup Strategy

**Firebase Backup:**
```bash
# Export Firestore data
firebase firestore:export gs://your-bucket/backups/$(date +%Y%m%d)

# Automate with cron:
0 2 * * 0 firebase firestore:export gs://your-bucket/backups/$(date +%Y%m%d)
```

**Code Backup:**
- Use Git for version control
- Push to remote repository regularly
- Tag releases: `git tag -a v1.0.0 -m "Release 1.0.0"`

---

## Support & Resources

### Documentation
- [Firebase Documentation](https://firebase.google.com/docs)
- [Flutter Documentation](https://docs.flutter.dev/)
- [Ultralytics YOLO](https://docs.ultralytics.com/)
- [Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)

### Community
- [Stack Overflow](https://stackoverflow.com/) - Technical questions
- [GitHub Issues](https://github.com/) - Bug reports
- [Reddit r/Firebase](https://www.reddit.com/r/Firebase/) - Firebase help
- [Reddit r/raspberry_pi](https://www.reddit.com/r/raspberry_pi/) - Pi help

### Tools
- [Firebase Console](https://console.firebase.google.com/)
- [Flutter DevTools](https://docs.flutter.dev/development/tools/devtools)
- [Postman](https://www.postman.com/) - API testing
- [Wireshark](https://www.wireshark.org/) - Network debugging

---

**Document Version**: 1.0  
**Last Updated**: December 2024  
**For**: IntelliCab System Administrators & Developers

---

*For end-user documentation, see [USER_MANUAL.md](USER_MANUAL.md)*
