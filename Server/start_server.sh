#!/bin/bash

# Start the isolated audio server runtime.

cd "$(dirname "$0")"

server_runtime_dir="${HOME}/Library/Application Support/SaucyMusiServer"
server_venv_dir="${server_runtime_dir}/venv"

# Install dependencies if needed
if [ ! -f "requirements.txt" ]; then
    echo "requirements.txt not found. Please create it first."
    exit 1
fi

mkdir -p "${server_runtime_dir}"

if [ ! -d "${server_venv_dir}" ]; then
    python3 -m venv "${server_venv_dir}"
fi

echo "Starting music server..."
echo "Press Ctrl+C to stop the server"

exec "${server_venv_dir}/bin/python" server.py
