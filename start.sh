#!/bin/bash
set -e

APP_ROOT=/var/www/html
CONF_FILE=$APP_ROOT/lib/confs/Conf.php
KEY_FILE=$APP_ROOT/lib/confs/cryptokeys/key.ohrm

# Remove one-time debug pages
rm -f $APP_ROOT/aiven-test.php $APP_ROOT/install-log.php $APP_ROOT/db-test.php

# Container filesystem is ephemeral: restore Conf.php from env if missing
if [ ! -f "$CONF_FILE" ]; then
    if [ -z "$OHRM_DB_PASS" ]; then
        echo "WARNING: $CONF_FILE missing and OHRM_DB_PASS not set; app will show installer."
    else
        H="${OHRM_DB_HOST:-mysql-339a7caa-orangehrm-db.a.aivencloud.com}"
        P="${OHRM_DB_PORT:-23149}"
        N="${OHRM_DB_NAME:-orangehrm}"
        U="${OHRM_DB_USER:-avnadmin}"
        esc() { printf '%s' "$1" | sed "s/\\\\/\\\\\\\\/g; s/'/\\\\'/g"; }
        mkdir -p "$(dirname "$CONF_FILE")"
        cat > "$CONF_FILE" <<EOF
<?php

class Conf
{
    private string \$dbHost;
    private string \$dbPort;
    private string \$dbName;
    private string \$dbUser;
    private string \$dbPass;

    public function __construct()
    {
        \$this->dbHost = '$(esc "$H")';
        \$this->dbPort = '$(esc "$P")';
        \$this->dbName = '$(esc "$N")';
        \$this->dbUser = '$(esc "$U")';
        \$this->dbPass = '$(esc "$OHRM_DB_PASS")';
    }

    public function getDbHost(): string
    {
        return \$this->dbHost;
    }

    public function getDbPort(): string
    {
        return \$this->dbPort;
    }

    public function getDbName(): string
    {
        return \$this->dbName;
    }

    public function getDbUser(): string
    {
        return \$this->dbUser;
    }

    public function getDbPass(): string
    {
        return \$this->dbPass;
    }
}
EOF
        echo "Conf.php restored from env."
    fi
fi

# Restore crypto key if missing (128 hex chars, same format as installer)
if [ ! -f "$KEY_FILE" ]; then
    mkdir -p "$(dirname "$KEY_FILE")"
    if [ -n "$OHRM_CRYPTO_KEY" ]; then
        printf '%s' "$OHRM_CRYPTO_KEY" > "$KEY_FILE"
    else
        openssl rand -hex 64 | tr -d '\n' > "$KEY_FILE"
    fi
    # Apache runs as www-data: must be able to read both files
    chown www-data:www-data "$KEY_FILE" 2>/dev/null || true
    chmod 644 "$KEY_FILE"
    echo "key.ohrm restored."
fi

if [ -f "$CONF_FILE" ]; then
    chown www-data:www-data "$CONF_FILE" 2>/dev/null || true
    chmod 644 "$CONF_FILE"
fi

echo "Starting OrangeHRM..."
exec apache2ctl -D FOREGROUND
