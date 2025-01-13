#!/bin/bash

set -e

echo "Starting Odoo entrypoint script..."

# Read PASSWORD from file if specified
if [ -v PASSWORD_FILE ]; then
    PASSWORD="$(< $PASSWORD_FILE)"
    echo "Password loaded from PASSWORD_FILE."
fi

# Set the PostgreSQL database host, port, user, and password
: ${HOST:=${DB_HOST}}
: ${PORT:=${DB_PORT}}
: ${USER:=${DB_USER}}
: ${PASSWORD:=${DB_PASSWORD}}

# Log database variables for debugging
echo "DB_HOST: $HOST"
echo "DB_PORT: $PORT"
echo "DB_USER: $USER"
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
check_config "db_host" "$HOST"
check_config "db_port" "$PORT"
check_config "db_user" "$USER"
check_config "db_password" "$PASSWORD"

# Function to test database connectivity
function test_db_connection() {
    echo "Testing database connectivity..."
    PGPASSWORD=$PASSWORD psql -h $HOST -U $USER -p $PORT -c '\l' &>/dev/null
    if [ $? -ne 0 ]; then
        echo "ERROR: Unable to connect to the database at $HOST:$PORT."
        exit 1
    fi
    echo "Database connection successful."
}

case "$1" in
    -- | odoo)
        shift
        if [[ "$1" == "scaffold" ]] ; then
            echo "Running scaffold command..."
            exec odoo "$@"
        else
            echo "Waiting for PostgreSQL to be ready..."
            wait-for-psql.py ${DB_ARGS[@]} --timeout=30 || {
                echo "ERROR: PostgreSQL is not ready after waiting."
                exit 1
            }
            test_db_connection
            echo "Starting Odoo..."
            exec odoo "$@" "${DB_ARGS[@]}"
        fi
        ;;
    -*)
        echo "Waiting for PostgreSQL to be ready..."
        wait-for-psql.py ${DB_ARGS[@]} --timeout=30 || {
            echo "ERROR: PostgreSQL is not ready after waiting."
            exit 1
        }
        test_db_connection
        echo "Starting Odoo with custom parameters..."
        exec odoo "$@" "${DB_ARGS[@]}"
        ;;
    *)
        echo "Executing custom command: $@"
        exec "$@"
        ;;
esac

exit 1
