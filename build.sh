#!/bin/sh
rm -rf build
mkdir build
cd build
cmake ..
make package
cp uv-0.9.9-Linux.deb /tmp/
chmod 644 /tmp/uv-0.9.9-Linux.deb
echo "Package ready: /tmp/uv-0.9.9-Linux.deb"
echo "Install with: sudo apt install /tmp/uv-0.9.9-Linux.deb"