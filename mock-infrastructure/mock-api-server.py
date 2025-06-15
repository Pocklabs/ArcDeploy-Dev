#!/usr/bin/env python3

"""
Mock API Server for ArcDeploy Testing
Simulates cloud provider API responses for comprehensive testing scenarios
"""

import json
import time
import random
import argparse
import threading
from datetime import datetime, timedelta
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import logging
import os
import sys

# ============================================================================
# Configuration
# ============================================================================

class MockAPIConfig:
    def __init__(self):
        self.port = 8888
        self.host = '127.0.0.1'
        self.response_delay_min = 0.1
        self.response_delay_max = 2.0
        self.failure_rate = 0.1  # 10% chance of failure
        self.rate_limit_requests = 100
        self.rate_limit_window = 3600  # 1 hour
        self.test_data_dir = os.path.join(os.path.dirname(__file__), '..', 'test-data')
        
    def from_env(self):
        """Load configuration from environment variables"""
        self.port = int(os.getenv('MOCK_API_PORT', self.port))
        self.host = os.getenv('MOCK_API_HOST', self.host)
        self.response_delay_min = float(os.getenv('MOCK_API_DELAY_MIN', self.response_delay_min))
        self.response_delay_max = float(os.getenv('MOCK_API_DELAY_MAX', self.response_delay_max))
        self.failure_rate = float(os.getenv('MOCK_API_FAILURE_RATE', self.failure_rate))
        return self

# ============================================================================
# Rate Limiting
# ============================================================================

class RateLimiter:
    def __init__(self, config):
        self.config = config
        self.requests = {}
        self.lock = threading.Lock()
    
    def is_rate_limited(self, client_ip):
        with self.lock:
            now = time.time()
            window_start = now - self.config.rate_limit_window
            
            if client_ip not in self.requests:
                self.requests[client_ip] = []
            
            # Clean old requests
            self.requests[client_ip] = [
                req_time for req_time in self.requests[client_ip] 
                if req_time > window_start
            ]
            
            # Check if rate limited
            if len(self.requests[client_ip]) >= self.config.rate_limit_requests:
                return True
            
            # Add current request
            self.requests[client_ip].append(now)
            return False
    
    def get_rate_limit_info(self, client_ip):
        with self.lock:
            current_count = len(self.requests.get(client_ip, []))
            remaining = max(0, self.config.rate_limit_requests - current_count)
            reset_time = int(time.time() + self.config.rate_limit_window)
            
            return {
                'limit': self.config.rate_limit_requests,
                'remaining': remaining,
                'reset': reset_time
            }

# ============================================================================
# Mock Response Generator
# ============================================================================

class MockResponseGenerator:
    def __init__(self, config):
        self.config = config
        self.load_test_data()
    
    def load_test_data(self):
        """Load test data from files"""
        self.responses = {}
        cloud_providers_dir = os.path.join(self.config.test_data_dir, 'cloud-providers')
        
        if not os.path.exists(cloud_providers_dir):
            logging.warning(f"Test data directory not found: {cloud_providers_dir}")
            return
        
        for provider in os.listdir(cloud_providers_dir):
            provider_dir = os.path.join(cloud_providers_dir, provider)
            if not os.path.isdir(provider_dir):
                continue
            
            self.responses[provider] = {}
            api_responses_dir = os.path.join(provider_dir, 'api-responses')
            
            if os.path.exists(api_responses_dir):
                for response_file in os.listdir(api_responses_dir):
                    if response_file.endswith('.json'):
                        response_name = response_file[:-5]  # Remove .json extension
                        file_path = os.path.join(api_responses_dir, response_file)
                        
                        try:
                            with open(file_path, 'r') as f:
                                self.responses[provider][response_name] = json.load(f)
                        except Exception as e:
                            logging.error(f"Failed to load response file {file_path}: {e}")
    
    def get_response(self, provider, scenario, **kwargs):
        """Get mock response for a specific provider and scenario"""
        if provider not in self.responses:
            return self.generate_error_response(404, "provider_not_found", f"Provider '{provider}' not supported")
        
        if scenario not in self.responses[provider]:
            return self.generate_error_response(404, "scenario_not_found", f"Scenario '{scenario}' not found for provider '{provider}'")
        
        response = self.responses[provider][scenario].copy()
        
        # Customize response with dynamic data
        response = self.customize_response(response, **kwargs)
        
        return response
    
    def customize_response(self, response, **kwargs):
        """Customize response with dynamic data"""
        # Update timestamps
        now = datetime.utcnow().isoformat() + '+00:00'
        self.update_timestamps(response, now)
        
        # Update request ID
        self.update_request_id(response)
        
        # Apply customizations from kwargs
        for key, value in kwargs.items():
            self.deep_update(response, key, value)
        
        return response
    
    def update_timestamps(self, obj, timestamp):
        """Recursively update timestamp fields"""
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key in ['timestamp', 'created', 'started', 'finished'] and value:
                    obj[key] = timestamp
                elif isinstance(value, (dict, list)):
                    self.update_timestamps(value, timestamp)
        elif isinstance(obj, list):
            for item in obj:
                self.update_timestamps(item, timestamp)
    
    def update_request_id(self, obj):
        """Update request ID with random value"""
        if isinstance(obj, dict):
            for key, value in obj.items():
                if key == 'request_id':
                    obj[key] = f"req_{random.randint(100000, 999999)}"
                elif isinstance(value, (dict, list)):
                    self.update_request_id(value)
        elif isinstance(obj, list):
            for item in obj:
                self.update_request_id(item)
    
    def deep_update(self, obj, key, value):
        """Deep update of nested dictionaries"""
        if isinstance(obj, dict):
            if key in obj:
                obj[key] = value
            for v in obj.values():
                if isinstance(v, (dict, list)):
                    self.deep_update(v, key, value)
        elif isinstance(obj, list):
            for item in obj:
                self.deep_update(item, key, value)
    
    def generate_error_response(self, status_code, error_code, message):
        """Generate standardized error response"""
        return {
            'error': {
                'code': error_code,
                'message': message,
                'status_code': status_code
            },
            'meta': {
                'request_id': f"req_error_{random.randint(100000, 999999)}",
                'timestamp': datetime.utcnow().isoformat() + '+00:00',
                'api_version': 'v1'
            }
        }

# ============================================================================
# HTTP Request Handler
# ============================================================================

class MockAPIHandler(BaseHTTPRequestHandler):
    def __init__(self, *args, config=None, rate_limiter=None, response_generator=None, **kwargs):
        self.config = config
        self.rate_limiter = rate_limiter
        self.response_generator = response_generator
        super().__init__(*args, **kwargs)
    
    def log_message(self, format, *args):
        """Override to use proper logging"""
        logging.info(f"{self.client_address[0]} - {format % args}")
    
    def do_GET(self):
        self.handle_request('GET')
    
    def do_POST(self):
        self.handle_request('POST')
    
    def do_PUT(self):
        self.handle_request('PUT')
    
    def do_DELETE(self):
        self.handle_request('DELETE')
    
    def handle_request(self, method):
        """Handle all HTTP requests"""
        client_ip = self.client_address[0]
        
        # Add artificial delay
        delay = random.uniform(self.config.response_delay_min, self.config.response_delay_max)
        time.sleep(delay)
        
        # Check rate limiting
        if self.rate_limiter.is_rate_limited(client_ip):
            self.send_rate_limit_response()
            return
        
        # Random failure simulation
        if random.random() < self.config.failure_rate:
            self.send_random_failure_response()
            return
        
        # Parse request
        url_parts = urlparse(self.path)
        path_parts = url_parts.path.strip('/').split('/')
        query_params = parse_qs(url_parts.query)
        
        # Route request
        try:
            if len(path_parts) >= 2:
                provider = path_parts[0]
                action = path_parts[1]
                
                response = self.route_request(provider, action, method, query_params)
                self.send_json_response(200, response)
            else:
                self.send_json_response(404, {
                    'error': 'Invalid API endpoint',
                    'message': 'Expected format: /{provider}/{action}'
                })
        
        except Exception as e:
            logging.error(f"Error handling request: {e}")
            self.send_json_response(500, {
                'error': 'Internal server error',
                'message': str(e)
            })
    
    def route_request(self, provider, action, method, query_params):
        """Route request to appropriate handler"""
        # Special endpoints for testing different scenarios
        if action == 'test-scenarios':
            return self.handle_test_scenarios(provider, query_params)
        
        # Default routing based on action
        scenario_map = {
            'servers': 'success-create-server',
            'instances': 'success-create-server',
            'droplets': 'success-create-server',
            'create-server': 'success-create-server',
            'list-servers': 'success-list-servers',
            'server-status': 'success-server-status'
        }
        
        scenario = scenario_map.get(action, 'success-create-server')
        
        # Check for specific test scenarios in query params
        if 'scenario' in query_params:
            scenario = query_params['scenario'][0]
        
        return self.response_generator.get_response(provider, scenario)
    
    def handle_test_scenarios(self, provider, query_params):
        """Handle test scenario requests"""
        available_scenarios = list(self.response_generator.responses.get(provider, {}).keys())
        return {
            'provider': provider,
            'available_scenarios': available_scenarios,
            'usage': f'Add ?scenario=<scenario_name> to test specific scenarios',
            'examples': [
                f'/{provider}/servers?scenario=rate-limit-exceeded',
                f'/{provider}/servers?scenario=quota-exceeded',
                f'/{provider}/servers?scenario=auth-failed'
            ]
        }
    
    def send_json_response(self, status_code, data):
        """Send JSON response with proper headers"""
        response_data = json.dumps(data, indent=2).encode('utf-8')
        
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(response_data)))
        
        # Add rate limit headers
        rate_info = self.rate_limiter.get_rate_limit_info(self.client_address[0])
        self.send_header('X-RateLimit-Limit', str(rate_info['limit']))
        self.send_header('X-RateLimit-Remaining', str(rate_info['remaining']))
        self.send_header('X-RateLimit-Reset', str(rate_info['reset']))
        
        # CORS headers for browser testing
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type, Authorization')
        
        self.end_headers()
        self.wfile.write(response_data)
    
    def send_rate_limit_response(self):
        """Send rate limit exceeded response"""
        response = self.response_generator.get_response('hetzner', 'rate-limit-exceeded')
        self.send_json_response(429, response)
    
    def send_random_failure_response(self):
        """Send random failure response"""
        failures = [
            (500, 'internal_server_error', 'Internal server error occurred'),
            (503, 'service_unavailable', 'Service temporarily unavailable'),
            (502, 'bad_gateway', 'Bad gateway error'),
            (504, 'gateway_timeout', 'Gateway timeout')
        ]
        
        status_code, error_code, message = random.choice(failures)
        response = self.response_generator.generate_error_response(status_code, error_code, message)
        self.send_json_response(status_code, response)

# ============================================================================
# Server Management
# ============================================================================

class MockAPIServer:
    def __init__(self, config):
        self.config = config
        self.rate_limiter = RateLimiter(config)
        self.response_generator = MockResponseGenerator(config)
        self.server = None
    
    def create_handler(self):
        """Create request handler with injected dependencies"""
        def handler(*args, **kwargs):
            return MockAPIHandler(
                *args,
                config=self.config,
                rate_limiter=self.rate_limiter,
                response_generator=self.response_generator,
                **kwargs
            )
        return handler
    
    def start(self):
        """Start the mock API server"""
        handler_class = self.create_handler()
        self.server = HTTPServer((self.config.host, self.config.port), handler_class)
        
        logging.info(f"Mock API Server starting on {self.config.host}:{self.config.port}")
        logging.info(f"Available providers: {list(self.response_generator.responses.keys())}")
        logging.info(f"Failure rate: {self.config.failure_rate * 100}%")
        logging.info(f"Response delay: {self.config.response_delay_min}-{self.config.response_delay_max}s")
        
        try:
            self.server.serve_forever()
        except KeyboardInterrupt:
            logging.info("Mock API Server shutting down...")
            self.server.shutdown()
            self.server.server_close()

# ============================================================================
# CLI Interface
# ============================================================================

def setup_logging(verbose=False):
    """Setup logging configuration"""
    level = logging.DEBUG if verbose else logging.INFO
    logging.basicConfig(
        level=level,
        format='%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )

def main():
    parser = argparse.ArgumentParser(description='Mock API Server for ArcDeploy Testing')
    parser.add_argument('--host', default='127.0.0.1', help='Host to bind to')
    parser.add_argument('--port', type=int, default=8888, help='Port to bind to')
    parser.add_argument('--failure-rate', type=float, default=0.1, help='Random failure rate (0.0-1.0)')
    parser.add_argument('--delay-min', type=float, default=0.1, help='Minimum response delay (seconds)')
    parser.add_argument('--delay-max', type=float, default=2.0, help='Maximum response delay (seconds)')
    parser.add_argument('--rate-limit', type=int, default=100, help='Rate limit (requests per hour)')
    parser.add_argument('--verbose', '-v', action='store_true', help='Enable verbose logging')
    parser.add_argument('--test-data-dir', help='Test data directory path')
    
    args = parser.parse_args()
    
    setup_logging(args.verbose)
    
    # Create configuration
    config = MockAPIConfig().from_env()
    config.host = args.host
    config.port = args.port
    config.failure_rate = args.failure_rate
    config.response_delay_min = args.delay_min
    config.response_delay_max = args.delay_max
    config.rate_limit_requests = args.rate_limit
    
    if args.test_data_dir:
        config.test_data_dir = args.test_data_dir
    
    # Start server
    server = MockAPIServer(config)
    
    print(f"""
Mock API Server for ArcDeploy Testing
=====================================

Server URL: http://{config.host}:{config.port}

Usage Examples:
  # Test successful server creation
  curl http://{config.host}:{config.port}/hetzner/servers

  # Test rate limiting
  curl http://{config.host}:{config.port}/hetzner/servers?scenario=rate-limit-exceeded

  # Test quota exceeded
  curl http://{config.host}:{config.port}/aws/instances?scenario=quota-exceeded

  # List available scenarios
  curl http://{config.host}:{config.port}/hetzner/test-scenarios

Configuration:
  - Failure Rate: {config.failure_rate * 100}%
  - Response Delay: {config.response_delay_min}-{config.response_delay_max}s
  - Rate Limit: {config.rate_limit_requests} requests/hour

Press Ctrl+C to stop the server
""")
    
    try:
        server.start()
    except Exception as e:
        logging.error(f"Failed to start server: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()