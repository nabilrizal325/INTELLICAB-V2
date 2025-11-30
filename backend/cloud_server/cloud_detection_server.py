# cloud_detection_server.py
# Cloud detection server - receives frames and processes them

import cv2
import socket
import pickle
import struct
import time
import argparse
import numpy as np
from ultralytics import YOLO
from firebase_sender import FirebaseSender
from centroid_tracker import CentroidTracker
from direction_detector import DirectionDetector
import time

# Add timing variables
timing_stats = {
    'receive': [],
    'deserialize': [],
    'detection': [],
    'tracking': [],
    'display': []
}

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
        
        # Initialize tracking
        print("\n🎯 Initializing object tracking...")
        self.tracker = CentroidTracker(maxDisappeared=30)
        self.direction_detector = DirectionDetector()
        
        # Load boundary
        try:
            self.direction_detector.load_boundary('boundary.json')
            print("✅ Boundary loaded from boundary.json")
        except:
            print("⚠️  No boundary file found")
            print("   Run calibration first to set boundary")
        
        # Initialize Firebase
        print(f"\n🔥 Connecting to Firebase...")
        try:
            self.firebase_sender = FirebaseSender(firebase_creds)
        except Exception as e:
            print(f"⚠️  Firebase not initialized: {e}")
            self.firebase_sender = None
        
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
        """Start listening for camera connections"""
        # Create socket
        server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server_socket.bind(('0.0.0.0', self.port))
        server_socket.listen(5)
        
        print(f"\n{'='*60}")
        print(f"🔌 Server listening on port {self.port}")
        print(f"{'='*60}")
        print(f"\n⏳ Waiting for Raspberry Pi to connect...")
        print(f"   Make sure Pi is running the camera client")
        print(f"   and connected to the same network\n")
        
        try:
            # Accept connection
            conn, addr = server_socket.accept()
            print(f"\n✅ Connected to Raspberry Pi at {addr}")
            print(f"\n{'='*60}")
            print("🎥 DETECTION RUNNING")
            print(f"{'='*60}\n")
            
            # Process frames
            self.process_frames(conn)
            
        except KeyboardInterrupt:
            print("\n\n⏹️  Server stopped by user")
        except Exception as e:
            print(f"\n❌ Error: {e}")
        finally:
            server_socket.close()
            if self.show_display:
                cv2.destroyAllWindows()
            self.print_stats()
    
    def process_frames(self, conn):
        """Process incoming frames from camera"""
        print("📥 Client connected")
        
        # ⭐ NEW: Receive device_id first
        try:
            device_id_size = struct.unpack("Q", conn.recv(8))[0]
            device_id = conn.recv(device_id_size).decode('utf-8')
            print(f"📱 Device ID: {device_id}")
            self.current_device_id = device_id
        except Exception as e:
            print(f"❌ Failed to receive device_id: {e}")
            return
        
        data = b""
        payload_size = struct.calcsize("Q")  # Changed from "L" to "Q"
        self.start_time = time.time()
        
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
                    import numpy as np
                    nparr = np.frombuffer(frame_data, np.uint8)
                    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
                    
                    if frame is None:
                        raise ValueError("Failed to decode JPEG frame")
                        
                    print(f"✅ Frame decoded! Shape: {frame.shape}")
                except Exception as e:
                    print(f"❌ Decode error: {e}")
                    print(f"   Received {len(frame_data)} bytes")
                    print(f"   First 20 bytes: {frame_data[:20]}")
                    raise
                
                # Process frame
                self.process_single_frame(frame)
                
        except KeyboardInterrupt:
            raise
        except ConnectionError as e:
            print(f"\n❌ {e}")
        except Exception as e:
            print(f"\n❌ Processing error: {e}")
            import traceback
            traceback.print_exc()
    
    def process_single_frame(self, frame):
        """Process a single frame - run detection and tracking"""
        
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
                # Add brand info to event
                event['detected_brand'] = detected_brand
                self.firebase_sender.send_event(event)
        
        # Draw display
        display_start = time.time()
        if self.show_display:
            self.direction_detector.draw_boundary(frame)
            
            for obj_id, obj_data in objects.items():
                centroid = obj_data['centroid']
                label = obj_data['label']
                cv2.circle(frame, centroid, 4, (255, 0, 0), -1)
                cv2.putText(frame, f"ID:{obj_id}", 
                        (centroid[0]-10, centroid[1]-10),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (255, 0, 0), 2)
            
            elapsed = time.time() - self.start_time
            fps = self.frame_count / elapsed if elapsed > 0 else 0
            cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)
            
            cv2.putText(frame, f"Events: {self.total_events}", (10, 70),
                    cv2.FONT_HERSHEY_SIMPLEX, 1, (0, 255, 255), 2)
            
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
        
        def print_stats(self):
            """Print final statistics"""
            if self.start_time:
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