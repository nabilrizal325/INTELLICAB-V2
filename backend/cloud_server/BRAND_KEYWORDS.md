# Brand Keywords Configuration

## Purpose
This file documents the brand keywords used by the cloud detection server to extract brand information from YOLO class names for better inventory matching.

## How It Works

### Current Implementation
Located in `cloud_detection_server.py` → `extract_brand()` function

### Extraction Logic
```python
YOLO Class Name → Brand Extraction
"coca_cola_can"  → "coca cola"
"pepsi_bottle"   → "pepsi"
"sprite_zero"    → "sprite"
"bottle"         → None (generic)
```

## Current Brand List

### Sodas & Soft Drinks
- `coca_cola`, `coke`
- `pepsi`
- `sprite`
- `fanta`
- `mountain_dew`

### Energy Drinks
- `redbull`
- `monster`
- `gatorade`
- `powerade`

### Water Brands
- `aquafina`
- `dasani`
- `perrier`
- `evian`
- `fiji`
- `smartwater`
- `propel`

### Tea & Coffee
- `nestle`
- `lipton`
- `snapple`
- `arizona`

### Other
- `vitamin_water`

## Adding New Brands

### Step 1: Edit cloud_detection_server.py
Find the `extract_brand()` function and add to the `brand_keywords` list:

```python
brand_keywords = [
    'coca_cola', 'coke', 'pepsi', 'sprite', 'fanta', 'mountain_dew',
    'redbull', 'monster', 'gatorade', 'powerade', 'aquafina', 'dasani',
    'nestle', 'lipton', 'snapple', 'arizona', 'vitamin_water',
    'perrier', 'evian', 'fiji', 'smartwater', 'propel',
    # ADD NEW BRANDS HERE:
    'your_brand_name',
]
```

### Step 2: Naming Convention
- Use lowercase
- Replace spaces with underscores
- Match YOLO model class names
- Examples:
  - "Red Bull" → `redbull` or `red_bull`
  - "Mountain Dew" → `mountain_dew`
  - "Dr Pepper" → `dr_pepper`

### Step 3: Test
Run the server and check console output:
```
🔔 EVENT #1: coca_cola_can moved in (brand: coca cola)
📤 Firebase: coca_cola_can [coca cola] - in
```

## Regional Brands

### Asia
```python
# Suggested additions for Asian markets:
'pocari_sweat', 'calpis', 'vitasoy', 'yakult',
'green_tea', 'oishi', 'minute_maid'
```

### Europe
```python
# Suggested additions for European markets:
'orangina', 'schweppes', 'ribena', 'lucozade',
'innocent', 'tropicana'
```

### Middle East
```python
# Suggested additions for Middle Eastern markets:
'barbican', 'rani', 'vimto', 'tang'
```

## Troubleshooting

### Issue: Brand not detected
**Symptom**: Console shows "🔔 EVENT: coca_cola_can moved in" (no brand info)

**Solutions**:
1. Check if brand keyword exists in `brand_keywords` list
2. Ensure YOLO class name contains the brand keyword
3. Check spelling matches (underscores vs spaces)

### Issue: Wrong brand detected
**Symptom**: "pepsi_can" detected as "pepsi_cola" brand

**Solutions**:
1. Check keyword order in list (more specific first)
2. Ensure exact substring matching
3. Add brand aliases if needed

### Issue: Generic items detected as brands
**Symptom**: "bottle" detected as "coca_cola" brand

**Solutions**:
1. Ensure YOLO model uses specific class names
2. Train model with brand-specific classes
3. Adjust keyword matching logic

## Best Practices

### ✅ DO:
- Use lowercase brand keywords
- Match your YOLO model's class names
- Add common brand variations (e.g., both "coke" and "coca_cola")
- Group brands by category for easy maintenance
- Test after adding new brands

### ❌ DON'T:
- Use spaces in keywords (use underscores)
- Add generic terms like "bottle", "can", "drink"
- Include special characters
- Duplicate keywords

## Integration with Flutter App

The extracted brand is used by the Flutter app's auto-matching system:

```dart
// In device_service.dart
double _calculateMatchScore({
  required String detectedName,
  String? detectedBrand,  // ← From Python server
  required String inventoryName,
  required String inventoryBrand,
}) {
  // Brand match adds +0.4 to score
  if (detectedBrand != null && 
      detectedBrand.isNotEmpty && 
      inventoryBrand.isNotEmpty) {
    if (inventoryBrand.contains(detectedBrand) || 
        detectedBrand.contains(inventoryBrand)) {
      score += 0.4;
    }
  }
  // ... more matching logic
}
```

## Future Enhancements

### 1. External Configuration File
Move brand keywords to `brands.json`:
```json
{
  "sodas": ["coca_cola", "pepsi", "sprite"],
  "energy": ["redbull", "monster"],
  "water": ["fiji", "evian"]
}
```

### 2. Machine Learning Approach
Train a separate model to classify brands from images:
```python
def extract_brand_ml(image_crop):
    # Use brand classification model
    brand_prediction = brand_model.predict(image_crop)
    return brand_prediction
```

### 3. OCR Integration
Use OCR to read brand text from labels:
```python
def extract_brand_ocr(image_crop):
    # Use Tesseract or EasyOCR
    text = ocr.read_text(image_crop)
    return match_brand_from_text(text)
```

### 4. User-Defined Brands
Allow users to add custom brands via app settings:
```python
# Load from Firestore
def load_user_brands(user_id):
    brands = db.collection('users').doc(user_id).get().get('custom_brands')
    return brands
```

---

**Last Updated**: November 19, 2025  
**Version**: 1.0  
**Maintained by**: IntelliCab Development Team
