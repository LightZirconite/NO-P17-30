// State
let serverOffset = 0;
let isArmed = false;
let targetTimestamp = 0;
let pollingInterval = null;

// Elements
const els = {
    status: document.getElementById('statusText'),
    time: document.getElementById('serverTime'),
    countdown: document.getElementById('countdown'),
    logs: document.getElementById('logs'),
    overlay: document.getElementById('safetyOverlay'),
    volSlider: document.getElementById('volumeSlider'),
    volValue: document.getElementById('volumeValue'),
    btnArm: document.getElementById('btnArm'),
    btnStop: document.getElementById('btnStop'),
    btnConfirm: document.getElementById('btnConfirm'),
    btnCancel: document.getElementById('btnCancel')
};

// Event Listeners (No inline handlers)
els.volSlider.addEventListener('input', (e) => {
    els.volValue.innerText = e.target.value;
});

els.volSlider.addEventListener('change', (e) => {
    if (isArmed) {
        log("Volume défini pour le prochain lancement.");
    }
});

els.btnArm.addEventListener('click', showConfirm);
els.btnStop.addEventListener('click', () => sendAction('stop'));
els.btnConfirm.addEventListener('click', confirmLaunch);
els.btnCancel.addEventListener('click', hideConfirm);

function log(msg) {
    els.logs.innerText = msg;
    setTimeout(() => els.logs.innerText = "", 3000);
}

function showConfirm() { els.overlay.classList.add('visible'); }
function hideConfirm() { els.overlay.classList.remove('visible'); }

function confirmLaunch() {
    hideConfirm();
    const volume = els.volSlider.value;
    sendAction('start', volume);
}

function sendAction(action, volume = 50) {
    let url = `control.php?action=${action}&t=${Date.now()}`;
    if (action === 'start') {
        url += `&volume=${volume}`;
    }

    fetch(url)
        .then(res => res.json())
        .then(data => {
            if (data.status === 'ERROR') {
                log("Erreur: " + (data.message || "Inconnue"));
                console.error("Server Error:", data);
            } else {
                updateState(data);
                log(action === 'start' ? "Séquence initiée." : "Arrêt d'urgence envoyé.");
            }
        })
        .catch(err => {
            console.error(err);
            log("Erreur communication serveur");
        });
}

function updateState(data) {
    // Sync Time
    if (data.server_time) {
        const now = Math.floor(Date.now() / 1000);
        serverOffset = data.server_time - now;
    }

    // Status
    if (data.status === 'ARMED') {
        isArmed = true;
        targetTimestamp = data.target_timestamp;
        els.status.innerText = "SÉQUENCE ARMÉE";
        els.status.classList.add('armed');
        els.status.classList.remove('idle');
        els.countdown.classList.add('active');
    } else {
        isArmed = false;
        els.status.innerText = "EN ATTENTE";
        els.status.classList.remove('armed');
        els.status.classList.add('idle');
        els.countdown.classList.remove('active');
    }
}

function tick() {
    const now = Math.floor(Date.now() / 1000);
    const estimatedServerTime = now + serverOffset;

    // Update Clock
    const date = new Date(estimatedServerTime * 1000);
    els.time.innerText = date.toLocaleTimeString('fr-FR');

    // Update Countdown
    if (isArmed) {
        const diff = targetTimestamp - estimatedServerTime;
        if (diff > 0) {
            els.countdown.innerText = diff.toFixed(0) + "s";
            els.countdown.style.color = "#ffb86c"; // Orange
        } else if (diff > -5) {
            els.countdown.innerText = "SONNERIE";
            els.countdown.style.color = "#05d5fa"; // Cyan
        } else {
            els.countdown.innerText = "TERMINÉ";
        }
    }
}

function poll() {
    fetch(`control.php?t=${Date.now()}`)
        .then(res => res.json())
        .then(data => updateState(data))
        .catch(e => console.error(e));
}

// Init
setInterval(tick, 100); // Fast UI updates
setInterval(poll, 1000); // Server sync every 1s
poll(); // First check
