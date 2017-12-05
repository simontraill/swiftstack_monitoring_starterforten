#!/usr/bin/env bash

# straill (SwiftStack) 2017/11/20
#
# Check utilization of non-swift disks.
# Run this script on every node.

# Configure these.
VERBOSE=false              # Get some output on success

WARN=60
CRIT=70

for DISKUTIL in $( df -h | grep -v '\/srv\/node' | grep -v Filesystem | awk '{print $5}' | sed 's/%//'); do
  if [ $DISKUTIL -gt ${CRIT} ]; then
    echo "2 system_diskspace - CRITICAL - one or more system disks exceed ${CRIT}% utilization on node $( hostname -f )"
    exit 1
  elif [ $DISKUTIL -gt ${WARN} ]; then
    echo "1 system_diskspace - WARNING - one or more system disks exceed ${WARN}% utilization on node $( hostname -f )"
    exit 1
  fi
done

echo "0 system_diskspace - OK - all system disks are beneath ${WARN}% utilization on node $( hostname -f )"
exit 0

