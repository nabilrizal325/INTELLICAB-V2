# calibration_server.py (UPDATED FOR JPEG)
import cv2
import socket
import struct
import json
import numpy as np

def draw_boundary(frame):
    """Interactive boundary drawing"""
    clone = frame.copy()
    points = []
    
    def mouse_callback(event, x, y, flags, param):
        nonlocal points, clone
        
        if event == cv2.EVENT_LBUTTONDOWN:
            points = [(x, y)]
            clone = frame.copy()
            cv2.circle(clone, (x, y), 5, (0, 255, 0), -1)
            cv2.imshow('Calibration', clone)
            
        elif event == cv2.EVENT_MOUSEMOVE and len(points) == 1:
            temp = clone.copy()
            cv2.line(temp, points[0], (x, y), (0, 255, 255), 2)
            cv2.imshow('Calibration', temp)
            
        elif event == cv2.EVENT_LBUTTONUP:
            if len(points) == 1:
                points.append((x, y))
                cv2.line(clone, points[0], points[1], (0, 255, 255), 3)
                cv2.putText(clone, "Press 's' to save, 'r' to redraw", 
                           (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 
                           0.7, (0, 255, 0), 2)
                cv2.imshow('Calibration', clone)
    
    cv2.namedWindow('Calibration')
    cv2.setMouseCallback('Calibration', mouse_callback)
    cv2.imshow('Calibration', frame)
    
    print("\n📏 DRAW BOUNDARY LINE:")
    print("  1. Click and drag across the cabinet opening")
    print("  2. Press 's' to SAVE")
    print("  3. Press 'r' to REDRAW")
    print("  4. Press 'q' to QUIT\n")
    
    while True:
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord('s') and len(points) == 2:
            cv2.destroyAllWindows()
            return points
            
        elif key == ord('r'):
            points = []
            clone = frame.copy()
            cv2.imshow('Calibration', clone)
            
        elif key == ord('q'):
            cv2.destroyAllWindows()
            return None

# Start server
server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1024*1024)
server_socket.bind(('0.0.0.0', 8485))
server_socket.listen(5)

print("="*60)
print("📏 CALIBRATION SERVER")
print("="*60)
print("\n⏳ Waiting for Pi to connect...")
print("   Run on Pi: python3 pi_camera_client.py --server=YOUR_IP --calibrate\n")

try:
    conn, addr = server_socket.accept()
    print(f"✅ Connected to {addr}")
    print("\n📸 Receiving frame from Pi camera...")
    
    # Receive frame size (8 bytes for Q format)
    data = b""
    payload_size = struct.calcsize("Q")
    
    print(f"📦 Waiting for frame size ({payload_size} bytes)...")
    
    while len(data) < payload_size:
        packet = conn.recv(4096)
        if not packet:
            raise ConnectionError("Connection closed while receiving size")
        data += packet
    
    packed_msg_size = data[:payload_size]
    data = data[payload_size:]
    msg_size = struct.unpack("Q", packed_msg_size)[0]
    
    print(f"📦 Frame size: {msg_size} bytes ({msg_size/1024:.1f} KB)")
    print(f"📥 Receiving frame data...")
    
    # Receive frame data
    received = len(data)
    while len(data) < msg_size:
        packet = conn.recv(4096)
        if not packet:
            raise ConnectionError("Connection closed while receiving data")
        data += packet
        
        # Print progress every 100KB
        if len(data) - received >= 100*1024:
            received = len(data)
            progress = (len(data) / msg_size) * 100
            print(f"📥 Progress: {progress:.1f}% ({len(data)/1024:.0f}/{msg_size/1024:.0f} KB)")
    
    frame_data = data[:msg_size]
    
    print("✅ Frame data received!")
    print("🔄 Decoding JPEG frame...")
    
    # Decode JPEG
    try:
        nparr = np.frombuffer(frame_data, np.uint8)
        frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if frame is None:
            raise ValueError("cv2.imdecode returned None - invalid JPEG data")
        
        print(f"✅ Frame decoded! Shape: {frame.shape}")
    except Exception as e:
        print(f"❌ Decoding error: {e}")
        print(f"   Received {len(frame_data)} bytes")
        print(f"   First 50 bytes: {frame_data[:50]}")
        raise
    
    # Draw boundary
    boundary = draw_boundary(frame)
    
    if boundary:
        # Save to file
        with open('boundary.json', 'w') as f:
            json.dump({'boundary': boundary}, f)
        print(f"\n✅ Boundary saved to boundary.json")
        print(f"   Points: {boundary}")
        print("\nYou can now run the detection server!")
    else:
        print("\n❌ Calibration cancelled")

except KeyboardInterrupt:
    print("\n⏹️  Calibration cancelled by user")
except Exception as e:
    print(f"\n❌ Error: {e}")
    import traceback
    traceback.print_exc()
finally:
    try:
        conn.close()
    except:
        pass
    server_socket.close()
    cv2.destroyAllWindows()
    print("\n👋 Calibration server stopped")