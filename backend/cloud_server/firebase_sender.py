# firebase_sender.py
import firebase_admin
from firebase_admin import credentials, firestore
import time

class FirebaseSender:
    def __init__(self, credentials_path):
        self.initialized = False
        
        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(credentials_path)
                firebase_admin.initialize_app(cred)
            
            self.db = firestore.client()
            self.collection_name = 'cabinet_events'
            self.initialized = True
            print("✅ Firebase connected")
            
        except Exception as e:
            print(f"❌ Firebase error: {e}")
            print("Events will be logged to console only")
    
    def send_event(self, event):
        """Send detection event to Firebase under specific device"""
        if not self.initialized:
            print(f"[OFFLINE] {event['label']} moved {event['direction']}")
            return False
        
        try:
            # ⭐ Get device_id from event
            device_id = event.get('device_id')
            
            if not device_id:
                print("❌ No device_id in event - cannot save detection")
                return False
            
            # ⭐ Save to devices/{deviceId}/detections subcollection
            detection_ref = self.db.collection('devices').document(device_id).collection('detections').document()
            
            event_data = {
                'label': event['label'],
                'detected_brand': event.get('detected_brand'),
                'direction': event['direction'],
                'confidence': event.get('confidence', 0.0),
                'timestamp': firestore.SERVER_TIMESTAMP,
                'timestamp_local': event['timestamp'],
                'object_id': event['object_id'],
                'processed': False,  # For automatic detection processing
                'applied': False,     # Legacy field (kept for compatibility)
                'bbox': event.get('bbox', [])
            }
            
            detection_ref.set(event_data)
            
            brand_info = f" [{event.get('detected_brand')}]" if event.get('detected_brand') else ""
            print(f"📤 Firebase: {event['label']}{brand_info} - {event['direction']} (device: {device_id})")
            return True
            
        except Exception as e:
            print(f"❌ Firebase send error: {e}")
            return False