# 🎯 Auto-Matching System Documentation

## Overview
The IntelliCab system now features **intelligent automatic inventory matching** between YOLO object detection and user's scanned inventory items.

## How It Works

### 1. User Workflow
```
1. User scans items with barcode scanner
   ↓
2. Items stored in inventory with brand + name
   ↓
3. Items start in "unorganized" location
   ↓
4. User connects AI camera to app
   ↓
5. Camera detects items going IN/OUT
   ↓
6. System automatically matches detection with inventory
   ↓
7. If match found: Update inventory quantity
   If item in unorganized + going IN: Move to device location
```

### 2. Matching Algorithm

The system uses a **multi-strategy fuzzy matching** approach:

#### Scoring System (0.0 to 1.0):
- **Exact Match**: 1.0 (perfect match)
- **Brand Match**: +0.4 (detected_brand matches inventory.brand)
- **Substring Match**: 0.6-0.7 (one name contains the other)
- **Word Overlap**: 0.3-0.8 (based on percentage of matching words)
- **Brand in Name**: +0.3 (brand mentioned in product name)

#### Matching Examples:
```
YOLO Detection: "coca_cola_bottle"
Inventory: "Coca Cola" (brand: "Coca Cola")
Match Score: 0.95 ✅

YOLO Detection: "bottle"
Inventory: "Sprite Zero" (brand: "Sprite")
Match Score: 0.35 ❌ (below 60% threshold)

YOLO Detection: "pepsi_can"
Inventory: "Pepsi Max" (brand: "Pepsi")
Match Score: 0.78 ✅
```

### 3. Confidence Threshold
- Minimum **60% match confidence** required
- If no match above 60%: Create new inventory item (if direction=IN)
- Match scores logged to Firestore for transparency

## Code Changes

### ✅ Modified Files

#### 1. `lib/device_service.dart`
- **Replaced** `processDetection()` method with smart matching logic
- **Added** `_calculateMatchScore()` helper method
- **Changed**: Now queries ALL inventory items instead of exact name match
- **New Fields**: Logs `matchScore` and `matchedItemName` to detection documents

#### 2. `lib/detection_history_screen.dart`
- **Added** match score display in detection cards
- **Shows**: Green link icon + "Matched: {item} ({score}%)"
- **Example**: "Matched: Coca Cola (92%)"

#### 3. `backend/cloud_server/` (TODO)
- **Update**: `log_detection_event()` to extract `detected_brand` field
- **Purpose**: Extract brand from YOLO class name for better matching

## Database Schema

### Inventory Collection
```
User/{userId}/inventory/{itemId}
{
  name: String,              // "Coca Cola"
  brand: String,             // "Coca Cola"
  deviceId: String,          // "AA:BB:CC:DD:EE:FF" or "unorganized"
  deviceName: String,        // "Kitchen Cabinet"
  quantity: int,             // 5
  category: String,          // "Beverages" or "Auto-detected"
  added_date: Timestamp,
  last_updated: Timestamp
}
```

### Detection Collection
```
devices/{deviceId}/detections/{detectionId}
{
  timestamp: Timestamp,
  item_name: String,         // "coca_cola_bottle" (YOLO class)
  detected_brand: String,    // "coca cola" (extracted from YOLO)
  confidence: double,        // 0.95 (YOLO confidence)
  direction: String,         // "in" or "out"
  image_base64: String,      // Thumbnail
  processed: bool,           // true after user action
  ignored: bool,             // true if false positive
  matchScore: double,        // 0.92 (matching confidence)
  matchedItemName: String,   // "Coca Cola" (inventory item matched)
  inventoryUpdated: bool,    // true if quantity changed
  processedAt: Timestamp
}
```

## UI Examples

### Detection Card with Match Info
```
┌─────────────────────────────────────┐
│ 🖼️  Coca Cola          ↓ IN        │
│     Confidence: 95.2%               │
│     🔗 Matched: Coca Cola (92%)    │
│     Dec 15, 2024 - 3:45 PM         │
│     [ APPLIED ]                     │
└─────────────────────────────────────┘
```

### Detection Card with Low Match
```
┌─────────────────────────────────────┐
│ 🖼️  Unknown Bottle     ↓ IN        │
│     Confidence: 87.3%               │
│     Dec 15, 2024 - 3:48 PM         │
│     [Edit] [Apply] [Ignore]        │
└─────────────────────────────────────┘
```

## Benefits

### For Users:
✅ **Automatic inventory sync** - No manual entry needed
✅ **Smart matching** - Handles YOLO class names vs product names
✅ **Transparent confidence** - Users can see match quality
✅ **Manual override** - Can still edit/ignore detections
✅ **Auto-organization** - Items move from unorganized to device

### For Developers:
✅ **Fuzzy matching** - Handles variations in naming
✅ **Brand-aware** - Uses brand information for better accuracy
✅ **Logged metadata** - Match scores stored for analysis
✅ **Extensible** - Easy to add new matching strategies
✅ **Threshold-based** - Configurable confidence level

## Testing Scenarios

### Test Case 1: Perfect Match
```dart
Inventory: {"name": "Coca Cola", "brand": "Coca Cola"}
Detection: "coca_cola_can"
Expected: Match Score ~0.9, Auto-apply
```

### Test Case 2: Partial Match
```dart
Inventory: {"name": "Pepsi Max", "brand": "Pepsi"}
Detection: "pepsi_bottle"
Expected: Match Score ~0.7, Auto-apply
```

### Test Case 3: Low Confidence
```dart
Inventory: {"name": "Sprite", "brand": "Sprite"}
Detection: "bottle"
Expected: Match Score <0.6, Create new item
```

### Test Case 4: Move from Unorganized
```dart
Inventory: {"name": "Coca Cola", "deviceId": "unorganized"}
Detection: "coca_cola_can" direction="in" on device "AA:BB:CC"
Expected: Match, move to device AA:BB:CC, quantity +1
```

## Future Improvements

### Potential Enhancements:
1. **Machine Learning**: Train model to learn user's naming patterns
2. **User Feedback Loop**: Let users confirm/reject matches to improve algorithm
3. **Multi-language Support**: Handle different language product names
4. **OCR Integration**: Extract text from product images for better matching
5. **Synonym Database**: Map common variations (e.g., "Coke" → "Coca Cola")
6. **Expiry Date Tracking**: Auto-update expiry dates from detection timestamps

### Python Server Updates (TODO):
```python
# In cloud_detection_server.py
def extract_brand(item_name):
    """Extract brand from YOLO class name"""
    # Examples:
    # "coca_cola_can" → "coca cola"
    # "pepsi_bottle" → "pepsi"
    # "sprite_zero" → "sprite"
    
    brand_keywords = ['coca_cola', 'pepsi', 'sprite', 'fanta', ...]
    for keyword in brand_keywords:
        if keyword in item_name.lower():
            return keyword.replace('_', ' ')
    return None

# Update log_detection_event()
firebase_sender.log_detection(
    device_id=device_id,
    item_name=item_name,
    detected_brand=extract_brand(item_name),  # NEW FIELD
    confidence=confidence,
    direction=direction,
    image_base64=image_base64
)
```

## Troubleshooting

### Issue: No matches found
- Check if items exist in inventory
- Verify brand field is populated
- Lower confidence threshold (currently 60%)
- Add more matching strategies

### Issue: Wrong items matched
- Review match score logic
- Add more specific brand keywords
- Increase confidence threshold
- Use manual correction feature

### Issue: Items not moving from unorganized
- Verify direction is 'in'
- Check deviceId is 'unorganized'
- Ensure processDetection() completes successfully

## Console Logs

The system outputs detailed logs:
```
🎯 Matched detected "coca_cola_can" with inventory "Coca Cola" (92% confidence)
✅ Moved Coca Cola from unorganized to Kitchen Cabinet
```

```
⚠️ No inventory match for "unknown_bottle" (best score: 45%)
✅ Created new inventory item: unknown_bottle at Living Room
```

---

**Last Updated**: December 2024  
**Status**: ✅ Implemented in Flutter app (pending Python server update)
