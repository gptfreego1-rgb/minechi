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
    imagemagick \
    xdotool

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

# MicroEmulator launcher dengan window title
RUN cat >/usr/local/bin/microemu <<'EOF'
#!/bin/sh
exec java \
-noverify \
-Xms16m \
-Xmx400m \
-XX:+UseSerialGC \
-XX:MaxRAM=400m \
-jar /opt/microemulator/microemulator-2.0.4/microemulator.jar \
/opt/microemulator/avatar.jar
EOF

RUN chmod +x /usr/local/bin/microemu

# Screenshot script - hanya MicroEmulator
RUN cat >/usr/local/bin/screenshot <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="/root/screenshots/screenshot_${TIMESTAMP}.png"

# Tunggu sebentar agar window stabil
sleep 1

# Cari window MicroEmulator
WINDOW_ID=$(DISPLAY=:1 xdotool search --name "MicroEmulator" 2>/dev/null | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: MicroEmulator window not found!"
    echo "Mencoba screenshot full window saja..."
    DISPLAY=:1 import -window root -quality 100 "$FILENAME"
else
    echo "Found MicroEmulator window ID: $WINDOW_ID"
    # Screenshot hanya window MicroEmulator
    DISPLAY=:1 import -window "$WINDOW_ID" -quality 100 "$FILENAME"
fi

if [ -f "$FILENAME" ]; then
    echo "Screenshot saved: $FILENAME"
    echo "File size: $(du -h "$FILENAME" | cut -f1)"
else
    echo "ERROR: Screenshot failed!"
fi
EOF

RUN chmod +x /usr/local/bin/screenshot

# Screenshot HD - hanya MicroEmulator dengan resize
RUN cat >/usr/local/bin/screenshot-hd <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="/root/screenshots/screenshot_hd_${TIMESTAMP}.png"
TEMP_FILE="/tmp/temp_screenshot_${TIMESTAMP}.png"

# Tunggu sebentar
sleep 1

# Cari window MicroEmulator
WINDOW_ID=$(DISPLAY=:1 xdotool search --name "MicroEmulator" 2>/dev/null | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: MicroEmulator window not found!"
    echo "Mencoba screenshot full window saja..."
    DISPLAY=:1 import -window root -quality 100 "$TEMP_FILE"
else
    echo "Found MicroEmulator window ID: $WINDOW_ID"
    DISPLAY=:1 import -window "$WINDOW_ID" -quality 100 "$TEMP_FILE"
fi

if [ -f "$TEMP_FILE" ]; then
    # Resize ke 2x untuk HD
    convert "$TEMP_FILE" -resize 200% -quality 100 "$FILENAME"
    rm -f "$TEMP_FILE"
    echo "HD Screenshot saved: $FILENAME"
    echo "File size: $(du -h "$FILENAME" | cut -f1)"
else
    echo "ERROR: Screenshot failed!"
fi
EOF

RUN chmod +x /usr/local/bin/screenshot-hd

# Screenshot crop otomatis (crop border)
RUN cat >/usr/local/bin/screenshot-crop <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILENAME="/root/screenshots/screenshot_crop_${TIMESTAMP}.png"
TEMP_FILE="/tmp/temp_screenshot_${TIMESTAMP}.png"

sleep 1

WINDOW_ID=$(DISPLAY=:1 xdotool search --name "MicroEmulator" 2>/dev/null | head -1)

if [ -z "$WINDOW_ID" ]; then
    echo "ERROR: MicroEmulator window not found!"
    exit 1
fi

echo "Found MicroEmulator window ID: $WINDOW_ID"

# Ambil screenshot window
DISPLAY=:1 import -window "$WINDOW_ID" -quality 100 "$TEMP_FILE"

if [ -f "$TEMP_FILE" ]; then
    # Crop border (hilangkan 5px dari setiap sisi)
    convert "$TEMP_FILE" -shave 5x5 -quality 100 "$FILENAME"
    rm -f "$TEMP_FILE"
    echo "Cropped screenshot saved: $FILENAME"
    echo "File size: $(du -h "$FILENAME" | cut -f1)"
else
    echo "ERROR: Screenshot failed!"
fi
EOF

RUN chmod +x /usr/local/bin/screenshot-crop

# Web server untuk screenshot
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
            self.take_screenshot('normal')
        elif parsed_path.path == '/screenshot-hd':
            self.take_screenshot('hd')
        elif parsed_path.path == '/screenshot-crop':
            self.take_screenshot('crop')
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
            <title>J2ME Screenshot</title>
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
                    flex-wrap: wrap;
                }
                .screenshot-btn {
                    flex: 1;
                    min-width: 120px;
                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                    color: white;
                    border: none;
                    padding: 15px 20px;
                    font-size: 1em;
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
                .screenshot-btn.crop {
                    background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
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
                    padding: 2px 8px;
                    border-radius: 10px;
                    font-size: 0.6em;
                    margin-left: 5px;
                }
                .badge.hd { background: #f5576c; color: white; }
                .badge.crop { background: #4facfe; color: white; }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📸 MicroEmulator Screenshot</h1>
                <div class="panel">
                    <div class="btn-group">
                        <button class="screenshot-btn" onclick="takeScreenshot('normal')">
                            📸 Screenshot
                        </button>
                        <button class="screenshot-btn hd" onclick="takeScreenshot('hd')">
                            📸 HD <span style="font-size:0.7em;">(2x)</span>
                        </button>
                        <button class="screenshot-btn crop" onclick="takeScreenshot('crop')">
                            ✂️ Crop Border
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
                    const urls = {
                        'normal': '/screenshot',
                        'hd': '/screenshot-hd',
                        'crop': '/screenshot-crop'
                    };
                    fetch(urls[type])
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
                                const typeNames = {'normal': 'Normal', 'hd': 'HD', 'crop': 'Cropped'};
                                fileInfo.textContent = typeNames[type] + ' - ' + data.filename + ' (' + data.size + ')';
                                
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
                                let badge = '';
                                if (screenshot.name.includes('hd')) {
                                    badge = '<span class="badge hd">HD</span>';
                                } else if (screenshot.name.includes('crop')) {
                                    badge = '<span class="badge crop">Crop</span>';
                                }
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
    
    def take_screenshot(self, mode):
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        suffix = ''
        if mode == 'hd':
            suffix = '_hd'
        elif mode == 'crop':
            suffix = '_crop'
        filename = f'screenshot{suffix}_{timestamp}.png'
        filepath = f'/root/screenshots/{filename}'
        
        os.makedirs('/root/screenshots', exist_ok=True)
        
        try:
            # Panggil script bash yang sesuai
            if mode == 'hd':
                script = '/usr/local/bin/screenshot-hd'
            elif mode == 'crop':
                script = '/usr/local/bin/screenshot-crop'
            else:
                script = '/usr/local/bin/screenshot'
            
            result = subprocess.run(
                [script],
                capture_output=True,
                timeout=15
            )
            
            # Cari file screenshot terbaru
            if os.path.exists('/root/screenshots'):
                files = sorted([f for f in os.listdir('/root/screenshots') if f.endswith('.png')], reverse=True)
                if files:
                    latest = files[0]
                    latest_path = f'/root/screenshots/{latest}'
                    if os.path.exists(latest_path):
                        file_size = os.path.getsize(latest_path)
                        size_str = self._format_size(file_size)
                        
                        response_data = {
                            'status': 'success',
                            'filename': latest,
                            'url': f'/download/{latest}',
                            'download_url': f'/download/{latest}',
                            'size': size_str
                        }
                        self.send_response(200)
                    else:
                        return self._error_response('File not found')
                else:
                    return self._error_response('No screenshot created')
            else:
                return self._error_response('Screenshots directory not found')
                
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
    print('MicroEmulator Screenshot server running on port 8080')
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

    <Program label="Screenshot">
        screenshot
    </Program>

    <Program label="Screenshot HD">
        screenshot-hd
    </Program>

    <Program label="Screenshot Crop">
        screenshot-crop
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

# Startup Script
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

# Start X server
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
