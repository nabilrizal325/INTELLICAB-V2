# cloud_detection_server.py
# Cloud detection server - receives frames and processes them

import cv2
import socket
import struct
import time
import argparse
import numpy as np
from ultralytics import YOLO
from firebase_sender import FirebaseSender
from centroid_tracker import CentroidTracker
from direction_detector import DirectionDetector

# Brand extraction for better inventory matching
def extract_brand(item_name):
    """
    Extract brand from YOLO class name for inventory matching
    
    Examples:
        "coca_cola_can" → "coca cola"
        "pepsi_bottle" → "pepsi"
        "sprite_zero" → "sprite"
        "bottle" → None
    """
    # Common brand keywords (add more as needed)
    brand_keywords = [
        'coca_cola', 'coke', 'pepsi', 'sprite', 'fanta', 'mountain_dew',
        'redbull', 'monster', 'gatorade', 'powerade', 'aquafina', 'dasani',
        'nestle', 'lipton', 'snapple', 'arizona', 'vitamin_water',
        'perrier', 'evian', 'fiji', 'smartwater', 'propel'
    ]
    
    item_lower = item_name.lower().replace(' ', '_')
    
    for keyword in brand_keywords:
        if keyword in item_lower:
            # Return cleaned brand name
            return keyword.replace('_', ' ')
    
    # No brand detected
    return None

class CloudDetectionServer:
    def __init__(self, model_path, firebase_creds, port=8485, show_display=True):
        self.port = port
        self.show_display = show_display
        
        print("="*60)
        print("🌩️  CLOUD DETECTION SERVER")
        print("="*60)
        
        # Load YOLO model
        print(f"\n📦 Loading YOLO model: {model_path}")
        self.model = YOLO(model_path)
        print("✅ Model loaded successfully!")
        
        # Initialize tracking (will be per-device)
        print("\n🎯 Initializing object tracking...")
        self.tracker = CentroidTracker(maxDisappeared=30)
        self.direction_detector = DirectionDetector()
        
        # Initialize Firebase
        print(f"\n🔥 Connecting to Firebase...")
        try:
            self.firebase_sender = FirebaseSender(firebase_creds)
            # Store db reference for loading boundaries
            import firebase_admin
            from firebase_admin import firestore
            self.db = firestore.client()
        except Exception as e:
            print(f"⚠️  Firebase not initialized: {e}")
            self.firebase_sender = None
            self.db = None
        
        # Stats
        self.frame_count = 0
        self.start_time = None
        self.total_events = 0

    def print_stats(self):
        """Print final statistics"""
        if hasattr(self, 'start_time') and self.start_time:
            elapsed = time.time() - self.start_time
            fps = self.frame_count / elapsed if elapsed > 0 else 0
            
            print(f"\n{'='*60}")
            print("📊 SESSION STATISTICS")
            print(f"{'='*60}")
            print(f"Total frames processed: {self.frame_count}")
            print(f"Total time: {elapsed:.1f} seconds")
            print(f"Average FPS: {fps:.2f}")
            print(f"Total events detected: {self.total_events}")
            print(f"{'='*60}\n")
        else:
            print("\n📊 No statistics available\n")
        
    def start_server(self):
        """Start socket server and accept connections"""
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(('0.0.0.0', self.port))
        server_socket.listen(5)
        
        print(f"🚀 Cloud detection server listening on port {self.port}")
        print("Waiting for Pi devices to connect...")
        
        # ⭐ Keep server running in loop
        while True:
            try:
                conn, addr = server_socket.accept()
                print(f"\n📥 New connection from {addr}")
                
                # Process frames from this Pi device
                self.process_frames(conn)
                
                # ⭐ After Pi disconnects, continue accepting new connections
                print(f"📤 Device {addr} disconnected")
                print("Waiting for next connection...")
                
            except KeyboardInterrupt:
                print("\n⏹️  Server shutting down...")
                break
            except Exception as e:
                print(f"⚠️  Connection error: {e}")
                print("Waiting for next connection...")
                continue
    
        server_socket.close()
    
    def process_frames(self, conn):
        """Process incoming frames from camera"""
        print("📥 Client connected")
        
        # Receive device_id
        try:
            device_id_size = struct.unpack("Q", conn.recv(8))[0]
            device_id = conn.recv(device_id_size).decode('utf-8')
            print(f"📱 Device ID: {device_id}")
            self.current_device_id = device_id
        except Exception as e:
            print(f"❌ Failed to receive device_id: {e}")
            conn.close()
            return
        
        # ⭐ Load boundary from Firebase for this device
        if self.db:
            try:
                device_doc = self.db.collection('devices').document(device_id).get()
                if device_doc.exists:
                    device_data = device_doc.to_dict()
                    boundary = device_data.get('boundary')
                    if boundary:
                        # Store original boundary for scaling
                        self.boundary_original = {
                            'x1': int(boundary['x1']),
                            'y1': int(boundary['y1']),
                            'x2': int(boundary['x2']),
                            'y2': int(boundary['y2'])
                        }
                        
                        # Get calibration resolution
                        self.calibration_width = device_data.get('calibration_width', 640)
                        self.calibration_height = device_data.get('calibration_height', 480)
                        
                        print(f"\n📏 BOUNDARY INFO:")
                        print(f"   Boundary coordinates: ({self.boundary_original['x1']},{self.boundary_original['y1']}) -> ({self.boundary_original['x2']},{self.boundary_original['y2']})")
                        print(f"   Calibration resolution: {self.calibration_width}x{self.calibration_height}")
                        print(f"   Will auto-scale to match incoming frames\n")
                        
                        # Don't set boundary yet - will scale on first frame
                        self.boundary_scaled = False
                        
                    else:
                        print("⚠️  No boundary set for this device - detections will be logged but not tracked")
                else:
                    print(f"⚠️  Device {device_id} not found in Firebase")
            except Exception as e:
                print(f"⚠️  Failed to load boundary: {e}")
        
        # ⭐ Initialize variables for frame receiving
        data = b''
        payload_size = struct.calcsize("Q")
        
        # ⭐ Initialize start_time for FPS tracking
        if self.start_time is None:
            self.start_time = time.time()
        
        # ⭐ Wrap frame processing in try-except
        try:
            while True:
                # Receive frame size
                while len(data) < payload_size:
                    packet = conn.recv(4096)
                    if not packet:
                        raise ConnectionError("Connection lost")
                    data += packet
                
                packed_msg_size = data[:payload_size]
                data = data[payload_size:]
                msg_size = struct.unpack("Q", packed_msg_size)[0]
                
                # Receive frame data
                while len(data) < msg_size:
                    data += conn.recv(4096)
                
                frame_data = data[:msg_size]
                data = data[msg_size:]
                
                # Deserialize frame
                # Decode JPEG
                try:
                    nparr = np.frombuffer(frame_data, np.uint8)
                    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                    
                    if frame is None:
                        raise ValueError("Failed to decode JPEG frame")
                    
                    # 🔍 DEBUG: Print frame dimensions (only every 30 frames to avoid spam)
                    if self.frame_count % 30 == 0:
                        print(f"\n📐 FRAME DEBUG INFO:")
                        print(f"   Frame shape: {frame.shape}")
                        print(f"   Height: {frame.shape[0]} pixels")
                        print(f"   Width: {frame.shape[1]} pixels")
                        print(f"   Channels: {frame.shape[2]}\n")
                except Exception as e:
                    print(f"❌ Decode error: {e}")
                    print(f"   Received {len(frame_data)} bytes")
                    print(f"   First 20 bytes: {frame_data[:20]}")
                    raise
                
                # Process frame
                self.process_single_frame(frame)
                
        except KeyboardInterrupt:
            raise
        except ConnectionResetError:
            print(f"🔌 Device {device_id} disconnected (connection reset)")
        except Exception as e:
            print(f"⚠️  Error processing frames from {device_id}: {e}")
        finally:
            conn.close()
            print(f"✅ Connection closed for {device_id}")
            # ⭐ Server continues running, waiting for next connection
    
    def process_single_frame(self, frame):
        """Process a single frame - run detection and tracking"""
        
        # ⭐ Auto-scale boundary on first frame
        if hasattr(self, 'boundary_original') and not getattr(self, 'boundary_scaled', False):
            frame_height, frame_width = frame.shape[:2]
            
            # Calculate scale factors
            scale_x = frame_width / self.calibration_width
            scale_y = frame_height / self.calibration_height
            
            # Scale boundary points
            scaled_x1 = int(self.boundary_original['x1'] * scale_x)
            scaled_y1 = int(self.boundary_original['y1'] * scale_y)
            scaled_x2 = int(self.boundary_original['x2'] * scale_x)
            scaled_y2 = int(self.boundary_original['y2'] * scale_y)
            
            # Clamp to frame bounds
            scaled_x1 = max(0, min(scaled_x1, frame_width - 1))
            scaled_x2 = max(0, min(scaled_x2, frame_width - 1))
            scaled_y1 = max(0, min(scaled_y1, frame_height - 1))
            scaled_y2 = max(0, min(scaled_y2, frame_height - 1))
            
            scaled_points = [(scaled_x1, scaled_y1), (scaled_x2, scaled_y2)]
            self.direction_detector.set_boundary(scaled_points)
            self.boundary_scaled = True
            
            print(f"\n✅ BOUNDARY AUTO-SCALED:")
            print(f"   Calibration resolution: {self.calibration_width}x{self.calibration_height}")
            print(f"   Actual frame resolution: {frame_width}x{frame_height}")
            print(f"   Scale factors: x={scale_x:.3f}, y={scale_y:.3f}")
            print(f"   Original boundary: ({self.boundary_original['x1']},{self.boundary_original['y1']}) -> ({self.boundary_original['x2']},{self.boundary_original['y2']})")
            print(f"   Scaled boundary:   ({scaled_x1},{scaled_y1}) -> ({scaled_x2},{scaled_y2})\n")
        
        frame_start = time.time()
        
        # Run YOLO detection
        detect_start = time.time()
        results = self.model(frame, verbose=False)
        detect_time = time.time() - detect_start
        
        # Extract detections
        extract_start = time.time()
        boxes = []
        labels = []
        confidences = []
        
        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                conf = float(box.conf[0])
                cls = int(box.cls[0])
                label = self.model.names[cls]
                
                if conf > 0.8:
                    boxes.append([int(x1), int(y1), int(x2), int(y2)])
                    labels.append(label)
                    confidences.append(conf)
                    
                    if self.show_display:
                        cv2.rectangle(frame, (int(x1), int(y1)), 
                                    (int(x2), int(y2)), (0, 255, 0), 2)
                        cv2.putText(frame, f"{label} {conf:.2f}", 
                                (int(x1), int(y1)-10), 
                                cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 2)
        
        extract_time = time.time() - extract_start
        
        # Update tracker
        track_start = time.time()
        objects = self.tracker.update(boxes, labels)
        events = self.direction_detector.update(objects)
        track_time = time.time() - track_start
        
        # Handle events with brand extraction
        for event in events:
            self.total_events += 1
            detected_brand = extract_brand(event['label'])
            brand_info = f" (brand: {detected_brand})" if detected_brand else ""
            print(f"\n🔔 EVENT #{self.total_events}: {event['label']} moved {event['direction']}{brand_info}")
            
            if self.firebase_sender:
                # Add brand info and device_id to event
                event['detected_brand'] = detected_brand
                event['device_id'] = self.current_device_id
                self.firebase_sender.send_event(event)
        
        # Draw display
        display_start = time.time()
        if self.show_display:
            # Draw boundary line
            self.direction_detector.draw_boundary(frame)
            
            # 🔍 DEBUG: Draw boundary endpoints as circles and add info text
            if hasattr(self.direction_detector, 'boundary') and self.direction_detector.boundary:
                p1, p2 = self.direction_detector.boundary
                # Draw large circles at boundary endpoints
                cv2.circle(frame, p1, 10, (0, 0, 255), -1)  # Red circle at start point
                cv2.circle(frame, p2, 10, (255, 0, 0), -1)  # Blue circle at end point
                
                # Add text labels
                cv2.putText(frame, "START", (p1[0] + 15, p1[1]), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
                cv2.putText(frame, "END", (p2[0] + 15, p2[1]), 
                           cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 0, 0), 2)
            
            for obj_id, obj_data in objects.items():
                centroid = obj_data['centroid']
                label = obj_data['label']
                cv2.circle(frame, centroid, 4, (255, 0, 0), -1)
                cv2.putText(frame, f"ID:{obj_id}", 
                        (centroid[0]-10, centroid[1]-10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 0), 2)
            
            # Display stats
            elapsed = time.time() - self.start_time
            fps = self.frame_count / elapsed if elapsed > 0 else 0
            cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)
            
            cv2.putText(frame, f"Events: {self.total_events}", (10, 70),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)
            
            # 🔍 DEBUG: Display frame dimensions and boundary coordinates
            h, w = frame.shape[:2]
            cv2.putText(frame, f"Frame: {w}x{h}", (10, 110),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2)
            
            if hasattr(self.direction_detector, 'boundary') and self.direction_detector.boundary:
                p1, p2 = self.direction_detector.boundary
                cv2.putText(frame, f"Boundary: ({p1[0]},{p1[1]}) -> ({p2[0]},{p2[1]})", 
                           (10, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 255), 1)
            
            cv2.imshow('Cloud Detection Server', frame)
            if cv2.waitKey(1) == ord('q'):
                raise KeyboardInterrupt
        
        display_time = time.time() - display_start
        
        # Print timing every 30 frames
        self.frame_count += 1
        if self.frame_count % 30 == 0:
            elapsed = time.time() - self.start_time
            fps = self.frame_count / elapsed
            
            print(f"\n📊 FPS: {fps:.2f} | Events: {self.total_events}")
            print(f"⏱️  Timing breakdown:")
            print(f"   Detection: {detect_time*1000:.1f}ms")
            print(f"   Extract:   {extract_time*1000:.1f}ms")
            print(f"   Tracking:  {track_time*1000:.1f}ms")
            print(f"   Display:   {display_time*1000:.1f}ms")
            print(f"   Total:     {(detect_time+extract_time+track_time+display_time)*1000:.1f}ms")

def main():
    parser = argparse.ArgumentParser(description='Cloud Detection Server')
    parser.add_argument('--model', default='my_model.pt',
                       help='Path to YOLO model (use .pt on laptop)')
    parser.add_argument('--firebase-creds', default='firebase-credentials.json',
                       help='Path to Firebase credentials JSON')
    parser.add_argument('--port', type=int, default=8485,
                       help='Server port')
    parser.add_argument('--no-display', action='store_true',
                       help='Run without display (faster)')
    
    args = parser.parse_args()
    
    # Create and start server
    server = CloudDetectionServer(
        model_path=args.model,
        firebase_creds=args.firebase_creds,
        port=args.port,
        show_display=not args.no_display

    
    )
    
    server.start_server()


if __name__ == '__main__':
    main()