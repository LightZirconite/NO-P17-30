<?php
// server/control.php
// Empêcher le cache navigateur
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");

// Chemins absolus pour éviter les erreurs de dossier courant
$stateFile = __DIR__ . '/state.json';
$debugFile = __DIR__ . '/debug.log';

// Fonction de log basique pour déboguer
function logDebug($msg) {
    global $debugFile;
    // On tente d'écrire, mais on ne bloque pas si ça échoue
    @file_put_contents($debugFile, date('Y-m-d H:i:s') . " - " . $msg . "\n", FILE_APPEND);
}

// Vérification des permissions (création si inexistant)
if (!file_exists($stateFile)) {
    if (@file_put_contents($stateFile, json_encode(['status' => 'IDLE'])) === false) {
        echo json_encode([
            'status' => 'ERROR', 
            'message' => 'ERREUR CRITIQUE: Impossible de créer state.json. Vérifiez les permissions du dossier (CHMOD 777).'
        ]);
        exit;
    }
}

if (!is_writable($stateFile)) {
    echo json_encode([
        'status' => 'ERROR', 
        'message' => 'ERREUR PERMISSION: Le fichier state.json n\'est pas inscriptible (CHMOD 666 requis).'
    ]);
    exit;
}

// Récupération de l'action (start/stop)
$action = isset($_GET['action']) ? $_GET['action'] : null;
logDebug("Requete reçue. Action: " . ($action ? $action : 'read'));

if ($action === 'start') {
    $targetTime = time() + 15;
    $volume = isset($_GET['volume']) ? intval($_GET['volume']) : 50;
    
    $data = [
        'status' => 'ARMED',
        'target_timestamp' => $targetTime,
        'server_time' => time(),
        'volume' => $volume,
        'message' => 'Lancement imminent !'
    ];
    
    $json = json_encode($data);
    if (file_put_contents($stateFile, $json) === false) {
        logDebug("ERREUR ECRITURE START");
        echo json_encode(['status' => 'ERROR', 'message' => 'Echec écriture fichier']);
    } else {
        logDebug("START OK. Target: $targetTime");
        echo $json;
    }

} elseif ($action === 'stop') {
    $data = [
        'status' => 'IDLE',
        'target_timestamp' => 0,
        'server_time' => time(),
        'message' => 'En attente...'
    ];
    
    $json = json_encode($data);
    file_put_contents($stateFile, $json);
    logDebug("STOP OK");
    echo $json;

} else {
    // Lecture simple avec Auto-Reset
    $content = file_get_contents($stateFile);
    $data = json_decode($content, true);
    
    if (!$data) {
        $data = ['status' => 'IDLE'];
    }

    // Si c'est ARMÉ mais que l'heure est passée depuis plus de 5 secondes
    if (isset($data['status']) && $data['status'] === 'ARMED') {
        if (time() > ($data['target_timestamp'] + 5)) {
            logDebug("AUTO-RESET déclenché");
            $data = [
                'status' => 'IDLE',
                'target_timestamp' => 0,
                'server_time' => time(),
                'message' => 'Reset automatique post-event'
            ];
            file_put_contents($stateFile, json_encode($data));
        }
    }
    
    // On ajoute toujours l'heure serveur fraîche pour la synchro
    $data['server_time'] = time();
    echo json_encode($data);
}

