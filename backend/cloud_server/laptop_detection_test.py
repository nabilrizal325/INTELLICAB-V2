import cv2
import torch
import numpy as np
from ultralytics import YOLO
from centroid_tracker import CentroidTracker
from direction_detector import DirectionDetector
from firebase_sender import FirebaseSender
import time
import argparse

class LaptopDetectionTest:
    def __init__(self, model_path, firebase_creds, device_id="laptop_test"):
        print("="*60)
        print("💻 LAPTOP CAMERA DETECTION TEST")
        print("="*60)
        
        self.device_id = device_id
        
        # GPU Detection
        self.device = 'cuda' if torch.cuda.is_available() else 'cpu'
        print(f"\n🎮 Using: {self.device.upper()}")
        
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            gpu_memory = torch.cuda.get_device_properties(0).total_memory / 1024**3
            print(f"   GPU: {gpu_name}")
            print(f"   VRAM: {gpu_memory:.1f} GB")
            
            # Enable GPU optimizations
            torch.backends.cudnn.benchmark = True
            print(f"   ✅ CuDNN benchmark enabled")
        
        # Load YOLO model
        print(f"\n📦 Loading YOLO model: {model_path}")
        self.model = YOLO(model_path)
        self.model.to(self.device)
        print(f"✅ Model loaded!")
        
        # GPU Warm-up
        if self.device == 'cuda':
            print(f"\n🔥 Warming up GPU...")
            dummy_frame = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)
            for _ in range(5):
                _ = self.model(dummy_frame, device=self.device, half=True, verbose=False)
            torch.cuda.synchronize()
            print(f"✅ GPU warmed up!")
        
        # Initialize tracking
        self.tracker = CentroidTracker(maxDisappeared=30)
        self.direction_detector = DirectionDetector()
        
        # Initialize Firebase
        print(f"\n🔥 Connecting to Firebase...")
        try:
            self.firebase_sender = FirebaseSender(firebase_creds)
            from firebase_admin import firestore
            self.db = firestore.client()
        except Exception as e:
            print(f"⚠️ Firebase not initialized: {e}")
            self.firebase_sender = None
            self.db = None
        
        # Load boundary from Firebase
        self._load_boundary()
        
        # Initialize webcam
        print(f"\n📷 Opening camera...")
        # Allow passing camera index and resolution
        self.camera_index = getattr(self, 'camera_index', 0)
        self.cap = cv2.VideoCapture(self.camera_index)
        
        if not self.cap.isOpened():
            raise Exception(f"❌ Cannot open camera {self.camera_index}!")
        
        # Set resolution
        width, height = getattr(self, 'resolution', (640, 480))
        self.cap.set(cv2.CAP_PROP_FRAME_WIDTH, width)
        self.cap.set(cv2.CAP_PROP_FRAME_HEIGHT, height)
        
        print("✅ Camera ready!")
        
        # Stats
        self.frame_count = 0
        self.start_time = time.time()
        self.total_events = 0
        self.paused = False
        
        # Get actual camera resolution
        actual_width = int(self.cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        actual_height = int(self.cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        print(f"   Resolution: {actual_width}x{actual_height}")
    
    def _load_boundary(self):
        """Load boundary from Firebase"""
        if not self.db:
            print("⚠️ No Firebase - using default boundary")
            # Default boundary: horizontal line across middle
            self.direction_detector.set_boundary([(50, 240), (590, 240)])
            return
        
        try:
            device_doc = self.db.collection('devices').document(self.device_id).get()
            if device_doc.exists:
                boundary = device_doc.to_dict().get('boundary')
                if boundary:
                    points = [
                        (boundary['x1'], boundary['y1']),
                        (boundary['x2'], boundary['y2'])
                    ]
                    self.direction_detector.set_boundary(points)
                    print(f"\n✅ Loaded boundary from Firebase:")
                    print(f"   ({boundary['x1']},{boundary['y1']}) -> ({boundary['x2']},{boundary['y2']})")
                else:
                    print("⚠️ No boundary in Firebase - using default")
                    self.direction_detector.set_boundary([(50, 240), (590, 240)])
            else:
                print("⚠️ Device not in Firebase - using default boundary")
                self.direction_detector.set_boundary([(50, 240), (590, 240)])
        except Exception as e:
            print(f"⚠️ Error loading boundary: {e}")
            self.direction_detector.set_boundary([(50, 240), (590, 240)])
    
    def run(self):
        """Main detection loop"""
        print(f"\n{'='*60}")
        print("🚀 DETECTION STARTED")
        print("Controls:")
        print("  'q' - Quit")
        print("  'c' - Calibrate boundary")
        print("  'p' - Pause/Resume")
        print("  'h' - Toggle help overlay")
        print(f"{'='*60}\n")
        
        try:
            while True:
                ret, frame = self.cap.read()
                if not ret:
                    print("❌ Failed to read frame")
                    break
                
                # Process frame (skip if paused)
                if not self.paused:
                    self._process_frame(frame)
                else:
                    # Draw PAUSED overlay
                    overlay = frame.copy()
                    cv2.rectangle(overlay, (200, 200), (440, 280), (0, 0, 255), -1)
                    cv2.addWeighted(overlay, 0.7, frame, 0.3, 0, frame)
                    cv2.putText(frame, "PAUSED", (220, 250),
                               cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 255, 255), 3)
                
                # Show frame
                cv2.imshow('Laptop Detection Test', frame)
                
                # Handle keyboard
                key = cv2.waitKey(1) & 0xFF
                if key == ord('q'):
                    break
                elif key == ord('c'):
                    self._calibrate_boundary(frame)
                elif key == ord('p'):
                    self.paused = not self.paused
                    status = "PAUSED" if self.paused else "RESUMED"
                    print(f"\n⏸️  {status}")
        
        except KeyboardInterrupt:
            print("\n⏹️ Stopped by user")
        
        finally:
            self.cap.release()
            cv2.destroyAllWindows()
            self._print_stats()
    
    def _process_frame(self, frame):
        """Process a single frame"""
        detect_start = time.time()
        
        # YOLO detection
        results = self.model(
            frame,
            imgsz=416,
            conf=0.25,
            iou=0.45,
            half=True if self.device == 'cuda' else False,
            device=self.device,
            verbose=False,
        )
        detect_time = (time.time() - detect_start) * 1000
        
        # Extract detections
        boxes = []
        labels = []
        raw_detections = []
        
        for result in results:
            for box in result.boxes:
                x1, y1, x2, y2 = box.xyxy[0].cpu().numpy()
                cls = int(box.cls[0])
                conf = float(box.conf[0])
                label = self.model.names[cls]
                
                if conf > 0.5:  # Filter low confidence
                    boxes.append([x1, y1, x2, y2])
                    labels.append(label)

                    # ⭐ Store detection with box coordinates and confidence
                    raw_detections.append({
                        'box': (int(x1), int(y1), int(x2), int(y2)),
                        'label': label,
                        'confidence': conf
                    })
            
        # Update tracker
        objects = self.tracker.update(boxes, labels)
        events = self.direction_detector.update(objects)
        
        # Handle events with brand extraction
        for event in events:
            self.total_events += 1
            
            # Extract brand from label
            detected_brand = self._extract_brand(event['label'])
            brand_info = f" (brand: {detected_brand})" if detected_brand else ""
            print(f"\n🔔 EVENT #{self.total_events}: {event['label']} moved {event['direction']}{brand_info}")
            
            if self.firebase_sender:
                event['device_id'] = self.device_id
                event['detected_brand'] = detected_brand
                self.firebase_sender.send_event(event)
        
        # ⭐ Draw bounding boxes FIRST (so they appear behind other drawings)
        for detection in raw_detections:
            x1, y1, x2, y2 = detection['box']
            label = detection['label']
            conf = detection['confidence']
            
            # Draw bounding box (green rectangle)
            cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)
            
            # Draw label background (filled rectangle for better visibility)
            label_text = f"{label} {conf:.2f}"
            (text_width, text_height), _ = cv2.getTextSize(
                label_text, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 2
            )
            cv2.rectangle(
                frame, 
                (x1, y1 - text_height - 10), 
                (x1 + text_width, y1), 
                (0, 255, 0), 
                -1  # Filled rectangle
            )

            # Draw label text (black text on green background)
            cv2.putText(
                frame, 
                label_text,
                (x1, y1 - 5),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.6,
                (0, 0, 0),  # Black text
                2
            )

        # Draw boundary (red line)
        self.direction_detector.draw_boundary(frame)
        
        # ⭐ Draw tracking info (centroids and IDs)
        for obj_id, obj_data in objects.items():
            centroid = obj_data['centroid']
            label = obj_data['label']
            
            # Draw centroid (yellow circle - different from box color)
            cv2.circle(frame, (int(centroid[0]), int(centroid[1])), 5, (0, 255, 255), -1)
            
            # Draw tracking ID (cyan text near centroid)
            cv2.putText(
                frame, 
                f"ID:{obj_id}", 
                (int(centroid[0]) + 10, int(centroid[1]) + 5),
                cv2.FONT_HERSHEY_SIMPLEX, 
                0.5, 
                (255, 255, 0),  # Cyan
                2
            )
        
        # Display stats (top-left corner with semi-transparent background)
        self.frame_count += 1
        elapsed = time.time() - self.start_time
        fps = self.frame_count / elapsed if elapsed > 0 else 0
        
        # Draw semi-transparent background for stats
        overlay = frame.copy()
        cv2.rectangle(overlay, (5, 5), (300, 150), (0, 0, 0), -1)
        cv2.addWeighted(overlay, 0.5, frame, 0.5, 0, frame)
        
        # Draw stats text
        cv2.putText(frame, f"FPS: {fps:.1f}", (10, 30),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
        cv2.putText(frame, f"Events: {self.total_events}", (10, 60),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 255), 2)
        cv2.putText(frame, f"Detection: {detect_time:.1f}ms", (10, 90),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2)
        cv2.putText(frame, f"Objects: {len(raw_detections)}", (10, 120),
                   cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 0), 2)
    
    def _calibrate_boundary(self, frame):
        """Interactive boundary drawing"""
        print("\n📏 CALIBRATION MODE")
        print("   Click and drag to draw boundary line")
        print("   Press 's' to save, 'c' to cancel")
        
        clone = frame.copy()
        points = []
        
        def mouse_callback(event, x, y, flags, param):
            if event == cv2.EVENT_LBUTTONDOWN:
                points.clear()
                points.append((x, y))
            elif event == cv2.EVENT_MOUSEMOVE and flags == cv2.EVENT_FLAG_LBUTTON:
                temp = clone.copy()
                if len(points) > 0:
                    cv2.line(temp, points[0], (x, y), (0, 0, 255), 3)
                cv2.imshow('Calibration', temp)
            elif event == cv2.EVENT_LBUTTONUP:
                if len(points) > 0:
                    points.append((x, y))
        
        cv2.namedWindow('Calibration')
        cv2.setMouseCallback('Calibration', mouse_callback)
        cv2.imshow('Calibration', clone)
        
        while True:
            key = cv2.waitKey(1) & 0xFF
            if key == ord('s') and len(points) == 2:
                self.direction_detector.set_boundary(points)
                print(f"✅ Boundary saved: {points[0]} -> {points[1]}")
                
                # Save to Firebase
                if self.db:
                    try:
                        self.db.collection('devices').document(self.device_id).set({
                            'boundary': {
                                'x1': points[0][0],
                                'y1': points[0][1],
                                'x2': points[1][0],
                                'y2': points[1][1],
                            }
                        }, merge=True)
                        print("✅ Boundary saved to Firebase")
                    except Exception as e:
                        print(f"⚠️ Failed to save to Firebase: {e}")
                break
            elif key == ord('c'):
                print("❌ Calibration cancelled")
                break
        
        cv2.destroyWindow('Calibration')
    
    def _extract_brand(self, item_name):
        """Extract brand from YOLO class name"""
        brand_keywords = [
            'coca_cola', 'coke', 'pepsi', 'sprite', 'fanta', 'mountain_dew',
            'redbull', 'monster', 'gatorade', 'powerade', 'mister_potato',
            'maggi', 'indomie', 'mamee', 'twisties', 'pringles',
            'lays', 'doritos', 'cheetos', 'kitkat', 'snickers'
        ]
        
        item_lower = item_name.lower().replace(' ', '_')
        
        for keyword in brand_keywords:
            if keyword in item_lower:
                return keyword.replace('_', ' ')
        
        return None
    
    def _print_stats(self):
        """Print final statistics"""
        elapsed = time.time() - self.start_time
        fps = self.frame_count / elapsed if elapsed > 0 else 0
        
        print(f"\n{'='*60}")
        print("📊 SESSION STATISTICS")
        print(f"{'='*60}")
        print(f"Total frames: {self.frame_count}")
        print(f"Total time: {elapsed:.1f}s")
        print(f"Average FPS: {fps:.1f}")
        print(f"Total events: {self.total_events}")
        print(f"{'='*60}\n")

def main():
    parser = argparse.ArgumentParser(
        description='Laptop Camera Detection Test',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python laptop_detection_test.py
  python laptop_detection_test.py --camera 1 --resolution 1280x720
  python laptop_detection_test.py --device-id kitchen_camera --no-firebase
        """
    )
    parser.add_argument('--model', default='my_model.pt', help='YOLO model path')
    parser.add_argument('--firebase-creds', default='firebase-credentials.json',
                       help='Firebase credentials')
    parser.add_argument('--device-id', default='laptop_test',
                       help='Device ID for Firebase logging')
    parser.add_argument('--camera', type=int, default=0,
                       help='Camera index (0=default, 1=external, etc.)')
    parser.add_argument('--resolution', type=str, default='640x480',
                       help='Camera resolution (e.g., 1280x720, 1920x1080)')
    parser.add_argument('--no-firebase', action='store_true',
                       help='Run without Firebase (offline mode)')
    
    args = parser.parse_args()
    
    # Parse resolution
    try:
        width, height = map(int, args.resolution.split('x'))
    except:
        print(f"⚠️ Invalid resolution format: {args.resolution}, using 640x480")
        width, height = 640, 480
    
    # Create detector
    firebase_creds = None if args.no_firebase else args.firebase_creds
    detector = LaptopDetectionTest(
        model_path=args.model,
        firebase_creds=firebase_creds,
        device_id=args.device_id
    )
    
    # Set camera options
    detector.camera_index = args.camera
    detector.resolution = (width, height)
    
    detector.run()

if __name__ == '__main__':
    main()