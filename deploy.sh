#!/usr/bin/bash
set -e  # Exit on any error

# -- what is my OS?  is it ubuntu or amazon linux?  Anything else, we do not support
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    if [[ "$OS" != "ubuntu" && "$OS" != "amzn" ]]; then
        echo "Error: Unsupported OS. Only Ubuntu and Amazon Linux are supported."
        exit 1
    fi
    echo "Detected OS: $OS"
else
    echo "Error: Cannot detect OS. /etc/os-release not found."
    exit 1
fi

# -- Is nginx installed?  If not, install it (enable the service, and start it)
if ! command -v nginx &> /dev/null; then
    echo "nginx not found. Installing..."
    if [[ "$OS" == "ubuntu" ]]; then
        sudo apt-get update
        sudo apt-get install -y nginx
    elif [[ "$OS" == "amzn" ]]; then
        sudo yum install -y nginx
    fi
    sudo systemctl enable nginx
    sudo systemctl start nginx
    echo "nginx installed and started."
else
    echo "nginx is already installed."
fi

# -- Is Python3 installed?  If not, install it.  set the PY variable to either `python` or `python3` (as some OS's are funny)
if command -v python3 &> /dev/null; then
    PY="python3"
    echo "Python3 found: $(python3 --version)"
elif command -v python &> /dev/null && [[ $(python --version 2>&1) == *"Python 3"* ]]; then
    PY="python"
    echo "Python found: $(python --version)"
else
    echo "Python3 not found. Installing..."
    if [[ "$OS" == "ubuntu" ]]; then
        sudo apt-get update
        sudo apt-get install -y python3 python3-pip python3-venv
    elif [[ "$OS" == "amzn" ]]; then
        sudo yum install -y python3 python3-pip
    fi
    PY="python3"
    echo "Python3 installed: $($PY --version)"
fi

# -- Check the parameters - do we have what we need?

# $1 - slug (what we call this app)
# $2 - working directory
# $3 - servernames (; separated)
# $4 - port

show_help() {
    echo "Usage: $0 <slug> <working_directory> <servernames> <port>"
    echo ""
    echo "Parameters:"
    echo "  slug              - Name/identifier for this application"
    echo "  working_directory - Full path to the application directory"
    echo "  servernames       - Server names separated by semicolons (e.g., 'example.com;www.example.com')"
    echo "  port              - Port number for the application"
    echo ""
    echo "Example:"
    echo "  $0 myapp /var/www/myapp 'example.com;www.example.com' 8000"
    exit 1
}

# Validate all parameters are provided
if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
    echo "Error: Missing required parameters."
    echo ""
    show_help
fi

SLUG="$1"

# Convert working directory to absolute path
if [ ! -d "$2" ]; then
    echo "Error: Working directory does not exist: $2"
    exit 1
fi
WORKING_DIR="$(cd "$2" && pwd)"

SERVERNAMES="${3//;/ }"
PORT="$4"

echo "Configuration:"
echo "  Slug: $SLUG"
echo "  Working Directory: $WORKING_DIR"
echo "  Server Names: $SERVERNAMES"
echo "  Port: $PORT"
echo ""

# Function to process template files and replace variables
write_template() {
    local template_file="$1"
    local output_file="$2"

    if [ ! -f "$template_file" ]; then
        echo "Error: Template file not found: $template_file"
        exit 1
    fi

    echo "Processing template: $template_file -> $output_file"

    # Read template, replace variables, and write to output
    sed -e "s|{{ SLUG }}|${SLUG}|g" \
        -e "s|{{ WORKING_DIR }}|${WORKING_DIR}|g" \
        -e "s|{{ SERVER_NAMES }}|${SERVERNAMES}|g" \
        -e "s|{{ PORT }}|${PORT}|g" \
        -e "s|{{ PY }}|${PY}|g" \
        "$template_file" | sudo tee "$output_file" > /dev/null

    echo "Template processed successfully: $output_file"
}

# == Validate working directory
echo "Validating working directory..."
if [ ! -f "$WORKING_DIR/requirements.txt" ]; then
    echo "Error: requirements.txt not found in: $WORKING_DIR"
    exit 1
fi

echo "Working directory validated: $WORKING_DIR"

# == Create the log directory
echo "Creating log directory..."
sudo mkdir -p "/var/log/$SLUG"
sudo chown -R www-data:www-data "/var/log/$SLUG"
echo "Log directory created: /var/log/$SLUG"

# == Setup Python virtual environment
echo "Setting up Python virtual environment..."
cd "$WORKING_DIR" || exit 1

if [ -d "venv" ]; then
    echo "Virtual environment already exists, removing old one..."
    rm -rf venv
fi

"$PY" -m venv venv
venv/bin/pip install --upgrade pip
venv/bin/pip install -r requirements.txt

# Set permissions so www-data can read and execute
chmod -R 755 "$WORKING_DIR"
echo "Python environment setup complete"

# == Configure gunicorn
echo "Configuring gunicorn..."
write_template templates/gunicorn_config.py.txt "$WORKING_DIR/gunicorn_config.py"

# == Configure nginx
echo "Configuring nginx..."
write_template templates/nginx.conf.txt "/etc/nginx/sites-enabled/$SLUG"

# Test nginx configuration
if sudo nginx -t; then
    sudo systemctl restart nginx
    echo "Nginx configured and restarted successfully"
else
    echo "Error: Nginx configuration test failed"
    exit 1
fi

# == Configure systemd
echo "Configuring systemd service..."
write_template templates/systemd.txt "/etc/systemd/system/$SLUG.service"

sudo systemctl daemon-reload
sudo systemctl enable "$SLUG.service"
sudo systemctl restart "$SLUG.service"
echo "Systemd service configured and started"

# == Deployment complete
echo ""
echo "========================================="
echo "Deployment complete!"
echo "========================================="
echo "Service: $SLUG"
echo "Status: $(sudo systemctl is-active $SLUG.service)"
echo "Logs: sudo journalctl -u $SLUG.service -f"
echo "========================================="