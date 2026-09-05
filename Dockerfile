FROM alpine:latest

ENV DISPLAY=:1 \
    HOME=/root

# Install dependencies and Ant manually
RUN apk add --no-cache \
    openjdk17-jre \
    openjdk17-jdk \
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
    git \
    imagemagick \
    python3 \
    py3-pip \
    && rm -rf /var/cache/apk/*

# Install Ant manually
RUN wget -q https://dlcdn.apache.org//ant/binaries/apache-ant-1.10.14-bin.zip \
    && unzip -q apache-ant-1.10.14-bin.zip -d /opt \
    && mv /opt/apache-ant-1.10.14 /opt/ant \
    && rm apache-ant-1.10.14-bin.zip \
    && ln -s /opt/ant/bin/ant /usr/local/bin/ant \
    && chmod +x /usr/local/bin/ant \
    && ant -version

# Clone dan build FreeJ2ME dengan Ant
RUN mkdir -p /opt/freej2me \
    && cd /opt/freej2me \
    && git clone --depth 1 https://github.com/hex007/freej2me.git . \
    && echo "=== Struktur repository ===" \
    && ls -la \
    && echo "=== Mencari build script ===" \
    && find . -maxdepth 2 -name "build.xml" -o -name "build.gradle" -o -name "pom.xml" -o -name "gradlew" | sort

# Build dengan Ant
RUN cd /opt/freej2me \
    && if [ -f "build.xml" ]; then \
         echo "=== Menemukan build.xml, build dengan Ant ==="; \
         ant build || ant jar || ant compile || ant; \
       elif [ -f "build.gradle" ]; then \
         echo "=== Menemukan build.gradle, build dengan Gradle ==="; \
         gradle build || gradle jar || gradle assemble; \
       elif [ -f "pom.xml" ]; then \
         echo "=== Menemukan pom.xml, build dengan Maven ==="; \
         mvn package || mvn compile; \
       elif [ -d "freej2me" ]; then \
         echo "=== Masuk ke subdirectory freej2me ==="; \
         cd freej2me; \
         if [ -f "build.xml" ]; then \
           ant build || ant jar || ant compile || ant; \
         elif [ -f "build.gradle" ]; then \
           gradle build || gradle jar || gradle assemble; \
         else \
           echo "ERROR: Tidak menemukan build script di subdirectory"; \
           find . -maxdepth 2 -type f | sort; \
           exit 1; \
         fi; \
       else \
         echo "ERROR: Tidak menemukan build script"; \
         echo "Struktur lengkap:"; \
         find . -maxdepth 2 -type f | sort; \
         exit 1; \
       fi \
    && echo "=== Hasil build ===" \
    && find . -name "*.jar" -type f | grep -v "ant\|gradle\|maven"

# Cari dan copy jar hasil build
RUN cd /opt/freej2me \
    && echo "=== Mencari JAR file ===" \
    && find . -name "*.jar" -type f | sort \
    && JAR_FILE=$(find . -name "*.jar" -type f | grep -i "freej2me\|microemulator\|emulator" | head -1) \
    && if [ -z "$JAR_FILE" ]; then \
         JAR_FILE=$(find . -name "*.jar" -type f | grep -v "ant\|gradle\|maven\|sources\|javadoc\|lib" | head -1); \
       fi \
    && if [ -z "$JAR_FILE" ]; then \
         JAR_FILE=$(find . -name "*.jar" -type f | head -1); \
       fi \
    && echo "JAR file yang digunakan: $JAR_FILE" \
    && if [ -n "$JAR_FILE" ]; then \
         cp "$JAR_FILE" /opt/freej2me/freej2me.jar; \
       else \
         echo "ERROR: Tidak menemukan file JAR hasil build"; \
         exit 1; \
       fi \
    && mkdir -p /opt/freej2me/games \
    && ls -la /opt/freej2me/freej2me.jar

# Download Avatar
RUN wget -q https://files.catbox.moe/sllphh.ja \
    -O /opt/freej2me/games/avatar.jar

# Download Wallpaper
RUN mkdir -p /root/wallpaper \
    && wget -q \
    -O /root/wallpaper/bg.png \
    https://raw.githubusercontent.com/gptfreego1-rgb/k/refs/heads/main/file_000000005cac81fa9d4eaed1715e5291.png

# FreeJ2ME launcher
RUN cat >/usr/local/bin/freej2me <<'EOF'
#!/bin/sh
exec java \
-noverify \
-Xms16m \
-Xmx64m \
-XX:+UseSerialGC \
-XX:MaxRAM=64m \
-jar /opt/freej2me/freej2me.jar \
/opt/freej2me/games/avatar.jar
EOF

RUN chmod +x /usr/local/bin/freej2me

# Screenshot script
RUN cat >/usr/local/bin/screenshot <<'EOF'
#!/bin/sh
mkdir -p /root/screenshots
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DISPLAY=:1 import -window root /root/screenshots/screenshot_${TIMESTAMP}.png
echo "Screenshot saved: /root/screenshots/screenshot_${TIMESTAMP}.png"
EOF

RUN chmod +x /usr/local/bin/screenshot

# Web server untuk screenshot dan download
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
                    max-width: 800px;
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
                    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
                    gap: 15px;
                }
                .screenshot-item {
                    border: 1px solid #ddd;
                    border-radius: 8px;
                    overflow: hidden;
                    transition: all 0.3s;
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
                    background: rgba(0,0,0,0.7);
                    color: white;
                    padding: 5px;
                    font-size: 0.7em;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>📸 J2ME Screenshot Manager</h1>
                <div class="panel">
                    <button class="screenshot-btn" onclick="takeScreenshot()">
                        📸 Take Screenshot
                    </button>
                    <div class="notification" id="notification">✅ Screenshot berhasil diambil!</div>
                    <div class="download-section" id="downloadSection">
                        <h3>Hasil Screenshot:</h3>
                        <img class="screenshot-preview" id="screenshotPreview" alt="Screenshot">
                        <br>
                        <a class="download-link" id="downloadLink" href="#" download>
                            💾 Download Screenshot
                        </a>
                    </div>
                </div>
                <div class="history-section">
                    <h2>📁 Screenshot History</h2>
                    <div class="screenshots-grid" id="screenshotsGrid"></div>
                </div>
            </div>
            
            <script>
                function takeScreenshot() {
                    fetch('/screenshot')
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
                                preview.src = data.url;
                                
                                const downloadLink = document.getElementById('downloadLink');
                                downloadLink.href = data.download_url;
                                downloadLink.download = data.filename;
                                
                                loadHistory();
                            } else {
                                alert('Gagal mengambil screenshot');
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
                                item.innerHTML = `
                                    <a href="${screenshot.download_url}" download="${screenshot.name}">
                                        <img src="${screenshot.url}" alt="${screenshot.name}">
                                        <div class="filename">${screenshot.name}</div>
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
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f'screenshot_{timestamp}.png'
        filepath = f'/root/screenshots/{filename}'
        
        os.makedirs('/root/screenshots', exist_ok=True)
        
        try:
            result = subprocess.run(
                ['import', '-window', 'root', filepath],
                env={**os.environ, 'DISPLAY': ':1'},
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
                    screenshots.append({
                        'name': file,
                        'url': f'/download/{file}',
                        'download_url': f'/download/{file}'
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
    print('Screenshot server running on port 8080')
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

    <Program label="FreeJ2ME">
        freej2me
    </Program>

    <Program label="Terminal">
        xterm
    </Program>

    <Program label="Take Screenshot">
        screenshot
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

    <TrayButton label="FreeJ2ME">
        exec:freej2me
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
Xvfb :1 -screen 0 800x600x16 &
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

# Auto-start FreeJ2ME
sleep 3
freej2me &

wait $!
EOF

RUN chmod +x /startup.sh

# Cleanup
RUN rm -rf \
    /var/cache/apk/* \
    /tmp/* \
    /root/.cache

# Expose ports
EXPOSE 5901 8080

WORKDIR /root

CMD ["/startup.sh"]
