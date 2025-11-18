# pi_camera_client.py (COMPLETE JPEG VERSION)
import cv2
import socket
import struct
import time
import argparse
from picamera2 import Picamera2

class CameraClient:
    def __init__(self, server_ip, server_port, resolution=(640, 480), calibration_mode=False):
        self.server_ip = server_ip
        self.server_port = server_port
        self.resolution = resolution
        self.calibration_mode = calibration_mode
        
        print("="*60)
        if calibration_mode:
            print("📏 RASPBERRY PI CAMERA CLIENT - CALIBRATION MODE")
        else:
            print("📹 RASPBERRY PI CAMERA CLIENT")
        print("="*60)
        
        # Initialize camera
        print(f"\n📷 Initializing camera at {resolution[0]}x{resolution[1]}...")
        self.camera = Picamera2()
        config = self.camera.create_video_configuration(
            main={"format": 'XRGB8888', "size": resolution}
        )
        self.camera.configure(config)
        self.camera.start()
        time.sleep(2)
        print("✅ Camera ready")
        
        # Stats
        self.frame_count = 0
        self.start_time = None
        
    def connect_to_server(self):
        """Connect to cloud server"""
        print(f"\n🔌 Connecting to server at {self.server_ip}:{self.server_port}...")
        
        self.client_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.client_socket.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 1024*1024)
        
        try:
            self.client_socket.connect((self.server_ip, self.server_port))
            print("✅ Connected to cloud server!")
            return True
        except Exception as e:
            print(f"❌ Connection failed: {e}")
            print("\nTroubleshooting:")
            print("  1. Make sure cloud server is running")
            print("  2. Check both devices are on same network")
            print(f"  3. Verify server IP is correct: {self.server_ip}")
            print("  4. Check firewall settings")
            return False
    
    def send_calibration_frame(self):
        """Send a single frame for calibration"""
        print("\n📸 Capturing frame for calibration...")
        
        # Capture frame (BGRA format from XRGB8888)
        frame = self.camera.capture_array()
        
        # Convert BGRA to BGR (drop alpha channel)
        if frame.shape[2] == 4:
            frame_bgr = frame[:, :, :3]
        else:
            frame_bgr = frame
        
        # Encode as JPEG
        print("🔄 Encoding frame as JPEG...")
        encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 90]
        success, buffer = cv2.imencode('.jpg', frame_bgr, encode_param)
        
        if not success:
            print("❌ Failed to encode frame as JPEG")
            return
        
        data = buffer.tobytes()
        
        print(f"📦 JPEG size: {len(data)} bytes ({len(data)/1024:.1f} KB)")
        print("📤 Sending frame to server...")
        
        try:
            # Send size first
            self.client_socket.sendall(struct.pack("Q", len(data)))
            # Then send data
            self.client_socket.sendall(data)
            print("✅ Frame sent successfully!")
            
            # Wait for server to process
            print("⏳ Waiting for server to finish calibration...")
            time.sleep(2)
            
        except Exception as e:
            print(f"❌ Send error: {e}")
    
    def stream_frames(self):
        """Capture and send frames to server"""
        print(f"\n{'='*60}")
        print("🎥 STREAMING STARTED (JPEG MODE)")
        print(f"{'='*60}\n")
        
        self.start_time = time.time()
        
        try:
            while True:
                # Capture frame (BGRA format from XRGB8888)
                frame = self.camera.capture_array()
                
                # Validate frame
                if frame is None or frame.size == 0:
                    print("⚠️  Camera returned empty frame")
                    continue
                
                # Convert BGRA to BGR (drop alpha channel)
                if frame.shape[2] == 4:
                    frame_bgr = frame[:, :, :3]
                else:
                    frame_bgr = frame
                
                # Encode as JPEG
                encode_param = [int(cv2.IMWRITE_JPEG_QUALITY), 85]  # 85% quality for speed
                success, buffer = cv2.imencode('.jpg', frame_bgr, encode_param)
                
                if not success:
                    print("⚠️  JPEG encoding failed, skipping frame")
                    continue
                
                data = buffer.tobytes()
                message_size = struct.pack("Q", len(data))
                
                # Send frame
                try:
                    self.client_socket.sendall(message_size + data)
                except BrokenPipeError:
                    print("\n❌ Connection lost to server")
                    break
                except Exception as e:
                    print(f"\n❌ Send error: {e}")
                    break
                
                # Calculate and print FPS
                self.frame_count += 1
                if self.frame_count % 30 == 0:
                    elapsed = time.time() - self.start_time
                    fps = self.frame_count / elapsed
                    print(f"📹 Streaming at {fps:.2f} FPS | Frames: {self.frame_count} | JPEG size: {len(data)/1024:.1f} KB")
        
        except KeyboardInterrupt:
            print("\n⏹️  Streaming stopped by user")
        except Exception as e:
            print(f"\n❌ Streaming error: {e}")
            import traceback
            traceback.print_exc()
        finally:
            self.cleanup()
    
    def cleanup(self):
        """Clean up resources"""
        print("\n🧹 Cleaning up...")
        try:
            self.client_socket.close()
        except:
            pass
        self.camera.stop()
        
        if self.start_time:
            elapsed = time.time() - self.start_time
            fps = self.frame_count / elapsed if elapsed > 0 else 0
            print(f"\n📊 Streamed {self.frame_count} frames in {elapsed:.1f}s ({fps:.2f} FPS)")
        
        print("👋 Client stopped")
    
    def run(self):
        """Main run method"""
        if self.connect_to_server():
            if self.calibration_mode:
                self.send_calibration_frame()
                time.sleep(1)
                self.cleanup()
            else:
                self.stream_frames()


def main():
    parser = argparse.ArgumentParser(description='Pi Camera Client')
    parser.add_argument('--server', required=True,
                       help='Cloud server IP address')
    parser.add_argument('--port', type=int, default=8485,
                       help='Server port')
    parser.add_argument('--resolution', default='640x480',
                       help='Camera resolution (e.g., 640x480, 1280x720)')
    parser.add_argument('--calibrate', action='store_true',
                       help='Calibration mode - send one frame only')
    
    args = parser.parse_args()
    
    # Parse resolution
    width, height = map(int, args.resolution.split('x'))
    
    # Create and run client
    client = CameraClient(
        server_ip=args.server,
        server_port=args.port,
        resolution=(width, height),
        calibration_mode=args.calibrate
    )
    
    client.run()


if __name__ == '__main__':
    main()
