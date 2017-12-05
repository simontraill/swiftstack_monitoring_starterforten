#!/usr/bin/env bash

# Openstack Swift Basic Throughput test
# straill (SwiftStack) 2017/10/16 
#
# Setup:
#   - Ensure you have a swift account created - see SWIFT_USER below.
#   - Then set the config varibles below for your endpoints and password.
#   - Runs a simple PUT with a known size object; returns success levels based on speed
#   - Runs a simple GET with a known size object; returns success levels based on speed
#   - For more powerful benchmarking - but be careful not to hose your cluster - use https://github.com/swiftstack/ssbench 
#   - You should run this script against every proxy endpoint, and against your load balanced API endpoint.
#       If one of them is slow, and not theo other, you'll be revealing interesting things about your network bottlenecks.
#       It may sound noddy, but thi scenario is surprisingly common with an object store.

# Configure these.
SWIFT_HOST=host.name   # hostname[:port]
SWIFT_PROTO=http           # ( http | https )  
SWIFT_USER=monitoring_user
SWIFT_PASSWORD=XXX

BYTES=20000000            # Test uploads and download using a 20 MByte object
PUT_WARNING=10000000       # Upload rates less than this (in bits per second) will result in a warning
PUT_CRITICAL=1500000      # Upload rates less than this (in bits per second) will result in a critical
GET_CRITICAL=10000000      # Download rates less than this (in bits per second) will result in a critical
GET_WARNING=1500000       # Download rates less than this (in bits per second) will result in a warning

VERBOSE=false              # Get some output on success

# Leave these alone (at least if using local SwiftStack Auth)
SWIFT_AUTH_URL=${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0
SWIFT_STORAGE_URL=${SWIFT_PROTO}://${SWIFT_HOST}/v1/AUTH_${SWIFT_USER}

UPLOAD_FILE=/tmp/swift.throughput
if [ -f ${UPLOAD_FILE} ]; then
  if [ $( du -b ${UPLOAD_FILE} | awk '{print $1}' ) -ne ${BYTES} ]; then 
    rm ${UPLOAD_FILE}
  fi
fi
[ ! -e ${UPLOAD_FILE} ] && fallocate -l ${BYTES} ${UPLOAD_FILE}


CURL_FORMAT_FILE=/tmp/swift.throughput.curl.format
[ ! -e ${CURL_FORMAT_FILE} ] && cat <<'EOF' > ${CURL_FORMAT_FILE}
time_namelookup:  %{time_namelookup} | time_appconnect: %{time_appconnect} | time_total:  %{time_total}\n
EOF

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
  status=$1
  test_name=$2
  result=$3
  PBPS=$4
  GBPS=$5
  if [ $status -eq 0 ]; then
    statustxt=OK
    STATUS_MESSAGE="Swift throughput: ${test_name} for ${SWIFT_STORAGE_URL}"
  elif [ $status -eq 1 ]; then
    statustxt=WARNING
    STATUS_MESSAGE="Swift ${test_name} for ${SWIFT_STORAGE_URL} is a little slow (${result} bits / second)"
  elif [ $status -eq 2 ]; then
    statustxt=CRITICAL
    STATUS_MESSAGE="Swift ${test_name} for ${SWIFT_STORAGE_URL} is a very slow (${result} bits / second)"
  fi
  echo "$status swift_throughput_${SWIFT_HOST} put=${PBPS}|get=${GBPS}  $statustxt - ${STATUS_MESSAGE}"
  exit 0
}

# Get auth token; use default storage URL. 
TOKEN=$( curl -s -i "${SWIFT_PROTO}://${SWIFT_HOST}/auth/v1.0" -H "x-auth-user: ${SWIFT_USER}" -H "x-auth-key: ${SWIFT_PASSWORD}" 2>/dev/null | egrep '^X-Auth-Token' | awk '{print $NF}' | sed 's/\x0D$//' ) # Fun times with carriage returns

# Create a container if required.
curl -s -i -X PUT -H "x-auth-token: ${TOKEN}" "${SWIFT_STORAGE_URL}/throughput_container" | egrep '^(HTTP/1.1 201 Created)|(HTTP/1.1 202 Accepted)' >/dev/null
if [ $? -ne 0 ]; then
  fail "Failed to create swift container ${SWIFT_STORAGE_URL}/throughput_container"
else 
  debug "Created swift container ${SWIFT_STORAGE_URL}/throughput_container OK."
fi

# PUT test.
RES=$( curl -w "@${CURL_FORMAT_FILE}" -X PUT -H "x-auth-token: ${TOKEN}" -s "${SWIFT_STORAGE_URL}/throughput_container/throughput_object"  --data-binary @${UPLOAD_FILE} )
TIME=$( echo $RES | awk '{print $NF}' )
BPS=$( python -c "print '%.2f' % (${BYTES}/${TIME})" )
PUT_BPS=${BPS}
if [ $( python -c "print (${BPS} <= ${PUT_CRITICAL})" ) == 'True' ]; then
  print_result 2 "PUT" ${BPS} ${PUT_BPS} ""
elif [ $( python -c "print (${BPS} <= ${PUT_WARNING})" ) == 'True' ]; then
  print_result 1 "PUT" ${BPS} ${PUT_BPS} ""
fi

# GET test.
RES=$( curl -w "@${CURL_FORMAT_FILE}" -X GET -H "x-auth-token: ${TOKEN}" -s "${SWIFT_STORAGE_URL}/throughput_container/throughput_object" )
TIME=$( echo $RES | awk '{print $NF}' )
BPS=$( python -c "print '%.2f' % (${BYTES}/${TIME})" )
GET_BPS=${BPS}
if [ $( python -c "print (${BPS} <= ${GET_CRITICAL})" ) == 'True' ]; then
  print_result 2 "GET" ${BPS} ${PUT_BPS} ${GET_BPS}
elif [ $( python -c "print (${BPS} <= ${GET_WARNING})" ) == 'True' ]; then
  print_result 1 "GET)" ${BPS} ${PUT_BPS} ${GET_BPS} 
fi

print_result 0 "PUT (${PUT_BPS} bytes/sec) and GET (${GET_BPS} bytes/sec) seem acceptable" "" ${PUT_BPS} ${GET_BPS}
