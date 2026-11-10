import Foundation

enum WebRemoteUI {
    static let html = """
    <!DOCTYPE html>
    <html lang="id">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <title>Presentools Remote</title>
      <style>
        :root {
          --bg-primary: #0a0c10;
          --bg-card: #151821;
          --bg-button: #222634;
          --border: #2e3447;
          --text-main: #f1f5f9;
          --text-dim: #94a3b8;
          --primary: #38bdf8;
          --spotlight-glow: rgba(251, 191, 36, 0.4);
          --laser-glow: rgba(239, 68, 68, 0.4);
          --zoom-glow: rgba(56, 189, 248, 0.4);
          --active-green: #22c55e;
          --active-spotlight: #f59e0b;
          --active-laser: #ef4444;
          --active-zoom: #0ea5e9;
        }
        * {
          box-sizing: border-box;
          margin: 0;
          padding: 0;
          user-select: none;
          -webkit-user-select: none;
          touch-action: manipulation;
          -webkit-tap-highlight-color: transparent;
        }
        body {
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
          background: var(--bg-primary);
          color: var(--text-main);
          min-height: 100vh;
          display: flex;
          flex-direction: column;
          align-items: center;
          padding: 12px;
          overflow-x: hidden;
        }
        header {
          width: 100%;
          max-width: 440px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 4px 4px 12px;
        }
        .brand {
          font-size: 1.1rem;
          font-weight: 700;
          letter-spacing: -0.5px;
          display: flex;
          align-items: center;
          gap: 8px;
        }
        .status-badge {
          display: flex;
          align-items: center;
          gap: 6px;
          font-size: 0.78rem;
          background: var(--bg-card);
          padding: 4px 10px;
          border-radius: 999px;
          border: 1px solid var(--border);
          color: var(--text-dim);
        }
        .status-dot {
          width: 7px;
          height: 7px;
          border-radius: 50%;
          background: #ef4444;
          transition: background 0.3s;
        }
        .status-dot.online {
          background: var(--active-green);
          box-shadow: 0 0 8px var(--active-green);
        }
        .nav-tabs {
          width: 100%;
          max-width: 440px;
          display: flex;
          background: var(--bg-card);
          padding: 4px;
          border-radius: 14px;
          border: 1px solid var(--border);
          margin-bottom: 14px;
        }
        .nav-tab {
          flex: 1;
          padding: 8px 0;
          font-size: 0.85rem;
          font-weight: 600;
          text-align: center;
          color: var(--text-dim);
          border-radius: 10px;
          cursor: pointer;
          transition: all 0.2s;
        }
        .nav-tab.active {
          background: #252b3b;
          color: #fff;
          box-shadow: 0 2px 8px rgba(0,0,0,0.3);
        }
        main {
          width: 100%;
          max-width: 440px;
          display: flex;
          flex-direction: column;
          gap: 16px;
          flex: 1;
        }
        .tab-content {
          display: none;
          flex-direction: column;
          gap: 16px;
          width: 100%;
        }
        .tab-content.active {
          display: flex;
        }
        .section-title {
          font-size: 0.75rem;
          text-transform: uppercase;
          letter-spacing: 1px;
          color: var(--text-dim);
          margin-bottom: 8px;
          padding-left: 2px;
        }
        .card {
          background: var(--bg-card);
          border: 1px solid var(--border);
          border-radius: 18px;
          padding: 14px;
        }
        .slide-zone {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
        }
        .btn-large {
          grid-column: span 2;
          height: 100px;
          background: linear-gradient(145deg, #1e293b, #0f172a);
          border: 1px solid #334155;
          border-radius: 16px;
          font-size: 1.3rem;
          font-weight: 700;
          color: #fff;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          box-shadow: 0 8px 20px rgba(0,0,0,0.4);
          cursor: pointer;
          transition: transform 0.08s ease, border-color 0.15s, background 0.15s;
        }
        .btn-large:active {
          transform: scale(0.97);
          background: #283548;
          border-color: var(--primary);
        }
        .btn-secondary {
          height: 72px;
          background: var(--bg-button);
          border: 1px solid var(--border);
          border-radius: 14px;
          font-size: 0.95rem;
          font-weight: 600;
          color: var(--text-main);
          display: flex;
          align-items: center;
          justify-content: center;
          gap: 8px;
          cursor: pointer;
          transition: transform 0.08s ease, background 0.15s;
        }
        .btn-secondary:active {
          transform: scale(0.96);
          background: #2e3447;
        }
        .effects-grid {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
        }
        .btn-effect {
          height: 76px;
          background: var(--bg-button);
          border: 1px solid var(--border);
          border-radius: 14px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          font-size: 0.88rem;
          font-weight: 600;
          color: var(--text-dim);
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }
        .btn-effect span.icon {
          font-size: 1.3rem;
        }
        .btn-effect:active {
          transform: scale(0.96);
        }
        .btn-effect.active-none {
          background: #1e293b;
          color: #fff;
          border-color: #64748b;
          box-shadow: 0 0 14px rgba(100, 116, 139, 0.3);
        }
        .btn-effect.active-spotlight {
          background: rgba(245, 158, 11, 0.15);
          color: #fbbf24;
          border-color: var(--active-spotlight);
          box-shadow: 0 0 16px var(--spotlight-glow);
        }
        .btn-effect.active-laser {
          background: rgba(239, 68, 68, 0.15);
          color: #f87171;
          border-color: var(--active-laser);
          box-shadow: 0 0 16px var(--laser-glow);
        }
        .btn-effect.active-zoom {
          background: rgba(14, 165, 233, 0.15);
          color: #38bdf8;
          border-color: var(--active-zoom);
          box-shadow: 0 0 16px var(--zoom-glow);
        }
        /* Trackpad & Air Mouse Styles */
        .touchpad-box {
          height: 280px;
          background: radial-gradient(circle at center, #1b202d, #11141c);
          border: 1.5px dashed #334155;
          border-radius: 20px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          position: relative;
          touch-action: none;
          cursor: crosshair;
        }
        .touchpad-box:active {
          border-color: var(--primary);
        }
        .touchpad-hint {
          font-size: 0.85rem;
          color: #64748b;
          pointer-events: none;
          text-align: center;
          padding: 0 20px;
        }
        .mouse-buttons {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 10px;
          margin-top: 10px;
        }
        .btn-mouse {
          height: 60px;
          background: var(--bg-button);
          border: 1px solid var(--border);
          border-radius: 12px;
          font-size: 0.95rem;
          font-weight: 600;
          color: var(--text-main);
          cursor: pointer;
        }
        .btn-mouse:active {
          background: #334155;
        }
        .airmouse-toggle {
          display: flex;
          align-items: center;
          justify-content: space-between;
          background: #1a202c;
          padding: 10px 14px;
          border-radius: 12px;
          border: 1px solid #2d3748;
          margin-bottom: 10px;
          font-size: 0.9rem;
          font-weight: 600;
        }
        .airmouse-hold-btn {
          width: 100%;
          height: 120px;
          background: linear-gradient(135deg, #0284c7, #0369a1);
          color: #fff;
          font-size: 1.15rem;
          font-weight: 700;
          border: none;
          border-radius: 18px;
          display: none;
          align-items: center;
          justify-content: center;
          flex-direction: column;
          gap: 8px;
          box-shadow: 0 6px 20px rgba(2, 132, 199, 0.4);
          cursor: pointer;
          touch-action: none;
        }
        .airmouse-hold-btn:active, .airmouse-hold-btn.holding {
          background: linear-gradient(135deg, #38bdf8, #0284c7);
          box-shadow: 0 0 24px rgba(56, 189, 248, 0.7);
          transform: scale(0.98);
        }
        .toast {
          position: fixed;
          bottom: 24px;
          background: #ef4444;
          color: white;
          padding: 10px 18px;
          border-radius: 12px;
          font-size: 0.85rem;
          box-shadow: 0 8px 24px rgba(0,0,0,0.5);
          opacity: 0;
          pointer-events: none;
          transition: opacity 0.25s ease, transform 0.25s ease;
          transform: translateY(12px);
          max-width: 90%;
          text-align: center;
          z-index: 100;
        }
        .toast.show {
          opacity: 1;
          transform: translateY(0);
        }
      </style>
    </head>
    <body>
      <header>
        <div class="brand">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color:var(--primary)"><circle cx="12" cy="12" r="10"></circle><polygon points="16.24 7.76 14.12 14.12 7.76 16.24 9.88 9.88 16.24 7.76"></polygon></svg>
          Presentools
        </div>
        <div class="status-badge">
          <div class="status-dot" id="statusDot"></div>
          <span id="statusText">Connecting</span>
        </div>
      </header>

      <div class="nav-tabs">
        <div class="nav-tab active" onclick="switchTab('remote')">Slide & Effects</div>
        <div class="nav-tab" onclick="switchTab('mouse')">Trackpad & Air Mouse</div>
      </div>

      <main>
        <!-- Tab 1: Remote & Effects -->
        <div class="tab-content active" id="tabRemote">
          <div>
            <div class="section-title">Slide Navigation (Clicker)</div>
            <div class="card slide-zone">
              <button class="btn-large" id="btnNext" onclick="triggerSlide('next')">
                <span>NEXT ➔</span>
                <small style="font-size:0.75rem; font-weight:normal; color:var(--text-dim)">Next Slide</small>
              </button>
              <button class="btn-secondary" id="btnPrev" onclick="triggerSlide('prev')">
                <span>⬅ PREV</span>
              </button>
              <button class="btn-secondary" id="btnBlank" onclick="triggerSlide('blank')">
                <span>⬛ BLANK</span>
              </button>
            </div>
          </div>

          <div>
            <div class="section-title">Presentools Effects</div>
            <div class="card effects-grid">
              <button class="btn-effect" id="effNone" onclick="setEffect('none')">
                <span class="icon">⏹️</span>
                <span>All Off</span>
              </button>
              <button class="btn-effect" id="effSpotlight" onclick="setEffect('spotlight')">
                <span class="icon">🔦</span>
                <span>Spotlight</span>
              </button>
              <button class="btn-effect" id="effLaser" onclick="setEffect('laser')">
                <span class="icon">🔴</span>
                <span>Laser</span>
              </button>
              <button class="btn-effect" id="effZoom" onclick="setEffect('zoom')">
                <span class="icon">🔍</span>
                <span>Zoom Lens</span>
              </button>
            </div>
          </div>
        </div>

        <!-- Tab 2: Trackpad & Air Mouse -->
        <div class="tab-content" id="tabMouse">
          <div class="airmouse-toggle">
            <span>Air Mouse Gyroscope</span>
            <input type="checkbox" id="gyroToggle" onchange="toggleGyro(this.checked)" style="transform:scale(1.3); cursor:pointer;">
          </div>

          <!-- Tombol Hold Saat Gyro Aktif -->
          <button class="airmouse-hold-btn" id="airMouseHoldBtn">
            <span>🎯 TAHAN UNTUK GERAKKAN</span>
            <small style="font-size:0.8rem; font-weight:normal; opacity:0.85">Arahkan HP ke layar Mac</small>
          </button>

          <!-- Area Touchpad Standar -->
          <div class="card" id="touchpadContainer">
            <div class="touchpad-box" id="touchpad">
              <div class="touchpad-hint">
                🖱️ <b>Touchpad Area</b><br>
                Geser untuk menggerakkan kursor.<br>
                Ketuk (tap) untuk klik.
              </div>
            </div>
            <div class="mouse-buttons">
              <button class="btn-mouse" onclick="sendMouseClick('click')">Left Click</button>
              <button class="btn-mouse" onclick="sendMouseClick('rightClick')">Right Click</button>
            </div>
          </div>
        </div>
      </main>

      <div class="toast" id="toast"></div>

      <script>
        let currentEffect = 'none';

        function vibrate(ms = 30) {
          if (navigator.vibrate) {
            navigator.vibrate(ms);
          }
        }

        function showToast(msg) {
          const t = document.getElementById('toast');
          t.textContent = msg;
          t.classList.add('show');
          setTimeout(() => t.classList.remove('show'), 3500);
        }

        function switchTab(name) {
          vibrate(20);
          document.querySelectorAll('.nav-tab').forEach((tab, i) => {
            tab.classList.toggle('active', (name === 'remote' && i === 0) || (name === 'mouse' && i === 1));
          });
          document.getElementById('tabRemote').classList.toggle('active', name === 'remote');
          document.getElementById('tabMouse').classList.toggle('active', name === 'mouse');
        }

        function updateEffectUI(effect) {
          currentEffect = effect;
          const effects = ['none', 'spotlight', 'laser', 'zoom'];
          effects.forEach(eff => {
            const btn = document.getElementById('eff' + eff.charAt(0).toUpperCase() + eff.slice(1));
            if (btn) {
              btn.className = 'btn-effect' + (eff === effect ? ' active-' + eff : '');
            }
          });
        }

        async function triggerSlide(action) {
          vibrate();
          try {
            const res = await fetch('/api/slide', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ action: action })
            });
            const data = await res.json();
            if (data.requiresAccessibility) {
              showToast("Buka System Settings > Privacy > Accessibility untuk mengizinkan Presentools");
            }
          } catch (e) {
            console.error(e);
          }
        }

        async function setEffect(effect) {
          vibrate();
          updateEffectUI(effect);
          try {
            await fetch('/api/effect', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ effect: effect })
            });
          } catch (e) {
            console.error(e);
          }
        }

        async function pollStatus() {
          try {
            const res = await fetch('/api/status');
            if (res.ok) {
              const data = await res.json();
              document.getElementById('statusDot').classList.add('online');
              document.getElementById('statusText').textContent = 'Ready';
              if (data.effect && data.effect !== currentEffect) {
                updateEffectUI(data.effect);
              }
            } else {
              throw new Error();
            }
          } catch (e) {
            document.getElementById('statusDot').classList.remove('online');
            document.getElementById('statusText').textContent = 'Offline';
          }
        }

        setInterval(pollStatus, 2000);
        pollStatus();

        /* --- Touchpad Logic --- */
        const pad = document.getElementById('touchpad');
        let touchStartX = 0, touchStartY = 0;
        let lastX = 0, lastY = 0;
        let touchStartTime = 0;
        let pendingDX = 0, pendingDY = 0;
        let sendTimer = null;

        function flushMouseMove() {
          if (pendingDX !== 0 || pendingDY !== 0) {
            const dx = pendingDX;
            const dy = pendingDY;
            pendingDX = 0;
            pendingDY = 0;
            fetch('/api/mouse', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ dx: dx, dy: dy })
            }).catch(() => {});
          }
          sendTimer = null;
        }

        function queueMouseMove(dx, dy) {
          pendingDX += dx;
          pendingDY += dy;
          if (!sendTimer) {
            sendTimer = setTimeout(flushMouseMove, 16); // ~60Hz
          }
        }

        pad.addEventListener('touchstart', (e) => {
          if (e.touches.length === 1) {
            const t = e.touches[0];
            touchStartX = t.clientX;
            touchStartY = t.clientY;
            lastX = t.clientX;
            lastY = t.clientY;
            touchStartTime = Date.now();
          }
        }, { passive: true });

        pad.addEventListener('touchmove', (e) => {
          if (e.touches.length === 1) {
            const t = e.touches[0];
            const dx = (t.clientX - lastX) * 1.6;
            const dy = (t.clientY - lastY) * 1.6;
            lastX = t.clientX;
            lastY = t.clientY;
            queueMouseMove(dx, dy);
          }
        }, { passive: true });

        pad.addEventListener('touchend', (e) => {
          const duration = Date.now() - touchStartTime;
          const moved = Math.hypot(lastX - touchStartX, lastY - touchStartY);
          if (duration < 220 && moved < 8) {
            // Tap detected -> Left Click
            vibrate(25);
            sendMouseClick('click');
          }
        });

        async function sendMouseClick(action) {
          vibrate(30);
          try {
            await fetch('/api/mouse', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ action: action })
            });
          } catch (e) {}
        }

        /* --- Air Mouse (Gyroscope) Logic --- */
        let gyroActive = false;
        let isHoldingAirMouse = false;
        let lastGamma = null, lastBeta = null;
        const holdBtn = document.getElementById('airMouseHoldBtn');
        const padBox = document.getElementById('touchpadContainer');

        async function toggleGyro(enabled) {
          if (enabled) {
            if (typeof DeviceOrientationEvent !== 'undefined' && typeof DeviceOrientationEvent.requestPermission === 'function') {
              try {
                const perm = await DeviceOrientationEvent.requestPermission();
                if (perm !== 'granted') {
                  showToast("Izin sensor gyro ditolak");
                  document.getElementById('gyroToggle').checked = false;
                  return;
                }
              } catch (err) {
                showToast("Gagal meminta izin gyro: " + err);
                document.getElementById('gyroToggle').checked = false;
                return;
              }
            }
            gyroActive = true;
            holdBtn.style.display = 'flex';
            padBox.style.display = 'none';
            window.addEventListener('deviceorientation', handleOrientation);
          } else {
            gyroActive = false;
            holdBtn.style.display = 'none';
            padBox.style.display = 'block';
            window.removeEventListener('deviceorientation', handleOrientation);
          }
        }

        function handleOrientation(e) {
          if (!gyroActive || !isHoldingAirMouse) {
            lastGamma = null;
            lastBeta = null;
            return;
          }
          if (lastGamma === null || lastBeta === null) {
            lastGamma = e.gamma;
            lastBeta = e.beta;
            return;
          }
          const dGamma = e.gamma - lastGamma;
          const dBeta = e.beta - lastBeta;
          lastGamma = e.gamma;
          lastBeta = e.beta;

          // Sensitivitas gerak gyro
          const dx = dGamma * 12;
          const dy = dBeta * 12;
          if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
            queueMouseMove(dx, dy);
          }
        }

        function startHold(e) {
          e.preventDefault();
          isHoldingAirMouse = true;
          holdBtn.classList.add('holding');
          vibrate(40);
        }

        function endHold(e) {
          e.preventDefault();
          isHoldingAirMouse = false;
          holdBtn.classList.remove('holding');
          lastGamma = null;
          lastBeta = null;
        }

        holdBtn.addEventListener('touchstart', startHold);
        holdBtn.addEventListener('touchend', endHold);
        holdBtn.addEventListener('mousedown', startHold);
        holdBtn.addEventListener('mouseup', endHold);
      </script>
    </body>
    </html>
    """
}
