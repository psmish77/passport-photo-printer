#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "=== Cloning Flutter Stable SDK ==="
# Clone the stable channel with depth 1 to speed up download
git clone https://github.com/flutter/flutter.git -b stable --depth 1

# Add Flutter to the executable PATH
export PATH="$PATH:$(pwd)/flutter/bin"

echo "=== Running Flutter Doctor ==="
flutter doctor

echo "=== Building Flutter Web Application ==="
flutter build web --release

echo "=== Build Completed Successfully ==="
