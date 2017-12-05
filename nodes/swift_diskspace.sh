#!/usr/bin/env bash

# straill (SwiftStack) 2017/11/20
#
# Check utilization of swift disks.
# Run this script on every node.

# Configure these.
VERBOSE=false              # Get some output on success

WARN=60
CRIT=70

for DISKUTIL in $( df -h | grep '\/srv\/node' | awk '{print $5}' | sed 's/%//'); do
  if [ $DISKUTIL -gt ${CRIT} ]; then
    echo "2 swift_diskspace - CRITICAL - one or more swift disks exceed ${CRIT}% utilization on node $( hostname -f )"
    exit 1
  elif [ $DISKUTIL -gt ${WARN} ]; then
    echo "1 swift_diskspace - WARNING - one or more swift disks exceed ${WARN}% utilization on node $( hostname -f )"
    exit 1
  fi
done

echo "0 swift_diskspace - OK - all swift disks are beneath ${WARN}% utilization on node $( hostname -f )"
exit 0

