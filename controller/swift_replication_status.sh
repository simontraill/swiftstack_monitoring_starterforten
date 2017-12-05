#!/usr/bin/env bash
# Probe for Swiftstack replication cycle times, taken from postgres on controller
# straill 2016/11/01
 
# Arguments:
#  $1 cluster name
#  $2 replication type (must be one of 'object', 'container', 'account')
 
. /opt/ss/etc/profile.d/01-swiftstack-controller.sh

# Check the Swit cluster with ID 1. You can obtain this via thw controller API if needbe.
CID=1
# Check object replication (we also have account and container replication but these are rarely a cause for concern).
RTYPE=object

# Warning / error threshholds in seconds
YELLOW=1800
RED=3600
 
# PGPASS location
export PGPASSFILE=/home/swiftstack/repstatus/pgpass
[ ! -f $PGPASSFILE ] && PGPASSFILE=/opt/ss/etc/pgpass
 
# Return cluster ID for given cluster name
function cluster_id() {
  CLUSTER_NAME=$1
  psql -t -q -c  'select id from app_cluster where name = '"'""${CLUSTER_NAME}""'"';' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//'
}
 
# Get oldest finish time for a given replicator across the cluster
# Args: $1: cluster ID / $2: replication type (object, container, account)
function repstatus() {
  CLUSTER_ID=$1
  REPTYPE=$2
  psql -t -q -c 'select extract(epoch from MIN(r.finish_time)) from app_nodereplicationstatus as r, app_node as n where r.replicator_type = '"'"${REPTYPE}"'"' and n.cluster_id = '"${CLUSTER_ID}"' and r.node_id = n.id and n.enabled is true;' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//'
}
 
# Given a timestamp return
#    "green" if it is less than $RED seconds in the past
#    "yellow" if it is less than $YELLOW seconds in the past
#    "red" if it is less than $RED seconds in the past
function get_status() {
  TS=$1
  DELTA=$(( $( date +%s ) - $TS ))
  STATUS_MESSAGE="Oldest object replication has been running for $DELTA seconds"
  if [ $DELTA -gt $RED ]; then
    echo "2 swift_replication - CRITICAL - ${STATUS_MESSAGE}"
    return 2
  elif [ $DELTA -gt $YELLOW ]; then
    echo "1 swift_replication - WARNING - ${STATUS_MESSAGE}"
    return 1
  else
    echo "0 swift_replication - OK - ${STATUS_MESSAGE}"
    return 0
  fi
}
 
# Main
get_status "$( repstatus "$CID" "$RTYPE" )"
exit $?
