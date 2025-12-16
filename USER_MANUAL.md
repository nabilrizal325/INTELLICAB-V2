# IntelliCab User Manual

## Table of Contents
1. [System Overview](#system-overview)
2. [Getting Started](#getting-started)
3. [Mobile App Setup](#mobile-app-setup)
4. [Device Management](#device-management)
5. [Boundary Calibration](#boundary-calibration)
6. [Inventory Management](#inventory-management)
7. [Understanding Automatic Detection](#understanding-automatic-detection)
8. [Notifications](#notifications)
9. [Grocery Lists](#grocery-lists)
10. [Troubleshooting](#troubleshooting)
11. [FAQ](#faq)

---

## System Overview

### What is IntelliCab?

IntelliCab is an intelligent cabinet monitoring system that automatically tracks items in your storage spaces using computer vision. The system combines:

- **Mobile App**: Your control center for managing inventory, viewing detections, and receiving notifications
- **Smart Camera Device**: Raspberry Pi with camera module mounted on your cabinet
- **Cloud Detection Server**: AI-powered object recognition running on a remote server

### How It Works

1. **Detection**: Camera continuously monitors your cabinet entrance
2. **Recognition**: AI identifies items and movement direction (IN/OUT)
3. **Tracking**: System automatically updates inventory quantities
4. **Notification**: Get alerts when items are low or need attention

### Key Features

- **Automatic Inventory Tracking**: Items detected and tracked without manual input
- **Smart Matching**: AI matches detected items to your inventory with 60%+ accuracy
- **Direction Detection**: Knows when items enter or leave the cabinet
- **Barcode Scanning**: Quick item addition using product barcodes
- **Manual Entry**: Add items that can't be scanned
- **Expiry Alerts**: Notifications for expiring products
- **Smart Grocery Lists**: Automatically adds low-stock items
- **Multiple Cabinets**: Manage different storage spaces separately
- **Detection History**: Review all detected movements with timestamps

---

## Getting Started

### System Requirements

**Hardware:**
- Android smartphone
- Raspberry Pi (3B+ or newer recommended)
- Raspberry Pi Camera Module or USB Camera
- Stable internet connection for both devices

**Software:**
- Mobile App (download from your platform)
- Cloud Server (setup by administrator)
- Pi Backend (installed on Raspberry Pi)

### Installation Overview

1. **Cloud Server Setup** (Administrator)
   - Install Python dependencies
   - Configure Firebase credentials
   - Deploy YOLO detection model
   - Start detection server

2. **Raspberry Pi Setup** (Per Cabinet)
   - Install Pi backend software
   - Connect camera module
   - Configure cloud server connection
   - Mount camera above cabinet entrance

3. **Mobile App Setup** (Each User)
   - Download and install app
   - Create account or login
   - Pair with your devices
   - Start using!

> For detailed hardware and server setup instructions, see the backend README files in the `backend/` folder.

---

## Mobile App Setup

### Creating an Account

1. Open the IntelliCab app
2. Tap **"Sign Up"** on the login screen
3. Enter your information:
   - Email address
   - Password (minimum 6 characters)
   - Confirm password
4. Tap **"Sign Up"** to create your account
5. Check your email for verification (if enabled)

### Logging In

1. Open the app
2. Enter your registered email and password
3. Tap **"Login"**
4. You'll be taken to the homepage

**You should see**: Your dashboard with device list and recent detections.

### Forgot Password

1. On the login screen, tap **"Forgot Password?"**
2. Enter your registered email address
3. Tap **"Send Reset Link"**
4. Check your email for password reset instructions
5. Follow the link to create a new password

---

## Device Management

### Adding a New Device

**Prerequisites**: Your Raspberry Pi must be set up and running with the Pi backend software.

1. Go to **"Devices"** tab from the navigation menu
2. Tap the **"+"** button or **"Add Device"**
3. Enter device information:
   - **Device Name**: Friendly name (e.g., "Kitchen Cabinet", "Pantry")
   - **MAC Address**: Your Raspberry Pi's MAC address
   - **Cloud Server IP**: IP address of your cloud detection server
   - **Cloud Server Port**: Port number (default: 5000)
4. Tap **"Add Device"**

**You should see**: Your new device appear in the devices list.

### Finding Your MAC Address

**On Raspberry Pi:**
```bash
# Run this command in terminal:
ifconfig
# Or:
ip link show
```
Look for `ether` followed by an address like `b8:27:eb:xx:xx:xx`

### Viewing Device Details

1. From the Devices screen, tap on any device
2. You'll see:
   - Device name and status
   - Connection information
   - Associated inventory items
   - Recent detections for this device
   - Calibration status

### Editing Device Settings

1. Open device details
2. Tap the **Edit** icon (pencil)
3. Modify settings as needed
4. Tap **"Save"** to apply changes

### Removing a Device

1. Open device details
2. Tap **"Delete Device"** or trash icon
3. Confirm deletion
4. Device and its detection history will be removed

**Note**: Inventory items will be moved to "Unorganized" category, not deleted.

---

## Boundary Calibration

### What is Boundary Calibration?

Calibration teaches the system where items cross into/out of your cabinet. This is crucial for accurate direction detection.

### When to Calibrate

- **First time setup**: After adding a new device
- **Camera moved**: If camera position changes
- **Inaccurate detection**: Items detected going wrong direction
- **Cabinet modifications**: If entrance area changes

### Calibration Process

1. **Access Calibration**:
   - Go to Device Details
   - Tap **"Calibrate Boundary"**
   - Or tap **"Calibration"** from main menu and select device

2. **Live Camera View Opens**:
   - You'll see real-time camera feed
   - Current boundary line shown (if exists)

3. **Draw Boundary Line**:
   - **Tap two points** on screen to create a line
   - Line should cross the cabinet entrance/exit path
   - Typically drawn at the cabinet door threshold

4. **Save Calibration**:
   - Tap **"Save Boundary"**
   - System uploads boundary data to cloud server
   - Confirmation message appears

### Best Practices

**Line Position**:
- Draw line perpendicular to movement direction
- Position at the narrowest point of entrance
- Ensure items must cross the line to enter/exit

**Camera View**:
- Entire entrance should be visible
- Good lighting (add LED strip if needed)
- Minimal background clutter
- Camera stable (no wobbling)

**Testing**:
- After calibration, test with a known item
- Move item in and out slowly
- Check detection history for correct direction
- Recalibrate if needed

### Troubleshooting Calibration

**Problem**: Can't see camera feed
- Check Raspberry Pi is running
- Verify cloud server is accessible
- Check network connection
- Review device MAC address is correct

**Problem**: Boundary line not saving
- Ensure two points are tapped clearly
- Check internet connection
- Verify Firebase permissions
- Try drawing line again

**Problem**: Wrong direction detected
- Redraw boundary line
- Ensure line crosses movement path
- Check camera isn't mounted backwards
- Verify IN/OUT zones are correct

---

## Inventory Management

### Three Ways to Add Items

IntelliCab offers multiple methods to build your inventory:

#### 1. Barcode Scanning (Fastest)

1. Tap **"+"** button on homepage or **"Add Item"**
2. Select **"Scan Barcode"**
3. Point camera at product barcode
4. System automatically fills:
   - Product name
   - Brand (if recognized)
   - Category
5. Adjust quantity and location
6. Add expiry date using calendar
7. Tap **"Add Item"**

**Supported Formats**: EAN-13, UPC-A, QR codes, and more

#### 2. Manual Entry (Most Flexible)

1. Tap **"Manual Entry"** from add options
2. Fill in details:
   - **Item Name**: Product name as it appears on packaging
   - **Brand**: Manufacturer name
   - **Category**: (Beverages, Snacks, Canned Goods, etc.)
   - **Quantity**: Current stock amount
   - **Storage Location**: Which cabinet/device
   - **Expiry Date**: Use calendar picker
   - **Barcode**: (Optional) for future scans
3. Tap **"Add to Inventory"**

**Tips for Manual Entry**:
- Use specific names (e.g., "Coca Cola 330ml Can" not just "Coke")
- Include brand names for better matching
- Be consistent with naming for similar items

#### 3. Automatic Detection (Hands-Free)

Items detected by your smart cabinet can be automatically added:

1. Ensure device is calibrated
2. Place new item in front of camera
3. Move item slowly across boundary
4. System detects and creates inventory entry
5. Review in **"Unorganized"** category
6. Assign to specific device if needed

**Note**: Automatic detection creates basic entries. Edit them to add expiry dates and adjust details.

### Viewing Inventory

**All Items**:
- Homepage shows complete inventory
- Searchable and filterable
- Grouped by location

**By Device**:
- Open Device Details
- View items specific to that cabinet
- See stock levels at a glance

**Unorganized Items**:
- Items not assigned to a device
- Review automatic detections here
- Assign to cabinets as needed

### Editing Items

1. Tap on any inventory item
2. Make changes:
   - Update quantity
   - Change location (device)
   - Adjust expiry date
   - Modify name or category
3. Tap **"Save"** or **"Update"**

### Deleting Items

1. Open item details
2. Tap **"Delete"** button
3. Confirm deletion
4. Item removed from inventory and detection history

---

## Understanding Automatic Detection

### How Detection Works

1. **Continuous Monitoring**: Camera captures video at 30 FPS
2. **Object Recognition**: AI model identifies items in frame
3. **Boundary Crossing**: System tracks when items cross calibration line
4. **Direction Analysis**: Determines if item moved IN or OUT
5. **Label Matching**: Compares detected label with your inventory
6. **Quantity Update**: Automatically adjusts stock levels

### Detection Matching

**Matching Process**:
- System extracts item label from detection (e.g., "coca_cola_can")
- Compares with inventory item names and brands
- Calculates similarity score
- **60% match threshold** required for automatic update
- Prioritizes brand matches and exact labels

**Example Matches**:
- Detected: "coca_cola_can" → Matches: "Coca Cola 330ml Can" (95%)
- Detected: "lays_chips" → Matches: "Lays Potato Chips Original" (88%)
- Detected: "mister_potato_hot_and_spicy" → Matches: "Mister Potato Hot & Spicy" (94%)

### Detection Confidence

Each detection has a confidence score:
- **90-100%**: Excellent detection, highly reliable
- **80-89%**: Good detection, generally accurate
- **70-79%**: Moderate detection, verify if important
- **Below 70%**: Low confidence, may need manual review

### Reviewing Detections

**Detection History**:
1. Go to **"Detection History"** from menu
2. View all detections chronologically
3. Filter by:
   - Device
   - Date range
   - Item name
   - Direction (IN/OUT)

**Each Detection Shows**:
- Timestamp
- Device name
- Detected label
- Confidence score
- Direction (IN/OUT)
- Matched inventory item
- Quantity change applied

### Manual Override

If automatic matching is incorrect:

1. Open Detection History
2. Find the incorrect detection
3. Tap to view details
4. Manual correction options:
   - Assign to different inventory item
   - Mark as false detection
   - Adjust quantity manually in inventory

---

## Notifications

### Types of Notifications

**Expiry Alerts**:
- Items expiring within 7 days
- Critical: Items expiring within 24 hours
- Sent daily at configured time

**Low Stock Alerts**:
- When item quantity reaches threshold (e.g., ≤2)
- Automatically adds to grocery list
- Configurable per item or globally

**Detection Alerts** (Optional):
- New items detected
- Unmatched detections need review
- Device connectivity issues

### Managing Notifications

**Enable/Disable**:
1. Go to **"Profile"** or **"Settings"**
2. Tap **"Notifications"**
3. Toggle notification types:
   - [ ] Expiry Alerts
   - [ ] Low Stock Alerts
   - [ ] Detection Alerts
   - [ ] Device Status Alerts

**Notification Settings**:
- Timing: Choose preferred alert time
- Frequency: Daily, twice daily, weekly
- Sound: Enable/disable notification sounds
- Badges: Show unread count on app icon

### Viewing Notifications

1. Tap **"Notifications"** from menu
2. See all recent alerts
3. Tap any notification to:
   - View item details
   - Update quantity
   - Add to grocery list
   - Dismiss notification

**Notification Badge**:
- Red badge on Notifications icon shows unread count
- Auto-clears when notifications are viewed

---

## Grocery Lists

### Smart Grocery List (Automatic)

Your grocery list is automatically populated based on:
- Low stock items (quantity ≤ threshold)
- Items marked as needed
- Frequently used items running out

**Viewing Smart List**:
1. Tap **"Grocery List"** from menu
2. See automatically added items
3. Each item shows:
   - Item name and brand
   - Current quantity
   - Last purchase date
   - Suggested quantity

**Using Smart List**:
- Check off items as you shop
- Mark items as purchased
- System updates inventory automatically
- Removes items from list when restocked

### Manual Grocery List Management

**Adding Items Manually**:
1. Open Grocery List
2. Tap **"+ Add Item"**
3. Enter item details
4. Tap **"Add to List"**

**Editing List Items**:
- Tap item to edit quantity or notes
- Swipe to remove from list
- Long press to mark as priority

**Clearing List**:
- After shopping, tap **"Clear Purchased"**
- Removes checked items
- Keeps unchecked items for next trip

### Shopping Mode

**Optimized Shopping View**:
1. Tap **"Shopping Mode"** button
2. Large checkboxes for easy tapping
3. Simplified layout
4. Running total (if prices entered)
5. Organized by category or store section

**Tips**:
- Group items by store layout
- Add notes for specific brands or sizes
- Use voice input for quick additions
- Share list with family members (if enabled)

---

## Troubleshooting

### App Issues

**Problem**: Can't login / "Invalid credentials"
- Verify email and password are correct
- Check internet connection
- Try password reset if forgotten
- Ensure account is verified (check email)

**Problem**: App crashes on startup
- Update to latest app version
- Clear app cache (Settings → Apps → IntelliCab → Clear Cache)
- Reinstall app if persistent
- Check device OS compatibility

**Problem**: Inventory not loading
- Check internet connection
- Pull down to refresh
- Verify Firebase connection
- Log out and log back in

### Detection Issues

**Problem**: No detections appearing
- Check Raspberry Pi is powered on
- Verify camera cable is connected
- Test camera: `raspistill -o test.jpg`
- Check cloud server is running
- Review device MAC address is correct
- Verify network connectivity

**Problem**: Wrong direction detected (IN showing as OUT)
- Recalibrate boundary line
- Ensure line crosses movement path correctly
- Check camera isn't mounted backwards
- Test with slow, deliberate movements

**Problem**: Items not matching inventory
- Detection label must match inventory name/brand
- Use consistent naming (include brand in name)
- Check match threshold (default 60%)
- Review detection label in history
- Manually edit inventory name to match detection

**Problem**: Low confidence detections
- Improve lighting (add LED strip)
- Reduce camera distance to items
- Clean camera lens
- Retrain model with your specific items
- Ensure items are clearly visible

### Device Connection Issues

**Problem**: Device shows "Offline" or "Disconnected"
- Check Raspberry Pi power and boot status
- Verify Pi is connected to internet (`ping google.com`)
- Check cloud server accessibility from Pi
- Review firewall settings (port 5000 open)
- Restart Pi backend service

**Problem**: "Can't reach cloud server"
- Verify cloud server IP and port in device settings
- Check server is running: `ps aux | grep calibration_server`
- Test server accessibility: `curl http://server_ip:5000/health`
- Review server logs for errors
- Check network firewall settings

**Problem**: Camera feed not showing in calibration
- Verify camera is detected: `vcgencmd get_camera`
- Check camera cable connection
- Test with: `raspistill -o test.jpg`
- Restart Pi camera service
- Try different camera if available

### Notification Problems

**Problem**: Not receiving notifications
- Check notification settings in app
- Verify device notification permissions (OS Settings)
- Enable "Allow Notifications" for IntelliCab
- Check internet connection
- Review notification schedule settings

**Problem**: Too many notifications
- Adjust notification frequency
- Increase low-stock threshold
- Disable detection alerts if not needed
- Set quiet hours

### Performance Issues

**Problem**: App slow or laggy
- Close unused apps
- Clear app cache
- Check available storage space
- Update to latest app version
- Restart device

**Problem**: Battery drain
- Reduce notification frequency
- Disable background refresh if not needed
- Check for app updates (may include optimizations)
- Review device battery health

---

## FAQ

### General Questions

**Q: How many devices can I connect?**
A: Unlimited. Connect as many Raspberry Pi cameras as you need for different cabinets.

**Q: Can multiple users share the same devices?**
A: Yes, if users share the same account or if sharing is configured. Currently, each account manages its own devices independently.

**Q: Does the app work offline?**
A: Limited functionality. You can view cached inventory and add items manually, but detection requires internet connectivity.

**Q: Is my data secure?**
A: Yes. Data is stored in Firebase with authentication required. Only you can access your inventory and detections.

**Q: What happens if I lose internet connection?**
A: Detections are queued on the Pi and uploaded when connection restores. App shows last synced data until online.

### Technical Questions

**Q: What AI model is used for detection?**
A: YOLOv8 (You Only Look Once) trained on grocery items, running on GPU-accelerated cloud server.

**Q: How fast is detection?**
A: Cloud server processes 200+ FPS. Pi camera captures at 30 FPS. Detection latency is typically <100ms.

**Q: Can I train the model on custom items?**
A: Yes, but requires technical knowledge. Collect labeled images, retrain YOLO model, deploy updated weights.

**Q: What camera resolution is recommended?**
A: 640x480 or higher. Higher resolution improves accuracy but increases bandwidth usage.

**Q: Does it work with USB cameras?**
A: Yes. Pi backend supports both Raspberry Pi Camera Module and USB webcams.

### Usage Questions

**Q: How do I handle items without barcodes?**
A: Use manual entry or let automatic detection create the entry, then edit details as needed.

**Q: Can I track partial quantities (e.g., 0.5kg flour)?**
A: Currently supports integer quantities. Track containers (e.g., "Flour Bag 1kg") rather than weight.

**Q: What if multiple items are detected simultaneously?**
A: Each item is detected separately with its own timestamp and quantity change.

**Q: How do I move items between cabinets?**
A: Edit the item and change "Storage Location" to the target device. Or let detection handle it automatically.

**Q: Can I export inventory data?**
A: Not currently in app. Technical users can export from Firebase console.

### Calibration Questions

**Q: How often should I recalibrate?**
A: Only when camera moves, detection direction is wrong, or cabinet layout changes.

**Q: What if my cabinet has two entrances?**
A: Use separate devices with cameras for each entrance, or position camera to see both.

**Q: Can I calibrate without items in the cabinet?**
A: Yes. Calibration sets the boundary line position, not item-specific settings.

**Q: Does lighting affect calibration?**
A: Calibration itself is not affected, but consistent lighting improves detection accuracy after calibration.

### Troubleshooting Questions

**Q: Why are some detections marked "unprocessed"?**
A: Detection confidence too low, no matching inventory item, or processing error. Review in Detection History.

**Q: Items detected but quantity not updating?**
A: Check direction detection is correct, verify item name matches detection label, ensure inventory item exists.

**Q: Detection says "Coca Cola" but I have "Pepsi"?**
A: Model may be incorrectly trained or confident. Manually correct in Detection History and update inventory.

**Q: Can I delete detection history?**
A: Not currently in app. History is preserved for auditing. Future versions may add deletion options.

---

## Support & Resources

### Documentation
- **Technical Setup**: See `backend/` folder READMEs for server and Pi setup
- **Auto-Matching Algorithm**: See `AUTO_MATCHING_SYSTEM.md` for matching details
- **Brand Keywords**: See `backend/cloud_server/BRAND_KEYWORDS.md` for supported brands

### Getting Help
- Review this manual thoroughly
- Check troubleshooting section for common issues
- Verify hardware connections and software versions
- Test with simple scenarios first

### System Requirements
- **Mobile**: Android 6.0+ / iOS 12.0+
- **Raspberry Pi**: 3B+ or newer (4 recommended for better performance)
- **Camera**: Raspberry Pi Camera Module v2 or compatible USB webcam
- **Network**: Stable WiFi with internet access
- **Cloud Server**: Ubuntu 20.04+, NVIDIA GPU recommended (CPU fallback available)

### Best Practices
1. Keep app and backend software updated
2. Regularly review and clean up inventory
3. Recalibrate after significant changes
4. Use consistent item naming
5. Monitor detection accuracy and adjust matching threshold if needed
6. Back up important inventory data periodically

---

**Document Version**: 1.0  
**Last Updated**: 2024  
**For**: IntelliCab Smart Cabinet System

---

## Quick Reference Card

### Essential Steps
1. ✅ Create account and login
2. ✅ Add device (MAC address, server IP)
3. ✅ Calibrate boundary line
4. ✅ Add initial inventory (scan/manual)
5. ✅ Test detection with known item
6. ✅ Enable notifications
7. ✅ Start using automatically!

### Common Tasks
- **Add item**: Tap **+** → Choose method → Fill details → Save
- **View detections**: Menu → **Detection History** → Filter as needed
- **Calibrate**: Device Details → **Calibrate** → Draw line → Save
- **Grocery list**: Menu → **Grocery List** → Review/edit items
- **Notifications**: Menu → **Notifications** → View/manage alerts

### Need Help?
1. Check relevant section in this manual
2. Review troubleshooting guide
3. Verify hardware connections
4. Check backend/cloud logs for errors

---

*End of User Manual*
