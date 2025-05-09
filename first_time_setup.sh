#!/bin/bash

# Countdown function
countdown() {
  local seconds=$1
  while [ "$seconds" -gt 0 ]; do # SC2086: Quote variables
    echo -ne "Waiting for $seconds seconds...\r"
    sleep 1
    ((seconds--))
  done
  echo ""
}

echo "Starting Frappe first-time setup"
countdown 3

# Check if .env file exists
if [ -f /home/frappe/press/.env ]; then
  echo ".env file found"
  countdown 3
else
  echo ".env file not found. Creating it from example.env."
  cp /home/frappe/press/example.env /home/frappe/press/.env
  chown frappe:frappe /home/frappe/press/.env
  echo "Please edit the .env file to configure it correctly."
  countdown 3
  echo "Starting nano to edit .env file. Please SAVE and EXIT when finished."
  countdown 3
  nano /home/frappe/press/.env
  echo "Continuing setup after .env file is saved."
fi

# Generate or confirm MySQL password
echo "Checking if MySQL password is set in .env"
countdown 3
if grep -q "MYSQL_ROOT_PASSWORD" /home/frappe/press/.env; then
  echo "MYSQL_ROOT_PASSWORD already set in .env"
else
  echo "MYSQL_ROOT_PASSWORD not set in .env"
  echo "Generating password for MariaDB"
  MYSQL_ROOT_PASSWORD=$(openssl rand -base64 128 | tr -d '=+/[:space:]' | head -c 55)
  echo "MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD" >>/home/frappe/press/.env
fi

# Generate or confirm Frappe admin password
echo "Checking if Frappe admin password is set in .env"
countdown 3
if grep -q "FRAPPE_ADMIN_PASSWORD" /home/frappe/press/.env; then
  echo "FRAPPE_ADMIN_PASSWORD already set in .env"
else
  echo "FRAPPE_ADMIN_PASSWORD not set in .env"
  echo "Generating password for Frappe admin"
  FRAPPE_ADMIN_PASSWORD=$(openssl rand -base64 128 | tr -d '=+/[:space:]' | head -c 55)
  echo "FRAPPE_ADMIN_PASSWORD=$FRAPPE_ADMIN_PASSWORD" >>/home/frappe/press/.env
fi

# Generate or confirm Docker registry password
echo "Checking if Docker registry password is set in .env"
countdown 3
if grep -q "DOCKER_REGISTRY_PASSWORD" /home/frappe/press/.env; then
  echo "DOCKER_REGISTRY_PASSWORD already set in .env"
else
  echo "DOCKER_REGISTRY_PASSWORD not set in .env"
  echo "Generating password for Docker registry"
  DOCKER_REGISTRY_PASSWORD=$(openssl rand -base64 128 | tr -d '=+/[:space:]' | head -c 55)
  echo "DOCKER_REGISTRY_PASSWORD=$DOCKER_REGISTRY_PASSWORD" >>/home/frappe/press/.env
fi

# Start Docker Compose
echo "Starting Docker Compose"
countdown 3
cd /home/frappe/press || {
  echo "Failed to change directory to /home/frappe/press"
  exit 1
}
if ! docker compose up -d; then
  echo "Docker Compose failed to start"
  exit 1
fi

# Wait for services to initialize
echo "Waiting for services to initialize"
countdown 5

# Function to get a variable value from the .env file
get_env_var() {
  dos2unix /home/frappe/press/.env 2>/dev/null
  local var_name=$1
  grep -E "^${var_name}=" /home/frappe/press/.env | cut -d '=' -f2- | tr -d '\r' | xargs
}
# Read required variables from .env
FRAPPE_PRESS_DOMAIN=$(get_env_var "FRAPPE_PRESS_DOMAIN")
FRAPPE_ADMIN_PASSWORD=$(get_env_var "FRAPPE_ADMIN_PASSWORD")
MYSQL_ROOT_PASSWORD=$(get_env_var "MYSQL_ROOT_PASSWORD")
ADMIN_EMAIL=$(get_env_var "ADMIN_EMAIL")

# Validate that required variables are set
if [ -z "$FRAPPE_PRESS_DOMAIN" ] || [ -z "$FRAPPE_ADMIN_PASSWORD" ] || [ -z "$MYSQL_ROOT_PASSWORD" ] || [ -z "$ADMIN_EMAIL" ]; then
  echo "One or more required variables are missing in the .env file"
  exit 1
fi

# Create new Frappe site
echo "Creating Frappe site"
countdown 3
cd /home/frappe/press || {
  echo "Failed to change directory to /home/frappe/press"
  exit 1
}
if ! docker compose exec backend bench new-site "$FRAPPE_PRESS_DOMAIN" \
  --mariadb-user-host-login-scope=% \
  --db-root-username="root" \
  --admin-password="$FRAPPE_ADMIN_PASSWORD" \
  --db-root-password="$MYSQL_ROOT_PASSWORD"; then
  echo "Failed to create new Frappe site"
  exit 1
fi

# Install Press app
echo "Installing Press app"
countdown 3
cd /home/frappe/press || {
  echo "Failed to change directory to /home/frappe/press"
  exit 1
}
if ! docker compose exec backend bench --site "$FRAPPE_PRESS_DOMAIN" install-app press; then
  echo "Failed to install Press app"
  exit 1
fi

# Complete setup wizard
echo "Completing setup wizard"
countdown 3

# Safely construct the JSON string
SETUP_WIZARD_JSON=$(jq -n \
  --arg email "$ADMIN_EMAIL" \
  --arg password "$FRAPPE_ADMIN_PASSWORD" \
  --arg full_name "Administrator" \
  --arg language "english" \
  --arg country "Netherlands" \
  --arg timezone "Europe/Amsterdam" \
  --arg currency "EUR" \
  '{
    args: {
      email: $email,
      password: $password,
      full_name: $full_name,
      language: $language,
      country: $country,
      timezone: $timezone,
      currency: $currency
    }
  }')

# Execute the setup wizard
cd /home/frappe/press && docker compose exec backend bench --site "$FRAPPE_PRESS_DOMAIN" execute \
  frappe.desk.page.setup_wizard.setup_wizard.setup_complete \
  --kwargs "$SETUP_WIZARD_JSON"

# Restart Docker Compose services
docker compose restart

# Clean up .bashrc
sed -i '/first_time_setup.sh/d' ~/.bashrc

# Display .env file
cat /home/frappe/press/.env

# Final message
echo ""
echo "Press installed successfully"
echo ""
