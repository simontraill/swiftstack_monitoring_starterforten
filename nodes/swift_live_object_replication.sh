#!/usr/bin/env bash

# Openstack Swift Object Live Replication Test
# straill (SwiftStack) 2017/10/26 
#
# Setup:
#   - Ensure you have a swift account created - see SWIFT_USER below.
#   - Then set the config varibles below for your endpoints and password.
#
# We push a test object into a swift cluster, then use swift-get-nodes to see where the replicas actually are.
# If they are not in the primary parition locations we'd expect, then throw a WARNING error.
# This will use the default storage policy.

# Install this script on every PROXY node - not on the SwiftStack controller.

# Configure these.
SWIFT_HOST=0.0.0.0         # hostname[:port]
SWIFT_PROTO=http           # ( http | https )  
SWIFT_USER=monitoring_user
SWIFT_PASSWORD=XXX
RING_FILE=/etc/swift/object.ring.gz     # This should be /etc/swift/object-${INDEX}.ring.gz, where INDEX is the 
                                        # Storage policy index of your *default* storage policy. See 
                                        # https://www.swiftstack.com/docs/admin/api/cluster.html#view-cluster-details for more details if required.

# The object name to be used for our test.
# We want to be uploading a fresh one every time, so we add the current unixtime to the name .
# When we upload these things we provide an X-Delete-At header 1 minute in the future to ensure Swift cleans them up for us.
NOW=$( date +'%s' )
OBJECT_NAME="AUTH_${SWIFT_USER}/replication_container/replication_object_${NOW}"
DELETE_AT=$(( ${NOW} + 60 ))   # Delete our  test object after 1 minute.

VERBOSE=false              # Get some output on success

. /opt/ss/etc/profile.d/ssnode.sh

# Leave these alone (at least if using local SwiftStack Auth)
SWIFT_AUTH_URL=${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0
SWIFT_STORAGE_URL=${SWIFT_PROTO}://${SWIFT_HOST}/v1/AUTH_${SWIFT_USER}

BYTES=5000000   # 5MB
UPLOAD_FILE=/tmp/swift.replication
if [ -f ${UPLOAD_FILE} ]; then
  if [ $( du -b ${UPLOAD_FILE} | awk '{print $1}' ) -ne ${BYTES} ]; then 
    rm ${UPLOAD_FILE}
  fi
fi
[ ! -e ${UPLOAD_FILE} ] && fallocate -l ${BYTES} ${UPLOAD_FILE}

debug() {
  if [ "$VERBOSE" = 'true' ]; then
    echo $1
  fi
}

fail() {
  echo "1 swift_live_replication - WARNING - Test object ${OBJECT_NAME} was NOT found in all of its primary replica locations after upload."
  exit 1
}


# Get auth token; use default storage URL. 
TOKEN=$( curl -s -i "${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0" -H "x-auth-user: ${SWIFT_USER}" -H "x-auth-key: ${SWIFT_PASSWORD}" 2>/dev/null | egrep '^X-Auth-Token' | awk '{print $NF}' | sed 's/\x0D$//' ) # Fun times with carriage returns

# Create a container if required.
curl -s -i -X PUT -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/replication_container" | egrep '^(HTTP/1.1 201 Created)|(HTTP/1.1 202 Accepted)' >/dev/null
if [ $? -ne 0 ]; then
  fail "Failed to create swift container ${SWIFT_STORAGE_URL}/replication_container"
else 
  debug "Created swift container ${SWIFT_STORAGE_URL}/replication_container OK."
fi

# PUT our object, and set a delete-at header to have it removed in 1 minutes time.
curl -s -i -X PUT -H "X-Delete-At: ${DELETE_AT}" -H "x-auth-token: ${TOKEN}" -s "${SWIFT_STORAGE_URL}/replication_container/replication_object_${NOW}"  --data-binary @${UPLOAD_FILE} | egrep '^(HTTP/1.1 201 Created)|(HTTP/1.1 202 Accepted)' >/dev/null
if [ $? -ne 0 ]; then
  fail "Failed to upload ${SWIFT_STORAGE_URL}/replication_container/replication_object_${NOW}"
fi

# Get the primary replica locations from swift-get-nodes - the places where our object *should be* - and check each in turn to ensure our object has gone there.
export OIFS=${IFS}
export IFS="|"
# Sleep for 10 seconds. With a 5 MB object this should be enouh to ensure all our replicas have a chance to be written.
sleep 10
for CURL_COMMAND in $( swift-get-nodes ${RING_FILE} ${OBJECT_NAME} | egrep '^curl -g ' | grep -v Handoff ); do 
  ( eval ${CURL_COMMAND} -s 2>/dev/null | egrep '^HTTP/1.1 200 OK' ) >/dev/null
  if [ $? -ne 0 ]; then
    fail "Could not find object ${OBJECT_NAME} in one of its primary replica locations."
    exit 1
  fi
done

# If we get here, we're good.
echo "0 swift_live_replication - OK - Test object ${OBJECT_NAME} was found in all of its primary replica locations after upload."
