FROM alpine:latest

ENV DISPLAY=:1 \
    HOME=/root

# Install packages
RUN apk add --no-cache \
    openjdk17-jre \
    firefox \
    xvfb \
    x11vnc \
    jwm \
    feh \
    wget \
    unzip \
    bash \
    ttf-dejavu \
    fontconfig \
    xterm \
    mesa-dri-gallium \
    python3 \
    py3-pip \
    imagemagick

# Download MicroEmulator
RUN mkdir -p /opt/microemulator \
    && wget -q https://storage.googleapis.com/google-code-archive-downloads/v2/code.google.com/microemu/microemulator-2.0.4.zip \
       -O /tmp/microemulator.zip \
    && unzip -q /tmp/microemulator.zip -d /opt/microemulator \
    && rm -f /tmp/microemulator.zip

# Download Avatar
RUN wget -q https://files.catbox.moe/sllphh.ja \
    -O /opt/microemulator/avatar.jar

# Download Wallpaper
RUN mkdir -p /root/wallpaper \
    && wget -q \
    -O /root/wallpaper/bg.png \
    https://raw.githubusercontent.com/gptfreego1-rgb/k/refs/heads/main/file_000000005cac81fa9d4eaed1715e5291.png

# MicroEmulator launcher
RUN cat >/usr/local/bin/microemu <<'EOF'
#!/bin/sh
exec java \
-noverify \
-Xms16m \
-Xmx64m \
-XX:+UseSerialGC \
-XX:MaxRAM=500m \
-jar /opt/microemulator/microemulator-2.0.4/microemulator.jar \
/opt/microemulator/avatar.jar
EOF

RUN chmod +x /usr/local/bin/microemu

# Screenshot script - HD Quality
RUN cat >/usr/local/bin/screenshot <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="/root/screenshots/screenshot_${TIMESTAMP}.png"

# Screenshot dengan kualitas tinggi
DISPLAY=:1 import -window root -quality 100 -density 300 "$FILENAME"

# Optimasi PNG untuk ukuran lebih kecil tanpa kehilangan kualitas
if [ -f "$FILENAME" ]; then
    # Resize ke 2x untuk HD jika diinginkan
    # convert "$FILENAME" -resize 200% "$FILENAME"
    echo "Screenshot saved: $FILENAME"
    echo "File size: $(du -h "$FILENAME" | cut -f1)"
else
    echo "ERROR: Screenshot failed!"
fi
EOF

RUN chmod +x /usr/local/bin/screenshot

# Screenshot HD dengan resize otomatis
RUN cat >/usr/local/bin/screenshot-hd <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="/root/screenshots/screenshot_hd_${TIMESTAMP}.png"

# Ambil screenshot dengan resolusi tinggi
DISPLAY=:1 import -window root -quality 100 "$FILENAME"

# Upscale ke 2x untuk HD (1280x960 dari 640x480)
if [ -f "$FILENAME" ]; then
    convert "$FILENAME" -resize 200% -quality 100 "$FILENAME"
    echo "HD Screenshot saved: $FILENAME"
    echo "File size: $(du -h "$FILENAME" | cut -f1)"
else
    echo "ERROR: Screenshot failed!"
fi
EOF

RUN chmod +x /usr/local/bin/screenshot-hd

# Web server untuk screenshot dan download - dengan preview HD
RUN cat >/usr/local/bin/screenshot-server <<'EOF'
#!/usr/bin/env python3
from http.server import HTTPServer, BaseHTTPRequestHandler
import subprocess
import os
from datetime import datetime
import json
from urllib.parse import urlparse

class ScreenshotHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed_path = urlparse(self.path)
        
        if parsed_path.path == '/':
            self.serve_html()
        elif parsed_path.path == '/screenshot':
            self.take_screenshot()
        elif parsed_path.path == '/screenshot-hd':
            self.take_screenshot_hd()
        elif parsed_path.path.startswith('/download/'):
            self.download_screenshot(parsed_path.path)
        elif parsed_path.path == '/list':
            self.list_screenshots()
        else:
            self.send_404()
    
    def serve_html(self):
        html = """
        <!DOCTYPE html>
        <html>
        <head>
            <title>J2ME Screenshot HD</title>
            <meta charset="UTF-8">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body { 
                    font-family: 'Segoe UI', Arial, sans-serif;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    min-height: 100vh;
                    padding: 20px;
                }
                .container {
                    max-width: 900px;
                    margin: 0 auto;
                }
                h1 {
                    color: white;
                    text-align: center;
                    margin-bottom: 30px;
                    font-size: 2em;
                    text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
                }
                .panel {
                    background: white;
                    border-radius: 15px;
                    padding: 30px;
                    box-shadow: 0 10px 30px rgba(0,0,0,0.2);
                }
                .btn-group {
                    display: flex;
                    gap: 10px;
                    margin-bottom: 20px;
                }
                .screenshot-btn {
                    flex: 1;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    border: none;
                    padding: 15px 20px;
                    font-size: 1.1em;
                    border-radius: 10px;
                    cursor: pointer;
                    transition: all 0.3s;
                    font-weight: bold;
                }
                .screenshot-btn:hover {
                    transform: translateY(-2px);
                    box-shadow: 0 5px 15px rgba(0,0,0,0.3);
                }
                .screenshot-btn:active {
                    transform: translateY(0);
                }
                .screenshot-btn.hd {
                    background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
                }
                .notification {
                    display: none;
                    background: #4CAF50;
                    color: white;
                    padding: 15px;
                    border-radius: 5px;
                    margin-bottom: 20px;
                    text-align: center;
                    animation: slideIn 0.5s;
                }
                @keyframes slideIn {
                    from { transform: translateY(-20px); opacity: 0; }
                    to { transform: translateY(0); opacity: 1; }
                }
                .download-section {
                    display: none;
                    text-align: center;
                }
                .screenshot-preview {
                    max-width: 100%;
                    border: 2px solid #ddd;
                    border-radius: 10px;
                    margin-bottom: 15px;
                    box-shadow: 0 5px 15px rgba(0,0,0,0.1);
                }
                .download-link {
                    display: inline-block;
                    background: #2196F3;
                    color: white;
                    padding: 12px 25px;
                    border-radius: 8px;
                    text-decoration: none;
                    font-weight: bold;
                    transition: background 0.3s;
                }
                .download-link:hover {
                    background: #0b7dda;
                }
                .history-section {
                    margin-top: 30px;
                }
                .history-section h2 {
                    color: #333;
                    margin-bottom: 15px;
                    border-bottom: 2px solid #667eea;
                    padding-bottom: 10px;
                }
                .screenshots-grid {
                    display: grid;
                    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
                    gap: 15px;
                }
                .screenshot-item {
                    border: 1px solid #ddd;
                    border-radius: 8px;
                    overflow: hidden;
                    transition: all 0.3s;
                    background: white;
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
                    background: rgba(0,0,0,0.8);
                    color: white;
                    padding: 8px;
                    font-size: 0.7em;
                    text-align: center;
                    word-break: break-all;
                }
                .screenshot-item .fileinfo {
                    background: #f5f5f5;
                    padding: 5px;
                    font-size: 0.6em;
                    text-align: center;
                    color: #666;
                }
                .badge {
                    display: inline-block;
                    background: #f5576c;
                    color: white;
                    padding: 2px 8px;
                    border-radius: 10px;
                    font-size: 0.6em;
                    margin-left: 5px;
                }
                @media (max-width: 600px) {
                    .btn-group {
                        flex-direction: column;
                    }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📸 J2ME Screenshot Manager <span style="font-size:0.5em;">HD</span></h1>
                <div class="panel">
                    <div class="btn-group">
                        <button class="screenshot-btn" onclick="takeScreenshot('normal')">
                            📸 Screenshot
                        </button>
                        <button class="screenshot-btn hd" onclick="takeScreenshot('hd')">
                            📸 HD Screenshot <span style="font-size:0.7em;">(2x)</span>
                        </button>
                    </div>
                    <div class="notification" id="notification">✅ Screenshot berhasil diambil!</div>
                    <div class="download-section" id="downloadSection">
                        <h3>Hasil Screenshot:</h3>
                        <img class="screenshot-preview" id="screenshotPreview" alt="Screenshot">
                        <br>
                        <a class="download-link" id="downloadLink" href="#" download>
                            💾 Download Screenshot
                        </a>
                        <p style="margin-top:10px;color:#666;font-size:0.8em;" id="fileInfo"></p>
                    </div>
                </div>
                <div class="history-section">
                    <h2>📁 Screenshot History</h2>
                    <div class="screenshots-grid" id="screenshotsGrid"></div>
                </div>
            </div>
            
            <script>
                function takeScreenshot(type) {
                    const url = type === 'hd' ? '/screenshot-hd' : '/screenshot';
                    fetch(url)
                        .then(response => response.json())
                        .then(data => {
                            if (data.status === 'success') {
                                const notification = document.getElementById('notification');
                                notification.style.display = 'block';
                                setTimeout(() => {
                                    notification.style.display = 'none';
                                }, 3000);
                                
                                const downloadSection = document.getElementById('downloadSection');
                                downloadSection.style.display = 'block';
                                
                                const preview = document.getElementById('screenshotPreview');
                                preview.src = data.url + '?t=' + Date.now();
                                
                                const downloadLink = document.getElementById('downloadLink');
                                downloadLink.href = data.download_url;
                                downloadLink.download = data.filename;
                                
                                const fileInfo = document.getElementById('fileInfo');
                                fileInfo.textContent = type.toUpperCase() + ' - ' + data.filename + ' (' + data.size + ')';
                                
                                loadHistory();
                            } else {
                                alert('Gagal mengambil screenshot: ' + data.message);
                            }
                        })
                        .catch(error => {
                            console.error('Error:', error);
                            alert('Error mengambil screenshot');
                        });
                }
                
                function loadHistory() {
                    fetch('/list')
                        .then(response => response.json())
                        .then(data => {
                            const container = document.getElementById('screenshotsGrid');
                            container.innerHTML = '';
                            
                            data.screenshots.forEach(screenshot => {
                                const item = document.createElement('div');
                                item.className = 'screenshot-item';
                                const isHd = screenshot.name.includes('hd');
                                const badge = isHd ? '<span class="badge">HD</span>' : '';
                                item.innerHTML = `
                                    <a href="${screenshot.download_url}" download="${screenshot.name}">
                                        <img src="${screenshot.url}" alt="${screenshot.name}">
                                        <div class="filename">${screenshot.name} ${badge}</div>
                                        <div class="fileinfo">${screenshot.size}</div>
                                    </a>
                                `;
                                container.appendChild(item);
                            });
                        });
                }
                
                loadHistory();
            </script>
        </body>
        </html>
        """
        
        self.send_response(200)
        self.send_header('Content-type', 'text/html')
        self.end_headers()
        self.wfile.write(html.encode())
    
    def take_screenshot(self):
        return self._take_screenshot('normal')
    
    def take_screenshot_hd(self):
        return self._take_screenshot('hd')
    
    def _take_screenshot(self, mode):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        suffix = '_hd' if mode == 'hd' else ''
        filename = f'screenshot{suffix}_{timestamp}.png'
        filepath = f'/root/screenshots/{filename}'
        
        os.makedirs('/root/screenshots', exist_ok=True)
        
        try:
            if mode == 'hd':
                # HD: Ambil screenshot lalu resize ke 2x
                temp_file = f'/tmp/temp_screenshot_{timestamp}.png'
                result = subprocess.run(
                    ['import', '-window', 'root', '-quality', '100', temp_file],
                    env={**os.environ, 'DISPLAY': ':1'},
                    capture_output=True,
                    timeout=10
                )
                if result.returncode == 0 and os.path.exists(temp_file):
                    # Resize ke 2x untuk HD
                    subprocess.run(
                        ['convert', temp_file, '-resize', '200%', '-quality', '100', filepath],
                        capture_output=True,
                        timeout=10
                    )
                    os.remove(temp_file)
                else:
                    return self._error_response('Failed to capture screenshot')
            else:
                # Normal
                result = subprocess.run(
                    ['import', '-window', 'root', '-quality', '100', filepath],
                    env={**os.environ, 'DISPLAY': ':1'},
                    capture_output=True,
                    timeout=10
                )
                if result.returncode != 0:
                    return self._error_response('Failed to capture screenshot')
            
            if os.path.exists(filepath):
                file_size = os.path.getsize(filepath)
                size_str = self._format_size(file_size)
                
                response_data = {
                    'status': 'success',
                    'filename': filename,
                    'url': f'/download/{filename}',
                    'download_url': f'/download/{filename}',
                    'size': size_str
                }
                self.send_response(200)
            else:
                return self._error_response('File not created')
                
        except Exception as e:
            return self._error_response(str(e))
        
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())
    
    def _error_response(self, message):
        response_data = {
            'status': 'error',
            'message': message
        }
        self.send_response(500)
        self.send_header('Content-type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response_data).encode())
    
    def _format_size(self, size):
        for unit in ['B', 'KB', 'MB', 'GB']:
            if size < 1024.0:
                return f"{size:.1f} {unit}"
            size /= 1024.0
        return f"{size:.1f} GB"
    
    def download_screenshot(self, path):
        filename = os.path.basename(path)
        filepath = f'/root/screenshots/{filename}'
        
        if os.path.exists(filepath):
            self.send_response(200)
            self.send_header('Content-type', 'image/png')
            self.send_header('Content-Disposition', f'attachment; filename="{filename}"')
            self.end_headers()
            with open(filepath, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_404()
    
    def list_screenshots(self):
        screenshots = []
        if os.path.exists('/root/screenshots'):
            files = sorted(os.listdir('/root/screenshots'), reverse=True)
            for file in files:
                if file.endswith('.png'):
                    filepath = f'/root/screenshots/{file}'
                    size = os.path.getsize(filepath) if os.path.exists(filepath) else 0
                    screenshots.append({
                        'name': file,
                        'url': f'/download/{file}',
                        'download_url': f'/download/{file}',
                        'size': self._format_size(size)
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
    os.makedirs('/root/screenshots', exist_ok=True)
    server = HTTPServer(('0.0.0.0', 8080), ScreenshotHandler)
    print('Screenshot HD server running on port 8080')
    server.serve_forever()
EOF

RUN chmod +x /usr/local/bin/screenshot-server

# Change VNC Password
RUN cat >/usr/local/bin/change-vnc-password <<'EOF'
#!/bin/sh

mkdir -p /root/.vnc

xterm -title "Change VNC Password" -e sh -c '

echo
echo "=== Change VNC Password ==="
echo

x11vnc -storepasswd /root/.vnc/passwd

echo
echo "Restarting VNC..."

pkill x11vnc 2>/dev/null || true

sleep 2

x11vnc \
-display :1 \
-rfbport 5901 \
-rfbauth /root/.vnc/passwd \
-forever \
-shared \
-noxdamage \
-nowf >/tmp/x11vnc.log 2>&1 &

echo
echo "Password changed successfully."
echo
echo "Press ENTER to close..."
read
'
EOF

RUN chmod +x /usr/local/bin/change-vnc-password

# JWM Configuration
RUN cat >/root/.jwmrc <<'EOF'
<?xml version="1.0"?>

<JWM>

<StartupCommand>feh --bg-fill /root/wallpaper/bg.png</StartupCommand>

<RootMenu onroot="12">

    <Program label="Firefox">
        firefox
    </Program>

    <Program label="MicroEmulator">
        microemu
    </Program>

    <Program label="Terminal">
        xterm
    </Program>

    <Program label="Take Screenshot">
        screenshot
    </Program>

    <Program label="Take Screenshot HD">
        screenshot-hd
    </Program>

    <Program label="Change VNC Password">
        change-vnc-password
    </Program>

    <Separator/>

    <Exit label="Exit"/>

</RootMenu>

<Tray x="0" y="-1" height="28">

    <TrayButton label="Menu">
        root:1
    </TrayButton>

    <TrayButton label="Firefox">
        exec:firefox
    </TrayButton>

    <TrayButton label="MicroEmulator">
        exec:microemu
    </TrayButton>

    <TrayButton label="Screenshot">
        exec:screenshot
    </TrayButton>

    <Spacer/>

    <Clock format="%H:%M"/>

</Tray>

<Desktops width="1" height="1"/>

</JWM>
EOF

# Startup Script - dengan resolusi lebih tinggi
RUN cat >/startup.sh <<'EOF'
#!/bin/sh

export DISPLAY=:1

mkdir -p /root/.vnc
mkdir -p /root/screenshots

# Default password: 123456
if [ ! -f /root/.vnc/passwd ]; then
    x11vnc -storepasswd 123456 /root/.vnc/passwd >/dev/null
fi

# Cleanup old X locks
rm -f /tmp/.X1-lock
rm -rf /tmp/.X11-unix/X1

# Start X server dengan resolusi lebih tinggi untuk HD
Xvfb :1 -screen 0 1024x768x24 &
sleep 2

# Start Window Manager
jwm &

# Start VNC
x11vnc \
-display :1 \
-rfbport 5901 \
-rfbauth /root/.vnc/passwd \
-forever \
-shared \
-noxdamage \
-nowf &

# Start Screenshot Server
screenshot-server &

wait $!
EOF

RUN chmod +x /startup.sh

# Cleanup
RUN rm -rf \
    /var/cache/apk/* \
    /tmp/* \
    /root/.cache

EXPOSE 5901 8080

WORKDIR /root

CMD ["/startup.sh"]
