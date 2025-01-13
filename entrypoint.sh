#!/bin/bash

set -e

echo "Starting Odoo entrypoint script..."

# Ensure all necessary environment variables are set
: ${DB_HOST:?"DB_HOST is required"}
: ${DB_PORT:?"DB_PORT is required"}
: ${DB_USER:?"DB_USER is required"}
: ${DB_PASSWORD:?"DB_PASSWORD is required"}
: ${DB_NAME:?"DB_NAME is required"}

# Log database variables for debugging
echo "DB_HOST: $DB_HOST"
echo "DB_PORT: $DB_PORT"
echo "DB_USER: $DB_USER"
echo "DB_PASSWORD: [hidden]"

DB_ARGS=()

function check_config() {
    param="$1"
    value="$2"
    if grep -q -E "^\s*\b${param}\b\s*=" "$ODOO_RC" ; then
        value=$(grep -E "^\s*\b${param}\b\s*=" "$ODOO_RC" | cut -d " " -f3 | sed 's/["\n\r]//g')
        echo "Using ${param} from config file: $value"
    else
        echo "Using ${param} from environment: $value"
    fi
    DB_ARGS+=("--${param}")
    DB_ARGS+=("${value}")
}

# Check if database parameters exist in the config file or environment
check_config "db_host" "$DB_HOST"
check_config "db_port" "$DB_PORT"
check_config "db_user" "$DB_USER"
check_config "db_password" "$DB_PASSWORD"
check_config "db_name" "$DB_NAME"

# Function to test database connectivity
function test_db_connection() {
    echo "Testing database connectivity..."
    PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -p $DB_PORT -d $DB_NAME -c '\l' &>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to connect to the database at $DB_HOST:$DB_PORT."
        exit 1
    fi
    echo "Database connection successful."
}

# Create an odoo.conf file to pass DB settings to Odoo
ODOO_CONF="/etc/odoo/odoo.conf"
echo "[options]" > $ODOO_CONF
echo "db_host = $DB_HOST" >> $ODOO_CONF
echo "db_port = $DB_PORT" >> $ODOO_CONF
echo "db_user = $DB_USER" >> $ODOO_CONF
echo "db_password = $DB_PASSWORD" >> $ODOO_CONF
echo "db_name = $DB_NAME" >> $ODOO_CONF

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            echo "Running scaffold command..."
            exec odoo "$@"
        else
            echo "Waiting for PostgreSQL to be ready..."
            wait-for-psql.py --db_host $DB_HOST --db_port $DB_PORT --db_user $DB_USER --db_password $DB_PASSWORD --timeout=30 || {
                echo "ERROR: PostgreSQL is not ready after waiting."
                exit 1
            }
            test_db_connection
            echo "Starting Odoo..."
            exec odoo --config $ODOO_CONF "$@"
        fi
        ;;

    -*)
        echo "Waiting for PostgreSQL to be ready..."
        wait-for-psql.py --db_host $DB_HOST --db_port $DB_PORT --db_user $DB_USER --db_password $DB_PASSWORD --timeout=30 || {
            echo "ERROR: PostgreSQL is not ready after waiting."
            exit 1
        }
        test_db_connection
        echo "Starting Odoo with custom parameters..."
        exec odoo --config $ODOO_CONF "$@" "${DB_ARGS[@]}"
        ;;

    *)
        echo "Executing custom command: $@"
        exec "$@"
        ;;

esac

exit 1
