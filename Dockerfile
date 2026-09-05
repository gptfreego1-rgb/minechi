FROM ubuntu:22.04

# Install dependencies
RUN apt-get update && apt-get install -y \
    openjdk-11-jdk \
    git \
    gradle \
    wget \
    xvfb \
    x11vnc \
    fluxbox \
    novnc \
    websockify \
    supervisor \
    imagemagick \
    python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Clone FreeJ2ME
RUN git clone https://github.com/hex007/freej2me.git

WORKDIR /app/freej2me

# Build project
RUN gradle build

WORKDIR /app

# Buat folder untuk games dan screenshots
RUN mkdir -p /app/games /app/screenshots

# Download game contoh (avatar.jar)
RUN wget -O /app/games/avatar.jar "https://files.catbox.moe/sllphh.ja"

# Script untuk menjalankan game
RUN echo '#!/bin/bash\n\
GAME_FILE=${1:-/app/games/avatar.jar}\n\
java -jar /app/freej2me/build/libs/freej2me.jar "$GAME_FILE"' > /app/run.sh && \
chmod +x /app/run.sh

# Buat web server Python untuk control panel
RUN cat > /app/web_server.py << 'EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess
import os
from datetime import datetime
import json
from urllib.parse import urlparse

class WebHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/':
            self.serve_html()
        elif parsed_path.path == '/screenshot':
            self.take_screenshot()
        elif parsed_path.path.startswith('/screenshots/'):
            self.serve_screenshot(parsed_path.path)
        elif parsed_path.path == '/list_screenshots':
            self.list_screenshots()
        else:
            self.send_404()
    
    def serve_html(self):
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>J2ME Emulator Control Panel</title>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { 
                    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                    padding: 20px;
                }
                .container {
                    max-width: 1400px;
                    margin: 0 auto;
                }
                h1 {
                    color: white;
                    text-align: center;
                    margin-bottom: 30px;
                    font-size: 2.5em;
                    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
                }
                .main-panel {
                    display: grid;
                    grid-template-columns: 1fr 1fr;
                    gap: 20px;
                    margin-bottom: 20px;
                }
                .panel {
                    background: white;
                    border-radius: 15px;
                    padding: 20px;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                }
                .panel h2 {
                    color: #333;
                    margin-bottom: 15px;
                    border-bottom: 2px solid #667eea;
                    padding-bottom: 10px;
                }
                .emulator-view {
                    width: 100%;
                    height: 600px;
                    border: none;
                    border-radius: 10px;
                    background: #000;
                }
                .screenshot-btn {
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    border: none;
                    padding: 15px 30px;
                    font-size: 1.2em;
                    border-radius: 10px;
                    cursor: pointer;
                    transition: all 0.3s;
                    width: 100%;
                    margin-bottom: 20px;
                    font-weight: bold;
                }
                .screenshot-btn:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 5px 15px rgba(0,0,0,0.3);
                }
                .screenshot-btn:active {
                    transform: translateY(0);
                }
                .screenshots-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                    gap: 15px;
                    max-height: 500px;
                    overflow-y: auto;
                }
                .screenshot-item {
                    position: relative;
                    border: 1px solid #ddd;
                    border-radius: 8px;
                    overflow: hidden;
                    transition: all 0.3s;
                    cursor: pointer;
                }
                .screenshot-item:hover {
                    transform: scale(1.05);
                    box-shadow: 0 5px 15px rgba(0,0,0,0.3);
                }
                .screenshot-item img {
                    width: 100%;
                    height: auto;
                    display: block;
                }
                .screenshot-item .filename {
                    position: absolute;
                    bottom: 0;
                    left: 0;
                    right: 0;
                    background: rgba(0,0,0,0.7);
                    color: white;
                    padding: 5px;
                    font-size: 0.8em;
                    text-align: center;
                }
                .loading {
                    display: none;
                    text-align: center;
                    padding: 20px;
                    color: #667eea;
                    font-weight: bold;
                }
                .notification {
                    display: none;
                    position: fixed;
                    top: 20px;
                    right: 20px;
                    background: #4CAF50;
                    color: white;
                    padding: 15px 20px;
                    border-radius: 5px;
                    box-shadow: 0 3px 10px rgba(0,0,0,0.2);
                    animation: slideIn 0.5s;
                    z-index: 1000;
                }
                @keyframes slideIn {
                    from { transform: translateX(100%); opacity: 0; }
                    to { transform: translateX(0); opacity: 1; }
                }
                .empty-state {
                    text-align: center;
                    color: #999;
                    padding: 40px;
                    font-style: italic;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🎮 J2ME Emulator Control Panel</h1>
                
                <div class="main-panel">
                    <div class="panel">
                        <h2>📱 Emulator View</h2>
                        <iframe class="emulator-view" src="http://localhost:6080/vnc.html"></iframe>
                    </div>
                    
                    <div class="panel">
                        <h2>📸 Screenshot Control</h2>
                        <button class="screenshot-btn" onclick="takeScreenshot()">
                            📸 Take Screenshot
                        </button>
                        <div class="loading" id="loading">Taking screenshot...</div>
                        <div id="screenshots" class="screenshots-grid">
                            <div class="empty-state">No screenshots yet. Click the button above!</div>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="notification" id="notification">✅ Screenshot saved!</div>
            
            <script>
                function takeScreenshot() {
                    const loading = document.getElementById('loading');
                    loading.style.display = 'block';
                    
                    fetch('/screenshot')
                        .then(response => response.json())
                        .then(data => {
                            loading.style.display = 'none';
                            if (data.status === 'success') {
                                showNotification();
                                loadScreenshots();
                            } else {
                                alert('Failed to take screenshot');
                            }
                        })
                        .catch(error => {
                            loading.style.display = 'none';
                            console.error('Error:', error);
                            alert('Error taking screenshot');
                        });
                }
                
                function loadScreenshots() {
                    fetch('/list_screenshots')
                        .then(response => response.json())
                        .then(data => {
                            const container = document.getElementById('screenshots');
                            
                            if (data.screenshots.length === 0) {
                                container.innerHTML = '<div class="empty-state">No screenshots yet. Click the button above!</div>';
                                return;
                            }
                            
                            container.innerHTML = '';
                            
                            data.screenshots.forEach(screenshot => {
                                const item = document.createElement('div');
                                item.className = 'screenshot-item';
                                item.onclick = () => window.open(screenshot.url, '_blank');
                                item.innerHTML = `
                                    <img src="${screenshot.url}" alt="${screenshot.name}">
                                    <div class="filename">${screenshot.name}</div>
                                `;
                                container.appendChild(item);
                            });
                        });
                }
                
                function showNotification() {
                    const notification = document.getElementById('notification');
                    notification.style.display = 'block';
                    setTimeout(() => {
                        notification.style.display = 'none';
                    }, 3000);
                }
                
                // Load screenshots on page load
                loadScreenshots();
                
                // Refresh screenshots every 30 seconds
                setInterval(loadScreenshots, 30000);
            </script>
        </body>
        </html>
        """
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def take_screenshot(self):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'screenshot_{timestamp}.png'
        filepath = f'/app/screenshots/{filename}'
        
        try:
            result = subprocess.run(
                ['import', '-window', 'root', filepath],
                env={**os.environ, 'DISPLAY': ':99'},
                capture_output=True,
                timeout=10
            )
            
            if result.returncode == 0:
                response_data = {
                    'status': 'success',
                    'file': filename,
                    'url': f'/screenshots/{filename}'
                }
                self.send_response(200)
            else:
                response_data = {
                    'status': 'error',
                    'message': 'Failed to take screenshot'
                }
                self.send_response(500)
                
        except Exception as e:
            response_data = {
                'status': 'error',
                'message': str(e)
            }
            self.send_response(500)
        
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())
    
    def serve_screenshot(self, path):
        filename = os.path.basename(path)
        filepath = f'/app/screenshots/{filename}'
        
        if os.path.exists(filepath):
            self.send_response(200)
            self.send_header('Content-type', 'image/png')
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_404()
    
    def list_screenshots(self):
        screenshots = []
        if os.path.exists('/app/screenshots'):
            files = sorted(os.listdir('/app/screenshots'), reverse=True)
            for file in files:
                if file.endswith('.png'):
                    screenshots.append({
                        'name': file,
                        'url': f'/screenshots/{file}'
                    })
        
        self.send_response(200)
        self.send_header('Content-type', 'application/json')
        self.end_headers()
        self.wfile.write(json.dumps({'screenshots': screenshots}).encode())
    
    def send_404(self):
        self.send_response(404)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(b'404 Not Found')

if __name__ == '__main__':
    server = HTTPServer(('0.0.0.0', 8080), WebHandler)
    print('Web server running on port 8080')
    server.serve_forever()
EOF

# FIX: Tambahkan RUN sebelum chmod
RUN chmod +x /app/web_server.py

# Konfigurasi supervisor
RUN echo '[supervisord]\n\
nodaemon=true\n\
\n\
[program:xvfb]\n\
command=Xvfb :99 -screen 0 1024x768x24\n\
priority=1\n\
\n\
[program:fluxbox]\n\
command=fluxbox\n\
environment=DISPLAY=:99\n\
priority=2\n\
\n\
[program:x11vnc]\n\
command=x11vnc -display :99 -forever -nopw -shared -rfbport 5900\n\
priority=3\n\
\n\
[program:novnc]\n\
command=websockify --web=/usr/share/novnc/ 6080 localhost:5900\n\
priority=4\n\
\n\
[program:j2me]\n\
command=/app/run.sh\n\
environment=DISPLAY=:99\n\
priority=5\n\
\n\
[program:webserver]\n\
command=python3 /app/web_server.py\n\
priority=6\n\
autorestart=true' > /etc/supervisor/conf.d/j2me.conf

# Expose ports
EXPOSE 6080 8080

# Set working directory
WORKDIR /app

# Jalankan supervisor
CMD ["/usr/bin/supervisord"]
