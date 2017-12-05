#!/usr/bin/env bash
# Probe for Swiftstack alerts. If we find ANY unacknowleged alerts in the controller, spit out a WARNING in check_mk.
# straill 2017/11/26
 
. /opt/ss/etc/profile.d/01-swiftstack-controller.sh

# PGPASS location
export PGPASSFILE=/home/swiftstack/repstatus/pgpass
[ ! -f $PGPASSFILE ] && PGPASSFILE=/opt/ss/etc/pgpass
 
# Return a count of unacknowleged alerts from this controller.
function alert_count() {
  psql -t -q -c  'select COUNT(*) from app_alert where app_alert.acknowledged = '"'""f""'"';' -d ssman 2>&1 | head -1 | sed 's/^\s*//' | sed 's/\..*$//'
}
 
function get_status() {
  COUNT=$1
  if [ "X${COUNT}" == "X" ]; then
    COUNT=0
  fi
  STATUS_MESSAGE="No unacknowleged alerts were found on the SwiftStack Controller."
  if [ $COUNT -gt 0 ]; then
    echo "1 swiftstack_alerts - WARNING - ${COUNT} unacknowleged alerts were found on the SwiftStack controller"
    return 1
  else
    echo "0 swiftstack_alerts - OK - ${STATUS_MESSAGE}"
    return 0
  fi
}
 
# Main
get_status "$( alert_count )"
exit $?

