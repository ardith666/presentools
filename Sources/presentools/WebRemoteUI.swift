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
          padding: 16px;
        }
        header {
          width: 100%;
          max-width: 420px;
          display: flex;
          justify-content: space-between;
          align-items: center;
          padding: 8px 4px 16px;
        }
        .brand {
          font-size: 1.15rem;
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
        main {
          width: 100%;
          max-width: 420px;
          display: flex;
          flex-direction: column;
          gap: 20px;
          flex: 1;
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
          border-radius: 20px;
          padding: 16px;
        }
        .slide-zone {
          display: grid;
          grid-template-columns: 1fr 1fr;
          gap: 12px;
        }
        .btn-large {
          grid-column: span 2;
          height: 110px;
          background: linear-gradient(145deg, #1e293b, #0f172a);
          border: 1px solid #334155;
          border-radius: 16px;
          font-size: 1.35rem;
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
          height: 76px;
          background: var(--bg-button);
          border: 1px solid var(--border);
          border-radius: 14px;
          font-size: 1rem;
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
          height: 80px;
          background: var(--bg-button);
          border: 1px solid var(--border);
          border-radius: 14px;
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          gap: 6px;
          font-size: 0.9rem;
          font-weight: 600;
          color: var(--text-dim);
          cursor: pointer;
          transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
        }
        .btn-effect span.icon {
          font-size: 1.4rem;
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

      <main>
        <div>
          <div class="section-title">Slide Navigation (Spotlight Clicker)</div>
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
      </main>

      <div class="toast" id="toast"></div>

      <script>
        let currentEffect = 'none';

        function vibrate() {
          if (navigator.vibrate) {
            navigator.vibrate(30);
          }
        }

        function showToast(msg) {
          const t = document.getElementById('toast');
          t.textContent = msg;
          t.classList.add('show');
          setTimeout(() => t.classList.remove('show'), 3500);
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

        setInterval(pollStatus, 1500);
        pollStatus();
      </script>
    </body>
    </html>
    """
}
