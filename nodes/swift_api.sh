#!/usr/bin/env bash

# Openstack Swift Basic API tests for check_mk
# straill (SwiftStack) 2017/10/16 
#
# Setup:
#   - Ensure you have a swift account created - see SWIFT_USER below.
#   - Then set the config varibles below for your endpoints and password.
#   - Runs basic functional test set using some (ugly) cURL commands; returns status in check_mk format
#   - Failures will cause us to immediately bail and return bad status

# Configure these.
SWIFT_HOST=0.0.0.0       # hostname[:port]
SWIFT_PROTO=http           # ( http | https )  
SWIFT_USER=monitoring_user
SWIFT_PASSWORD=XXX

# Overwrite system hostid command to give something unique
hostid() {
  ip a | grep link/ether | head -1 | awk '{print $2}'
}
EC_GRACE=10              # Sleep time in seconds to wait after performing an eventually-consistent operation (PUTs or DELETEs below)

VERBOSE=false              # Get some output on success

# Leave these alone (at least if using local SwiftStack Auth)
SWIFT_AUTH_URL=${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0
SWIFT_STORAGE_URL=${SWIFT_PROTO}://${SWIFT_HOST}/v1/AUTH_${SWIFT_USER}

export PATH=/opt/ss/bin:$PATH
export PYTHONPATH=/opt/ss/lib/python2.7
TMPFILE=/tmp/swift.monitoring.$$
trap "rm ${TMPFILE} >/dev/null 2>&1" INT QUIT EXIT TERM

function debug() {
  if [ $VERBOSE == 'true' ]; then
    echo $1
  fi
}

function fail() {
  FAILED=$1
  print_result
  exit 1
}

function print_result() {
  if [ "X${FAILED}" == "X" ]; then
    status=0
    statustxt=OK
    STATUS_MESSAGE="All Swift API tests passed OK"
  else 
    status=2
    statustxt=CRITICAL
    STATUS_MESSAGE=$FAILED
  fi
  echo "$status swiftapi_${SWIFT_HOST} -  $statustxt - ${STATUS_MESSAGE}"
  exit 0
}

# Get auth token; use default storage URL. 
TOKEN=$( curl -s -i "${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0" -H "x-auth-user: ${SWIFT_USER}" -H "x-auth-key: ${SWIFT_PASSWORD}" 2>/dev/null | egrep '^X-Auth-Token' | awk '{print $NF}' | sed 's/\x0D$//' )

# We're just ennumerating headline items at the API ref: Openstack Swift API reference at https://developer.openstack.org/api-ref/object-store/
# Each test here should be sufficient to ensure everything is basically working, though we don't test higher order stuff (quotas for example)
# because doing so would step outside of our remit of "tests as monitoring".

# /healthcheck
# "When I GET the /heathcheck endpoint, the message body should consists entirely of the message "OK"
if [ $( curl -s ${SWIFT_HOST}/healthcheck 2>/dev/null ) != "OK" ]; then 
  fail "curl ${SWIFT_HOST}/healthcheck did not return 'OK' in the message body"
else 
  debug "/healthcheck OK".
fi

# /info
# "A GET request to the /info endpoint should return a JSON message body containing - amongst other things - the swift version number"
SV=$( curl -s http://${SWIFT_HOST}/info 2>/dev/null | /opt/ss/bin/python -c 'import sys; import json; j = json.load(sys.stdin); print j["swift"]["version"]' )
if ( ! echo ${SV} | grep '[0-9]\.' >/dev/null ); then 
  fail "curl ${SWIFT_HOST}/info did not return a Swift version number"
else 
  debug "/info OK".
fi

# GET Account
# "GET account should return a HTTP 200/OK"
curl -s -i -X GET -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}" | egrep '^HTTP/1.1 200 OK' >/dev/null
if [ $? -ne 0 ]; then 
  fail "Account GET did not return 200 OK"
else
  debug "Account GET response OK"
fi
 
# "GET account with the format=json urlparam should return a list"
RES=$( curl -s -X GET -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}?format=json" | /opt/ss/bin/python -c 'import sys; import json; j = json.load(sys.stdin); print isinstance(j,list)' )
if [ ${RES} != 'True' ]; then 
  fail "Account GET did not return a list"
else
  debug "Account GET returns a list"
fi

TS=$( date +%s )
# "POST account with a given user metadata header should return a HTTP 204 No content"
curl -s -i -X POST -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}" -H "x-account-meta-timestamp: ${TS}" >$TMPFILE && cat $TMPFILE  | egrep '^HTTP/1.1 204 No Content' > /dev/null
if [ $? -ne 0 ]; then
  fail "Account POST did not return 204 No content: response: $( cat $TMPFILE )"
  debug "Account POST response OK"
fi
 
# "HEAD account should return HTTP 204/No Content"
curl -s -i -X HEAD -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}" -H "x-newest: true" > $TMPFILE && cat $TMPFILE | egrep '^HTTP/1.1 204 No Content' >/dev/null
if [ $? -ne 0 ]; then
  fail "Account HEAD did not return 204 No content: response: $( cat $TMPFILE )"
else 
  debug "Account HEAD response OK"
fi

# PUT Container
# "PUT container should return a HTTP 201/Created or HTTP/1.1 202 Accepted"
curl -s -i -X PUT -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)" >$TMPFILE && cat $TMPFILE | egrep '^(HTTP/1.1 201 Created)|(HTTP/1.1 202 Accepted)' >/dev/null
if [ $? -ne 0 ]; then 
  fail "Container PUT did not return 201 Created or 204 Accepted: response: $( cat $TMPFILE )"
else
  debug "Container PUT response OK"
fi

# Allow eventually-consistent operations to bed in a little.
sleep ${EC_GRACE}
 
# GET Container
# "GET container should return a HTTP 200/OK or HTTP/1.1 204 No Content"
curl -s -i -X GET -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)" >$TMPFILE && cat $TMPFILE | egrep '^(HTTP/1.1 200 OK)|(HTTP/1.1 204 No Content)' >/dev/null
if [ $? -ne 0 ]; then 
  fail "Container GET did not return 200 OK: response: $( cat $TMPFILE )"
else
  debug "Container GET response OK"
fi

TS=$( date +%s )
# "POST container with a given user metadata header should return a HTTP 204 No content"
curl -s -i -X POST -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)" -H "x-container-meta-timestamp: ${TS}" >$TMPFILE && cat $TMPFILE | egrep '^HTTP/1.1 204 No Content' >/dev/null
if [ $? -ne 0 ]; then
  fail "Container POST did not return 204 No content: response: $( cat $TMPFILE )"
else
  debug "Container POST response OK"
fi
 
# "HEAD container should return HTTP 204/No Content"
curl -s -i -X HEAD -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)" -H "x-newest: true" >$TMPFILE && cat $TMPFILE | egrep '^HTTP/1.1 204 No Content' >/dev/null
if [ $? -ne 0 ]; then
  fail "Container HEAD did not return 204 No content: response: $( cat $TMPFILE )"
else 
  debug "Container HEAD returned HTTP 204 No Content."
fi

# PUT Object
# "PUT object should return a HTTP 201/Created or HTTP/1.1 202 Accepted"
curl -s -i -X PUT -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)/objecttest" --data-binary 1234 >$TMPFILE && cat $TMPFILE | egrep '^(HTTP/1.1 201 Created)|(HTTP/1.1 202 Accepted)' >/dev/null
if [ $? -ne 0 ]; then 
  fail "Object PUT did not return 201 Created or 202 Accepted: response: $( cat $TMPFILE )"
else
  debug "Object PUT response OK"
fi
 
# Allow eventually-consistent operations to bed in a little.
sleep ${EC_GRACE}

# GET Object
# "GET object should return a HTTP 200/OK or HTTP/1.1 204 No Content"
curl -s -i -X GET -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)/objecttest" >$TMPFILE && cat $TMPFILE | egrep '^(HTTP/1.1 200 OK)|(HTTP/1.1 204 No Content)' >/dev/null
if [ $? -ne 0 ]; then 
  fail "Object GET did not return 200 OK: response: $( cat $TMPFILE )"
else
  debug "Object GET response OK"
fi
 
TS=$( date +%s )
# "POST object with a given user metadata header should return a HTTP 202 Accepted"
curl -s -i -X POST -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)/objecttest" -H "x-object-meta-timestamp: ${TS}" > $TMPFILE && cat $TMPFILE | egrep '^HTTP/1.1 202 Accepted' >/dev/null
if [ $? -ne 0 ]; then
  fail "Object POST did not return 202 Accepted: response: $( cat $TMPFILE )"
else
  debug "Object POST response OK"
fi
 
# "HEAD object should return HTTP 200/OK"
curl -s -i --head -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)/objecttest" -H "x-newest: true" > $TMPFILE && cat $TMPFILE | egrep '^HTTP/1.1 200 OK' >/dev/null
if [ $? -ne 0 ]; then
  fail "Object HEAD did not return 200 OK: response: $( cat $TMPFILE )"
else 
  debug "Object HEAD response OK"
fi

# "DELETE object should return HTTP 204/No Content
curl -s -i -X DELETE -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)/objecttest" -H "x-newest: true" > $TMPFILE &&  cat $TMPFILE | egrep '^HTTP/1.1 204 No Content' >/dev/null
if [ $? -ne 0 ]; then
  fail "Object DELETE did not return 204 No Content: response: $( cat $TMPFILE )"
else 
  debug "Object DELETE response OK"
fi

# Allow eventually-consistent operations to bed in a little.
sleep ${EC_GRACE}

# "DELETE container should return HTTP 204/No Content or HTTP/1.1 409 Conflict if objects present"
curl -s -i -X DELETE -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/containertest_$(hostid)" -H "x-newest: true" >$TMPFILE && cat $TMPFILE | egrep '^(HTTP/1.1 204 No Content)|(HTTP/1.1 409 Conflict)' >/dev/null
if [ $? -ne 0 ]; then
  fail "Container DELETE did not return 204 No Content nor 409 Conflict: response: $( cat $TMPFILE )"
else 
  debug "Container DELETE response OK"
fi


print_result

