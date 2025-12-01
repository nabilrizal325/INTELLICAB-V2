# direction_detector.py
import json
import time
import cv2

class DirectionDetector:
    def __init__(self):
        self.boundary = None
        self.prev_positions = {}
        self.crossed_objects = set()
        
    def set_boundary(self, points):
        """Set boundary line from two points [(x1,y1), (x2,y2)]"""
        self.boundary = points
        
    def save_boundary(self, filename='boundary.json'):
        """Save boundary to file"""
        if self.boundary:
            with open(filename, 'w') as f:
                json.dump({'boundary': self.boundary}, f)
                
    def load_boundary(self, filename='boundary.json'):
        """Load boundary from file"""
        with open(filename, 'r') as f:
            data = json.load(f)
            self.boundary = data['boundary']
            
    def get_side(self, point):
        """Determine which side of boundary line the point is on"""
        if not self.boundary:
            return None
            
        (x1, y1), (x2, y2) = self.boundary
        px, py = point
        
        # Calculate cross product
        d = (px - x1) * (y2 - y1) - (py - y1) * (x2 - x1)
        
        if d > 0:
            return 'IN'
        elif d < 0:
            return 'OUT'
        else:
            return None
            
    def update(self, objects):
        """Update tracking and detect boundary crossings"""
        events = []
        
        if not self.boundary:
            return events
            
        current_ids = set(objects.keys())
        
        for obj_id, obj_data in objects.items():
            centroid = obj_data['centroid']
            label = obj_data['label']
            current_side = self.get_side(centroid)
            
            if obj_id in self.prev_positions:
                prev_side = self.prev_positions[obj_id]['side']
                
                # Detect crossing
                if prev_side and current_side and prev_side != current_side:
                    if obj_id not in self.crossed_objects:
                        # Object crossed boundary
                        event = {
                            'object_id': obj_id,
                            'label': label,
                            'direction': current_side,
                            'timestamp': time.time(),
                            'centroid': centroid
                        }
                        events.append(event)
                        self.crossed_objects.add(obj_id)
            
            self.prev_positions[obj_id] = {
                'centroid': centroid,
                'side': current_side,
                'label': label
            }
        
        # Clean up disappeared objects
        disappeared = set(self.prev_positions.keys()) - current_ids
        for obj_id in disappeared:
            del self.prev_positions[obj_id]
            self.crossed_objects.discard(obj_id)
            
        return events
        
    def draw_boundary(self, frame):
        """Draw boundary line on frame"""
        if self.boundary:
            (x1, y1), (x2, y2) = self.boundary
            # Ensure coordinates are integers for OpenCV
            x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)
            cv2.line(frame, (x1, y1), (x2, y2), (0, 255, 255), 3)
            cv2.putText(frame, "BOUNDARY", (x1, y1-10),
                       cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 255), 2)