#!/usr/bin/env bash
# Check a given storage policy dispersion. If non-zero, return a warning.
# straill 2017/11/26
 
. /opt/ss/etc/profile.d/01-swiftstack-controller.sh


# Configure me here.
# Usage note: when you change your storage layout, the dispersion of your storage policy WILL BE NON ZERO for some time.
# Further, if your cluster layout is not entirely balanced across failure domains (same amount of disks and nodes in each, and each disk has the same size), dispersion will increase. This doesn't indicate a cluster failure - just that swift is either rebalancing or doing the best it can with the storage it's been given.
CLUSTER_NAME=Cluster_Name
POLICY_NAME="Standard-Replica"
DISPERSION_LIMIT=0.0 # Dispersion values greater than this from the ring builder file will result in a warning.

# PGPASS location
export PGPASSFILE=/home/swiftstack/repstatus/pgpass
[ ! -f $PGPASSFILE ] && PGPASSFILE=/opt/ss/etc/pgpass
 
# Return the uuid of a cluster given its name
function cluster_uuid() {
  _CLUSTER_NAME=$1
  psql -t -q -c  'select uuid from app_cluster where name = '"'""${_CLUSTER_NAME}""'"';' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//'
}

# Return the id of a cluster given its name
function cluster_id() {
  _CLUSTER_NAME=$1
  psql -t -q -c  'select id from app_cluster where name = '"'""${_CLUSTER_NAME}""'"';' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//'
}

# Return the builder file used for a storage policy, given the policy name.
function builder_file() {
  _CLUSTER_NAME=$1
  _CLUSTER_ID=$( cluster_id ${_CLUSTER_NAME} )
  _POLICY_NAME=$2
  INDEX=$( psql -t -q -c  'select storage_policy_index from app_ring where cluster_id = '"'""${_CLUSTER_ID}""'"' and name = '"'""${_POLICY_NAME}""'"';' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//' )
  if [ $INDEX -eq 0 ]; then
    echo object.builder
  else
    echo object-${INDEX}.builder
  fi
}

function get_dispersion() {
  _CLUSTER_NAME=$1
  _POLICY_NAME=$2

  UUID=$( cluster_uuid ${_CLUSTER_NAME} )
  BUILDER=$( builder_file ${_CLUSTER_NAME} ${_POLICY_NAME} )

  swift-ring-builder /opt/ss/builder_configs/${UUID}/${BUILDER} dispersion | grep Dispersion | awk '{print $3}' | sed 's/,//'
}
 
function get_status() {
  _DISPERSION=$( get_dispersion "${CLUSTER_NAME}" "${POLICY_NAME}" )
  if [ "X${_DISPERSION}" == "X" ]; then 
    _DISPERSION=" "  # Force an error
  fi
  DISPERSION_IS_HIGH=$( python -c "print float(${_DISPERSION}) > float(${DISPERSION_LIMIT})" )
  if [ $? -eq 0 ]; then
    if [ "${DISPERSION_IS_HIGH}" == "True" ]; then
      echo "1 swiftstack_dispersion - WARNING - Ring dispersion for policy ${STORAGE_POLICY} is ${_DISPERSION}; something may be up unless you have modified your storage layout"
      return 1
    fi
  fi
  echo "0 swiftstack_dispersion - OK - Ring dispersion for policy ${STORAGE_POLICY} is ${_DISPERSION}"
  return 0
}
 
# Main
get_status
exit $?
