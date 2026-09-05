FROM ubuntu:22.04

# Set environment untuk non-interactive installation
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Etc/UTC

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
    tzdata \
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

# Buat web server dengan tombol screenshot dan download
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
        elif parsed_path.path.startswith('/download/'):
            self.download_screenshot(parsed_path.path)
        else:
            self.send_404()
    
    def serve_html(self):
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>J2ME Emulator</title>
            <style>
                body {
                    margin: 0;
                    padding: 20px;
                    font-family: Arial, sans-serif;
                    background: #f0f0f0;
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                }
                .emulator-container {
                    width: 100%;
                    max-width: 800px;
                    margin-bottom: 20px;
                }
                iframe {
                    width: 100%;
                    height: 600px;
                    border: 2px solid #333;
                    border-radius: 10px;
                }
                .controls {
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    gap: 10px;
                }
                .screenshot-btn {
                    background: #4CAF50;
                    color: white;
                    border: none;
                    padding: 15px 30px;
                    font-size: 18px;
                    border-radius: 10px;
                    cursor: pointer;
                    transition: background 0.3s;
                }
                .screenshot-btn:hover {
                    background: #45a049;
                }
                .notification {
                    display: none;
                    background: #4CAF50;
                    color: white;
                    padding: 10px 20px;
                    border-radius: 5px;
                }
                .download-section {
                    display: none;
                    background: white;
                    padding: 15px;
                    border-radius: 10px;
                    box-shadow: 0 2px 5px rgba(0,0,0,0.1);
                    text-align: center;
                }
                .download-link {
                    display: inline-block;
                    background: #2196F3;
                    color: white;
                    padding: 10px 20px;
                    border-radius: 5px;
                    text-decoration: none;
                    margin-top: 10px;
                    font-weight: bold;
                }
                .download-link:hover {
                    background: #0b7dda;
                }
                .screenshot-preview {
                    max-width: 300px;
                    margin-top: 10px;
                    border: 1px solid #ddd;
                    border-radius: 5px;
                }
            </style>
        </head>
        <body>
            <div class="emulator-container">
                <iframe src="http://localhost:6080/vnc.html"></iframe>
            </div>
            <div class="controls">
                <button class="screenshot-btn" onclick="takeScreenshot()">
                    📸 Screenshot
                </button>
                <div class="notification" id="notification">✅ Screenshot berhasil!</div>
                <div class="download-section" id="downloadSection">
                    <h3>Hasil Screenshot:</h3>
                    <img class="screenshot-preview" id="screenshotPreview" alt="Screenshot">
                    <br>
                    <a class="download-link" id="downloadLink" href="#" download>
                        💾 Download Screenshot
                    </a>
                </div>
            </div>
            
            <script>
                function takeScreenshot() {
                    fetch('/screenshot')
                        .then(response => response.json())
                        .then(data => {
                            if (data.status === 'success') {
                                // Tampilkan notifikasi
                                const notification = document.getElementById('notification');
                                notification.style.display = 'block';
                                setTimeout(() => {
                                    notification.style.display = 'none';
                                }, 2000);
                                
                                // Tampilkan section download
                                const downloadSection = document.getElementById('downloadSection');
                                downloadSection.style.display = 'block';
                                
                                // Set preview dan link download
                                const preview = document.getElementById('screenshotPreview');
                                preview.src = data.url;
                                
                                const downloadLink = document.getElementById('downloadLink');
                                downloadLink.href = data.download_url;
                                downloadLink.download = data.filename;
                            } else {
                                alert('Gagal mengambil screenshot');
                            }
                        })
                        .catch(error => {
                            console.error('Error:', error);
                            alert('Error mengambil screenshot');
                        });
                }
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
                    'filename': filename,
                    'url': f'/download/{filename}',
                    'download_url': f'/download/{filename}'
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
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())
    
    def download_screenshot(self, path):
        filename = os.path.basename(path)
        filepath = f'/app/screenshots/{filename}'
        
        if os.path.exists(filepath):
            self.send_response(200)
            self.send_header('Content-type', 'image/png')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_404()
    
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
command=java -jar -noverify /app/freej2me/build/libs/freej2me.jar /app/games/avatar.jar\n\
environment=DISPLAY=:99\n\
priority=5\n\
\n\
[program:webserver]\n\
command=python3 /app/web_server.py\n\
priority=6\n\
autorestart=true' > /etc/supervisor/conf.d/j2me.conf

# Expose ports
EXPOSE 6080 8080

WORKDIR /app

CMD ["/usr/bin/supervisord"]
