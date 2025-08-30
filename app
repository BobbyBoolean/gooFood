from flask import Flask, request, jsonify, render_template_string
from flask_cors import CORS
import requests
import os
from typing import List, Dict, Any
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app)

# Google Places API configuration
GOOGLE_PLACES_API_KEY = os.getenv('AIzaSyAc71U59IynG6tjwS3kJWT76fwMIrStJpI')
PLACES_API_URL = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json'

class RestaurantFinder:
    def __init__(self, api_key: str):
        self.api_key = api_key
    
    def find_restaurants(self, latitude: float, longitude: float, radius: int = 1000) -> List[Dict[Any, Any]]:
        """
        Find restaurants near the given coordinates using Google Places API
        
        Args:
            latitude: Latitude coordinate
            longitude: Longitude coordinate
            radius: Search radius in meters (default: 1000m = 1km)
        
        Returns:
            List of restaurant data sorted by rating
        """
        if not self.api_key:
            raise ValueError("Google Places API key not configured")
        
        params = {
            'location': f'{latitude},{longitude}',
            'radius': radius,
            'type': 'restaurant',
            'key': self.api_key
        }
        
        try:
            logger.info(f"Searching for restaurants at ({latitude}, {longitude}) within {radius}m")
            response = requests.get(PLACES_API_URL, params=params, timeout=10)
            response.raise_for_status()
            
            data = response.json()
            
            if data.get('status') == 'REQUEST_DENIED':
                raise ValueError(f"API request denied: {data.get('error_message', 'Invalid API key or quota exceeded')}")
            
            if data.get('status') not in ['OK', 'ZERO_RESULTS']:
                raise ValueError(f"API error: {data.get('status')} - {data.get('error_message', 'Unknown error')}")
            
            restaurants = data.get('results', [])
            
            # Filter out places without ratings and sort by rating (descending)
            valid_restaurants = [r for r in restaurants if r.get('rating') is not None]
            sorted_restaurants = sorted(valid_restaurants, key=lambda x: x.get('rating', 0), reverse=True)
            
            # Return top 10 restaurants
            top_restaurants = sorted_restaurants[:10]
            
            logger.info(f"Found {len(top_restaurants)} restaurants")
            return top_restaurants
            
        except requests.RequestException as e:
            logger.error(f"Request error: {e}")
            raise ValueError(f"Failed to fetch restaurant data: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error: {e}")
            raise ValueError(f"An unexpected error occurred: {str(e)}")

# Initialize restaurant finder
restaurant_finder = RestaurantFinder(GOOGLE_PLACES_API_KEY)

# Add debug logging for all requests
@app.before_request
def log_request():
    logger.info(f"Request: {request.method} {request.path}")
    if request.is_json:
        logger.info(f"JSON data: {request.get_json()}")

@app.route('/')
def index():
    """Serve the main page"""
    try:
        with open('index.html', 'r') as f:
            return f.read()
    except FileNotFoundError:
        # Fallback if index.html is not found
        return '''
        <!DOCTYPE html>
        <html>
        <head>
            <title>Restaurant Finder</title>
        </head>
        <body>
            <h1>Restaurant Finder API</h1>
            <p>The frontend files (index.html, style.css, script.js) should be in the same directory as this app.py file.</p>
            <p>API endpoint: POST /api/restaurants</p>
        </body>
        </html>
        '''

@app.route('/api/restaurants', methods=['POST'])
def get_restaurants():
    """
    API endpoint to get restaurants near a location
    
    Expected JSON payload:
    {
        "latitude": float,
        "longitude": float
    }
    """
    try:
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        latitude = data.get('latitude')
        longitude = data.get('longitude')
        
        # Validate coordinates
        if latitude is None or longitude is None:
            return jsonify({'error': 'Missing latitude or longitude'}), 400
        
        try:
            latitude = float(latitude)
            longitude = float(longitude)
        except (ValueError, TypeError):
            return jsonify({'error': 'Invalid latitude or longitude format'}), 400
        
        # Validate coordinate ranges
        if not (-90 <= latitude <= 90):
            return jsonify({'error': 'Latitude must be between -90 and 90'}), 400
        
        if not (-180 <= longitude <= 180):
            return jsonify({'error': 'Longitude must be between -180 and 180'}), 400
        
        # Find restaurants
        restaurants = restaurant_finder.find_restaurants(latitude, longitude)
        
        return jsonify({
            'success': True,
            'restaurants': restaurants,
            'count': len(restaurants)
        })
        
    except ValueError as e:
        logger.error(f"ValueError in get_restaurants: {e}")
        return jsonify({'error': str(e)}), 400
    except Exception as e:
        logger.error(f"Unexpected error in get_restaurants: {e}")
        return jsonify({'error': 'An internal server error occurred'}), 500

@app.route('/health')
def health_check():
    """Health check endpoint"""
    api_configured = bool(GOOGLE_PLACES_API_KEY)
    return jsonify({
        'status': 'healthy',
        'api_key_configured': api_configured
    })

@app.route('/test', methods=['GET'])
def test_endpoint():
    """Test endpoint to verify server is working"""
    return jsonify({
        'message': 'Server is working!',
        'method': request.method,
        'available_endpoints': [
            'GET /',
            'POST /api/restaurants',
            'GET /health',
            'GET /test'
        ]
    })

@app.errorhandler(404)
def not_found(error):
    logger.error(f"404 error: {request.method} {request.path}")
    return jsonify({'error': 'Endpoint not found'}), 404

@app.errorhandler(405)
def method_not_allowed(error):
    logger.error(f"405 error: {request.method} {request.path}")
    return jsonify({
        'error': f'Method {request.method} not allowed for {request.path}',
        'allowed_methods': ['POST'] if request.path == '/api/restaurants' else ['GET']
    }), 405

@app.errorhandler(500)
def internal_error(error):
    return jsonify({'error': 'Internal server error'}), 500

if __name__ == '__main__':
    if not GOOGLE_PLACES_API_KEY:
        print("WARNING: GOOGLE_PLACES_API_KEY environment variable not set!")
        print("Please set your Google Places API key:")
        print("export GOOGLE_PLACES_API_KEY='your_api_key_here'")
        print("\nThe app will still start, but restaurant searches will fail.")
    
    print("Starting Restaurant Finder server...")
    print("Make sure index.html is in the same directory as app.py")
    app.run(debug=True, host='0.0.0.0', port=5000)
