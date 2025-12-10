#!/usr/bin/bash

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