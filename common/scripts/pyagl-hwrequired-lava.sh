#!/bin/bash

#pytest --show-capture=no --color=no -k radio /usr/lib/python?.?/site-packages/pyagl/tests/ -L

pytest --color=no /usr/lib/python?.?/site-packages/pyagl/tests/test_radio.py

echo "=== RADIO DONGLE USED ==="
journalctl -b | grep agl-service-radio
echo "=== RADIO DONGLE USED ==="
lsusb
zcat /proc/config.gz | grep USB
