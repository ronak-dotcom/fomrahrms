#!/bin/bash
set -e

# Vercel's build image has no Flutter SDK preinstalled, and build/web is no
# longer committed to git, so this installs Flutter fresh and builds the web
# app on every deploy.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable _flutter_sdk
export PATH="$PATH:$(pwd)/_flutter_sdk/bin"

flutter config --enable-web
flutter pub get

echo "==========================================================="
echo "  flutter test"
echo "==========================================================="
# Blocking: a failing test stops the deploy, so a change to the money rules
# (payroll maths, leave balance, attendance cycle, permission minutes) cannot
# reach production with a broken expectation. The suite was non-blocking
# while its characterisation tests were being reviewed; they now pass.
#
# pipefail so the exit code is flutter's, not tail's.
set -o pipefail
flutter test --reporter expanded 2>&1 | tail -120
set +o pipefail

echo
echo "==========================================================="
echo "  flutter analyze"
echo "==========================================================="
# Scoped to OUR code. The Flutter SDK is cloned into _flutter_sdk inside the
# project, so a bare `flutter analyze` walks the SDK's own packages too — its
# integration_test package alone emits thousands of errors against this SDK
# version, which previously flooded the log past Vercel's 4 MB limit.
#
# Non-blocking: the build below already fails the deploy on a genuine compile
# or type error, so the value here is lints and warnings.
flutter analyze lib test 2>&1 | tail -60 \
  || echo ">>> analyze reported issues (not blocking the deploy)"

echo
echo "==========================================================="
echo "  flutter build web"
echo "==========================================================="
# Blocking (set -e). A compile or type error fails the deploy, so broken code
# cannot reach production even with analyze soft.
flutter build web --release --no-tree-shake-icons
