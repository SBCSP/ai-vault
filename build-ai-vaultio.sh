#!/bin/bash

echo "Pulling dependencies"
flutter pub get

echo "Building MacOS"
flutter build macos

echo "Run MacOS App"
flutter run -d macos
