# smart_cabinet_pi_backend.py
# Unified backend - handles calibration, streaming, and detection
# Controlled entirely through Firebase (no command line needed!)

import cv2
import time
import json
import sys
import os
from picamera2 import Picamera2
import firebase_admin
from firebase_admin import credentials, firestore
import socket
import struct
import threading
import traceback
import base64

class SmartCabinetPiBackend:
    def __init__(self, firebase_creds, device_name="kitchen_cabinet"):
        print("="*60)
        print("🍓 SMART CABINET - RASPBERRY PI BACKEND")
        print("="*60)
        
        self.device_name = device_name
        self.device_id = self.get_device_id()
        
        # Initialize Firebase
        print(f"\n🔥 Connecting to Firebase...")
        try:
            if not firebase_admin._apps:
                cred = credentials.Certificate(firebase_creds)
                firebase_admin.initialize_app(cred, {
                    'storageBucket': 'your-project-id.appspot.com'  # Replace with your Firebase project
                })
            
            self.db = firestore.client()
            print("✅ Firebase connected")
        except Exception as e:
            print(f"❌ Firebase error: {e}")
            sys.exit(1)
        
        # Initialize camera
        print(f"\n📷 Initializing camera...")
        self.camera = Picamera2()
        config = self.camera.create_video_configuration(
            main={"format": 'XRGB8888', "size": (640, 480)}
        )
        self.camera.configure(config)
        self.camera.start()
        time.sleep(2)
        print("✅ Camera ready")
        
        # State
        self.running = False
        self.streaming = False
        self.cloud_server_ip = None
        self.cloud_server_port = 8485
        self.socket = None
        
        # Register device
        self.register_device()
        
        print(f"\n✅ Backend initialized!")
        print(f"   Device ID: {self.device_id}")
        print(f"   Device Name: {self.device_name}")
    
    def get_device_id(self):
        """Get unique device ID from MAC address"""
        import uuid
        mac = uuid.getnode()
        mac_str = ':'.join(['{:02x}'.format((mac >> elements) & 0xff) 
                           for elements in range(0,2*6,2)][::-1])
        return mac_str
    
    def register_device(self):
        """Register this device in Firebase - FIXED FIELD NAMES"""
        device_ref = self.db.collection('devices').document(self.device_id)
        device_ref.set({
            'deviceId': self.device_id,  # Changed from device_id
            'name': self.device_name,
            'type': 'smart_cabinet_camera',
            'status': 'online',
            'detection_enabled': False,  # Changed from detection_running
            'preview_enabled': False,    # Added - Flutter expects this
            'calibration_requested': False,  # Added - Flutter expects this
            'lastSeen': firestore.SERVER_TIMESTAMP,  # Changed from last_seen
            'firmware_version': '1.0.0',
            # These will be set by the app when user pairs the device:
            # 'userId': None,
            # 'boundary': None,
            # 'preview_image': None,
            # 'preview_ts': None,
            # 'calibration_image': None,
            # 'calibration_ts': None
        }, merge=True)
        
        print(f"\n📝 Device registered in Firebase")
        print(f"   Add this device in your app using ID: {self.device_id}")
    
    def listen_for_commands(self):
        """Listen for commands from app via Firebase"""
        print("\n👂 Listening for app commands...")
        
        def on_snapshot(doc_snapshot, changes, read_time):
            for doc in doc_snapshot:
                config = doc.to_dict()
                
                # Handle calibration request
                if config.get('calibration_requested', False):
                    print("\n📏 Calibration requested from app")
                    self.send_calibration_frame()
                    # Clear the request
                    doc.reference.update({'calibration_requested': False})
                
                # Handle preview streaming
                if config.get('preview_enabled', False) and not self.streaming:
                    print("\n📹 Starting preview stream")
                    threading.Thread(target=self.stream_preview, daemon=True).start()
                elif not config.get('preview_enabled', False) and self.streaming:
                    print("\n⏹️  Stopping preview stream")
                    self.streaming = False
                
                # Handle detection start/stop
                if config.get('detection_enabled', False) and not self.running:
                    cloud_ip = config.get('cloud_server_ip')
                    boundary = config.get('boundary')
                    
                    if not boundary:
                        print("⚠️  Detection enabled but no boundary set - waiting for boundary")
                    elif cloud_ip:
                        self.cloud_server_ip = cloud_ip
                        print(f"\n▶️  Starting detection (cloud: {cloud_ip})")
                        threading.Thread(target=self.start_detection, daemon=True).start()
                    else:
                        print("⚠️  Detection enabled but no cloud server IP")
                        
                elif not config.get('detection_enabled', False) and self.running:
                    print("\n⏹️  Stopping detection")
                    self.stop_detection()
        
        # Watch device document for changes
        device_ref = self.db.collection('devices').document(self.device_id)
        doc_watch = device_ref.on_snapshot(on_snapshot)
        
        return doc_watch
    
    def send_calibration_frame(self):
        """
        Capture a single calibration frame and save it into the device Firestore document.
        We encode the JPEG into base64 and write it to:
          devices/<device_id>.calibration_image (string, base64)
          devices/<device_id>.calibration_ts    (server timestamp)
        """
        try:
            print("📸 Capturing calibration frame...")
            
            # Capture frame from Picamera2
            frame = self.camera.capture_array()
            # If frame is BGRA drop alpha channel; if already BGR, keep it
            frame_bgr = frame[:, :, :3] if frame.shape[2] == 4 else frame

            # Encode as JPEG into memory buffer (choose quality to control size)
            encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 75]
            success, buffer = cv2.imencode('.jpg', frame_bgr, encode_param)
            if not success:
                print("❌ Failed to encode calibration frame as JPEG")
                return

            jpeg_bytes = buffer.tobytes()
            print(f"📦 JPEG size: {len(jpeg_bytes)} bytes")

            # Convert to base64 string (safe to store in Firestore)
            b64 = base64.b64encode(jpeg_bytes).decode('utf-8')
            print(f"📝 Base64 string length: {len(b64)} chars")

            # Prepare doc update
            device_ref = self.db.collection('devices').document(self.device_id)
            update_data = {
                'calibration_image': b64,
                'calibration_ts': firestore.SERVER_TIMESTAMP,
                'calibration_width': 640,  # ⭐ Store actual camera resolution
                'calibration_height': 480,
                'lastSeen': firestore.SERVER_TIMESTAMP
            }

            # Write to Firestore
            device_ref.update(update_data)
            print("✅ Calibration frame saved to Firestore (field: calibration_image)")

        except Exception as e:
            print(f"❌ Calibration frame upload error: {e}")
            traceback.print_exc()
    
    def stream_preview(self):
        """
        Periodically capture preview frames and write them into Firestore device document.
        Writes:
          devices/<device_id>.preview_image (base64 string)
          devices/<device_id>.preview_ts    (server timestamp)
        """
        self.streaming = True
        print("🎬 Preview streaming started")
        
        try:
            frame_count = 0
            while self.streaming:
                frame = self.camera.capture_array()
                frame_bgr = frame[:, :, :3] if frame.shape[2] == 4 else frame

                # Encode to JPEG: reduce quality to keep size small
                encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 70]
                success, buffer = cv2.imencode('.jpg', frame_bgr, encode_param)
                if not success:
                    print("⚠️  JPEG encoding failed for preview, skipping frame")
                    time.sleep(1)
                    continue

                jpeg_bytes = buffer.tobytes()
                b64 = base64.b64encode(jpeg_bytes).decode('utf-8')

                frame_count += 1
                if frame_count % 10 == 0:  # Log every 10 frames
                    print(f"📸 Preview frame {frame_count} - Size: {len(jpeg_bytes)} bytes")

                # Update Firestore fields
                device_ref = self.db.collection('devices').document(self.device_id)
                update_data = {
                    'preview_image': b64,
                    'preview_ts': firestore.SERVER_TIMESTAMP,
                    'lastSeen': firestore.SERVER_TIMESTAMP
                }

                try:
                    device_ref.update(update_data)
                except Exception as e:
                    print(f"❌ Firestore update error when uploading preview: {e}")
                    traceback.print_exc()

                # Sleep between frames (1-2 seconds recommended)
                time.sleep(1)

        except Exception as e:
            print(f"❌ Preview streaming error: {e}")
            traceback.print_exc()
        finally:
            self.streaming = False
            print("🎬 Preview streaming stopped")
    
    def start_detection(self):
        """Connect to cloud server and start streaming for detection"""
        if not self.cloud_server_ip:
            print("❌ No cloud server IP configured")
            return
        
        self.running = True
        
        # Update status
        self.db.collection('devices').document(self.device_id).update({
            'detection_enabled': True,
            'lastSeen': firestore.SERVER_TIMESTAMP
        })
        
        try:
            # Connect to cloud server
            self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            # ⭐ Disable Nagle's algorithm for lower latency
            self.socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.socket.connect((self.cloud_server_ip, self.cloud_server_port))
            print(f"✅ Connected to cloud server")
            
            # Send device_id to server
            device_id_bytes = self.device_id.encode('utf-8')
            self.socket.sendall(struct.pack("Q", len(device_id_bytes)))
            self.socket.sendall(device_id_bytes)
            print(f"📤 Sent device_id: {self.device_id}")
            
            frame_count = 0
            start_time = time.time()
            last_send_time = time.time()
            
            # ⭐ Target FPS for sending (reduce if network is slow)
            target_fps = 10  # Send max 10 FPS to cloud
            frame_interval = 1.0 / target_fps
            
            while self.running:
                current_time = time.time()
                
                # ⭐ Skip frame if we're sending too fast
                if current_time - last_send_time < frame_interval:
                    time.sleep(0.01)  # Small sleep to avoid busy-waiting
                    continue
                
                # Capture frame
                frame = self.camera.capture_array()
                frame_bgr = frame[:, :, :3] if frame.shape[2] == 4 else frame
                
                # ⭐ Resize frame to reduce data (optional - adjust as needed)
                # Smaller = faster transmission, but lower detection quality
                  # Half resolution
                
                # ⭐ Encode as JPEG with lower quality for faster transmission
                _, buffer = cv2.imencode('.jpg', frame_bgr, [cv2.IMWRITE_JPEC_QUALITY, 70])  # Reduced quality
                data = buffer.tobytes()
                
                # Send to cloud server with error handling
                try:
                    send_start = time.time()
                    self.socket.sendall(struct.pack("Q", len(data)) + data)
                    send_time = time.time() - send_start
                    
                    # ⭐ Warn if sending is too slow
                    if send_time > 0.1:  # More than 100ms to send
                        print(f"⚠️  Slow network: {send_time*1000:.0f}ms to send frame")
                    
                    last_send_time = current_time
                    
                except BrokenPipeError:
                    print("❌ Connection to cloud server lost (broken pipe)")
                    break
                except Exception as e:
                    print(f"❌ Connection error: {e}")
                    break
                
                # Update stats
                frame_count += 1
                if frame_count % 30 == 0:
                    elapsed = time.time() - start_time
                    fps = frame_count / elapsed if elapsed > 0 else 0
                    print(f"📊 Sending to cloud: {fps:.1f} FPS (target: {target_fps} FPS)")
                    
                    # Update in Firebase
                    self.db.collection('devices').document(self.device_id).update({
                        'streaming_fps': round(fps, 1),
                        'lastSeen': firestore.SERVER_TIMESTAMP
                    })
        
        except Exception as e:
            print(f"❌ Detection error: {e}")
            traceback.print_exc()
        
        finally:
            self.stop_detection()
    
    def stop_detection(self):
        """Stop detection thread and close connection"""
        print("\n⏹️  Stopping detection...")
        self.running = False
        
        if hasattr(self, 'detection_thread') and self.detection_thread:
            self.detection_thread.join(timeout=5)
            print("✅ Detection thread stopped")
        
        # ⭐ Close socket gracefully
        if hasattr(self, 'socket') and self.socket:
            try:
                self.socket.shutdown(socket.SHUT_RDWR)
                self.socket.close()
                print("🔌 Disconnected from cloud server")
            except:
                pass
            self.socket = None
        
        # Update Firebase status
        self.db.collection('devices').document(self.device_id).update({
            'detection_enabled': False,  # Changed from detection_running
            'lastSeen': firestore.SERVER_TIMESTAMP
        })
    
    def heartbeat(self):
        """Send heartbeat to Firebase every 10 seconds"""
        while True:
            try:
                self.db.collection('devices').document(self.device_id).update({
                    'lastSeen': firestore.SERVER_TIMESTAMP,  # Changed from last_seen
                    'status': 'online'
                })
            except:
                pass
            
            time.sleep(10)
    
    def run(self):
        """Main run loop"""
        print(f"\n{'='*60}")
        print("✅ BACKEND RUNNING - Waiting for app commands")
        print(f"{'='*60}\n")
        
        # Start heartbeat thread
        threading.Thread(target=self.heartbeat, daemon=True).start()
        
        # Listen for commands
        command_watch = self.listen_for_commands()
        
        try:
            # Keep running
            while True:
                time.sleep(1)
        
        except KeyboardInterrupt:
            print("\n⏹️  Shutting down...")
        
        finally:
            self.stop_detection()
            self.streaming = False
            command_watch.unsubscribe()
            self.camera.stop()
            
            # Update status to offline
            self.db.collection('devices').document(self.device_id).update({
                'status': 'offline',
                'detection_enabled': False,  # Changed from detection_running
                'lastSeen': firestore.SERVER_TIMESTAMP
            })
            
            print("👋 Backend stopped")
    

if __name__ == '__main__':
    import argparse
    
    parser = argparse.ArgumentParser()
    parser.add_argument('--firebase-creds', default='firebase-credentials.json',
                       help='Path to Firebase credentials')
    parser.add_argument('--device-name', default='kitchen_cabinet',
                       help='Friendly name for this device')
    
    args = parser.parse_args()
    
    # Create and run backend
    backend = SmartCabinetPiBackend(
        firebase_creds=args.firebase_creds,
        device_name=args.device_name
    )
    
    backend.run()
