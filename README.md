# IntelliCab - Smart Cabinet Inventory Management System

A full-stack IoT system combining Flutter mobile app, Raspberry Pi edge computing, and GPU-accelerated AI object detection for automatic inventory tracking.

## 📚 Documentation

- **[User Manual](USER_MANUAL.md)** - Complete guide for end users
- **[Installation Guide](INSTALLATION.md)** - Technical setup instructions for developers/admins
- **[Auto-Matching System](AUTO_MATCHING_SYSTEM.md)** - How AI detection matches inventory items
- **[Brand Keywords](backend/cloud_server/BRAND_KEYWORDS.md)** - Brand extraction algorithm reference

---

## 🎯 Key Features

- **AI-Powered Object Detection** - YOLO-based automatic inventory tracking
- **GPU Acceleration** - 200+ FPS on NVIDIA RTX 3050 (50-80x faster than CPU)
- **Zero Manual Entry** - Camera detects items going IN/OUT automatically
- **Multi-Device Support** - Unlimited smart cabinets per user
- **Smart Notifications** - Low stock alerts and expiry warnings
- **Real-Time Sync** - Firebase Firestore for instant updates across devices
- **Barcode Scanning** - Quick item registration with ML Kit
- **Auto Grocery Lists** - Automatically adds low-stock items to shopping list

---

## 🏗️ System Architecture

```
┌─────────────────────────────────────┐
│   Flutter Mobile App (Android/iOS)  │
│   - User interface & controls       │
│   - Firebase Auth & Firestore       │
└─────────────────────────────────────┘
              ↕ Firebase
┌─────────────────────────────────────┐
│   Raspberry Pi (Edge Device)        │
│   - Camera capture & streaming      │
│   - Device management               │
└─────────────────────────────────────┘
              ↕ TCP Streaming
┌─────────────────────────────────────┐
│   Cloud Detection Server            │
│   - YOLO object detection (GPU)     │
│   - Object tracking & events        │
└─────────────────────────────────────┘
```

---

## 🚀 Quick Start

### For End Users
See **[User Manual](USER_MANUAL.md)** for:
- Account setup
- Device pairing
- Adding inventory items
- Using automatic detection

### For Developers/Admins
See **[Installation Guide](INSTALLATION.md)** for:
- Firebase setup
- Cloud server deployment
- Raspberry Pi configuration
- Mobile app building

---

## 🛠️ Tech Stack

**Frontend:**
- Flutter/Dart
- Firebase (Auth, Firestore, Storage)
- Cloudinary (Image CDN)
- Mobile Scanner + ML Kit

**Backend:**
- Python (Raspberry Pi & Cloud Server)
- PyTorch + CUDA
- YOLOv8 (Ultralytics)
- OpenCV
- Picamera2

**Database:**
- Firebase Firestore (NoSQL)
- Real-time listeners

---

## 📊 Performance Metrics

| Metric | Value |
|--------|-------|
| **Detection Speed** | 200-250 FPS (GPU) |
| **Detection Latency** | <10ms |
| **Accuracy** | 95%+ |
| **Supported Devices** | Unlimited per user |
| **Real-time Sync** | <1s Firebase |

---

## 📖 Additional Resources

- **[Flutter Documentation](https://docs.flutter.dev/)** - Flutter framework guide
- **[Firebase Console](https://console.firebase.google.com/)** - Manage your Firebase project
- **[YOLOv8 Documentation](https://docs.ultralytics.com/)** - YOLO model training & usage
- **[Raspberry Pi Documentation](https://www.raspberrypi.com/documentation/)** - Pi setup guides

---

## 🏆 Project Highlights

✅ Full-stack IoT implementation (Mobile + Edge + Cloud)  
✅ Real-time multi-device synchronization  
✅ 50-80x detection speedup with GPU acceleration  
✅ Zero-configuration inventory tracking  
✅ Production-ready with comprehensive error handling  
✅ Well-documented codebase  

---

## 📝 License

This project is developed as part of a final year project.

---

## 👥 Contributors

- **Developer**: Nabil, Arissa, Hakim, Haziq
- **Institution**: German-Malaysian Institute
- **Year**: 2025

---

## 📧 Support

For technical issues, refer to:
- [User Manual - Troubleshooting Section](USER_MANUAL.md#troubleshooting)
- [Installation Guide - Troubleshooting](INSTALLATION.md#troubleshooting)

---

**Built with ❤️ using Flutter, Python, and AI**
