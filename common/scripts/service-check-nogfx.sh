#!/bin/bash

export LANG=C
export TERM=dumb
export COLUMNS=1000

REQUIREDSOCKETS="dbus.socket security-manager.socket"
REQUIREDSERVICES="afm-system-daemon.service connman.service ofono.service bluetooth.service"

ALL="${REQUIREDSOCKETS} ${REQUIREDSERVICES}"
RESULT="unknown"

echo "Started with $DEVICE_TAGS and $BUILD_TAGS"
# add delay for services to fully start
sleep 310

for i in ${ALL} ; do
    echo -e "\n\n########## Test for service ${i} being active ##########\n\n"

    systemctl is-active ${i} >/dev/null 2>&1
    if [ $? -eq 0 ] ; then
        RESULT="pass"
    else
        RESULT="fail"
        if [[ ${i} == "bluetooth.service" ]]; then
            if [[ ${DEVICE_TAGS} != *"bluetooth"* ]] || [[ ${BUILD_TAGS} != *"bluetooth"* ]]; then
                RESULT="skip"
            fi
        fi
        if [[ ${i} == "ofono.service" ]]; then
            if [[ ${DEVICE_TAGS} != *"bluetooth"* ]] || [[ ${BUILD_TAGS} != *"bluetooth"* ]]; then
                RESULT="skip"
            fi
        fi
    fi

    lava-test-case ${i} --result ${RESULT}
    systemctl status ${i} || true
    echo -e "\n\n"

    echo -e "\n\n########## Result for service ${i} : $RESULT ##########\n\n"
done


echo "------------------------------------------------"
echo "All systemd units:"
echo "------------------------------------------------"
systemctl list-units || true
echo "------------------------------------------------"
echo "Only the failed systemd units:"
echo "------------------------------------------------"
( systemctl list-units | grep failed ) || true


exit 0
