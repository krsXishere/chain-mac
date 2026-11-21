#!/bin/sh
set -e
cd "$(dirname "$0")/.."
swift build -c release --product ChainMac
echo "release build OK"
