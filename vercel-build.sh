#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Cloning Flutter Stable SDK ==="
# Clone the stable channel with depth 1 to speed up download
git clone https://github.com/flutter/flutter.git -b stable --depth 1

# Add Flutter to the executable PATH
export PATH="$PATH:$(pwd)/flutter/bin"

# Create dummy .env file if it doesn't exist to satisfy the Flutter asset bundler
if [ ! -f .env ]; then
  echo "=== Creating dummy .env file ==="
  echo "REMOVE_BG_API_KEY=" > .env
fi

echo "=== Running Flutter Doctor ==="
flutter doctor

echo "=== Building Flutter Web Application ==="
flutter build web --release

echo "=== Build Completed Successfully ==="
