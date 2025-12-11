<?php
// server/control.php
// Empêcher le cache navigateur
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');
header("Cache-Control: no-store, no-cache, must-revalidate, max-age=0");
header("Cache-Control: post-check=0, pre-check=0", false);
header("Pragma: no-cache");

$stateFile = 'state.json';

// Vérification des permissions
if (file_exists($stateFile) && !is_writable($stateFile)) {
    echo json_encode([
        'status' => 'ERROR', 
        'message' => 'ERREUR PERMISSION: Le serveur ne peut pas écrire dans state.json. Faites un CHMOD 666 ou 777 sur ce fichier via votre FTP.'
    ]);
    exit;
}

// Récupération de l'action (start/stop)
$action = isset($_GET['action']) ? $_GET['action'] : null;

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
    
    if (file_put_contents($stateFile, json_encode($data)) === false) {
        echo json_encode(['status' => 'ERROR', 'message' => 'Echec écriture fichier']);
    } else {
        echo json_encode($data);
    }

} elseif ($action === 'stop') {
    $data = [
        'status' => 'IDLE',
        'target_timestamp' => 0,
        'server_time' => time(),
        'message' => 'En attente...'
    ];
    
    file_put_contents($stateFile, json_encode($data));
    echo json_encode($data);

} else {
    // Lecture simple avec Auto-Reset
    if (file_exists($stateFile)) {
        $content = file_get_contents($stateFile);
        $data = json_decode($content, true);
        
        // Si c'est ARMÉ mais que l'heure est passée depuis plus de 30 secondes
        if (isset($data['status']) && $data['status'] === 'ARMED') {
            if (time() > ($data['target_timestamp'] + 30)) {
                $data = [
                    'status' => 'IDLE',
                    'target_timestamp' => 0,
                    'server_time' => time(),
                    'message' => 'Reset automatique post-event'
                ];
                file_put_contents($stateFile, json_encode($data));
            }
        }
        
        // On ajoute toujours l'heure serveur fraîche
        $data['server_time'] = time();
        echo json_encode($data);
    } else {
        echo json_encode([
            'status' => 'IDLE',
            'server_time' => time()
        ]);
    }
}
?>
