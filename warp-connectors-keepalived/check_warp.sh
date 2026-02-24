#!/bin/bash
/usr/bin/warp-cli status | grep -q "Connected"
exit $?