#!/bin/bash
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE DATABASE mainline_test OWNER mainline;
    GRANT ALL PRIVILEGES ON DATABASE mainline_test TO mainline;

    CREATE ROLE mainline_app LOGIN PASSWORD '${MAINLINE_APP_USER_DATABASE_PASSWORD:-app_password}';
    GRANT CONNECT ON DATABASE $POSTGRES_DB TO mainline_app;
    GRANT CONNECT ON DATABASE mainline_test TO mainline_app;
EOSQL
