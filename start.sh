#!/bin/bash
set -e

# Diagnostic page: tests DNS + TCP + PDO (plain/SSL) to Aiven MySQL.
# Password is NOT baked in — pass via ?pass= query param.
cat > /var/www/html/aiven-test.php <<'PHPEOF'
<?php
header('Content-Type: text/plain; charset=utf-8');
$host = $_GET['host'] ?? 'mysql-339a7caa-orangehrm-db.a.aivencloud.com';
$port = (int)($_GET['port'] ?? 23149);
$user = $_GET['user'] ?? 'avnadmin';
$db   = $_GET['db'] ?? 'defaultdb';
$pass = $_GET['pass'] ?? '';

echo "host=$host port=$port user=$user db=$db pass=" . ($pass === '' ? '(empty!)' : '(set, len ' . strlen($pass) . ')') . "\n\n";

echo "[1] DNS:\n";
$ip = gethostbyname($host);
echo ($ip !== $host ? "OK $ip" : "FAIL (unresolved)") . "\n\n";

echo "[2] TCP fsockopen (10s):\n";
$fp = @fsockopen($host, $port, $errno, $errstr, 10);
echo ($fp ? "OK connected" : "FAIL $errno $errstr") . "\n";
if ($fp) {
    fclose($fp);
}
echo "\n";

if ($pass === '') {
    echo "Add ?pass=YOUR_AIVEN_PASSWORD to run PDO tests.\n";
    exit;
}

echo "[3] PDO plain:\n";
try {
    $pdo = new PDO(
        "mysql:host=$host;port=$port;dbname=$db;charset=utf8mb4",
        $user,
        $pass,
        [PDO::ATTR_TIMEOUT => 10, PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );
    echo "OK " . $pdo->query('SELECT VERSION()')->fetchColumn() . "\n";
} catch (Throwable $e) {
    echo "FAIL [" . $e->getCode() . "] " . $e->getMessage() . "\n";
}

echo "\n[4] PDO SSL (system CA, verify off):\n";
try {
    $pdo = new PDO(
        "mysql:host=$host;port=$port;dbname=$db;charset=utf8mb4",
        $user,
        $pass,
        [
            PDO::ATTR_TIMEOUT => 10,
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::MYSQL_ATTR_SSL_CA => '/etc/ssl/certs/ca-certificates.crt',
            PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT => false,
        ]
    );
    echo "OK " . $pdo->query('SELECT VERSION()')->fetchColumn() . "\n";
} catch (Throwable $e) {
    echo "FAIL [" . $e->getCode() . "] " . $e->getMessage() . "\n";
}

echo "\n[5] PHP " . PHP_VERSION
    . " pdo_mysql=" . (extension_loaded('pdo_mysql') ? 'yes' : 'NO')
    . " openssl=" . (extension_loaded('openssl') ? 'yes' : 'NO')
    . " ca_bundle=" . (file_exists('/etc/ssl/certs/ca-certificates.crt') ? 'yes' : 'NO') . "\n";
PHPEOF

echo "Starting OrangeHRM (no local database)..."
exec apache2ctl -D FOREGROUND
