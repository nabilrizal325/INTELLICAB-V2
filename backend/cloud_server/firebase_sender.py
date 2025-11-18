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
        """Send detection event to Firebase"""
        if not self.initialized:
            print(f"[OFFLINE] {event['label']} moved {event['direction']}")
            return False
        
        try:
            event_data = {
                'item_name': event['label'],
                'direction': event['direction'],
                'timestamp': firestore.SERVER_TIMESTAMP,
                'timestamp_local': event['timestamp'],
                'object_id': event['object_id'],
                'device': 'cloud_camera',
                'user_id': 'nabilrizal325',  # Your user ID
                'status': 'unread',
                'processed': False
            }
            
            doc_ref = self.db.collection(self.collection_name).add(event_data)
            print(f"📤 Firebase: {event['label']} - {event['direction']}")
            return True
            
        except Exception as e:
            print(f"❌ Firebase send error: {e}")
            return False