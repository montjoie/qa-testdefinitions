#!/bin/bash

export LANG=C
export TERM=dumb
export COLUMNS=1000

while getopts ":b:d:" option; do
    case "${option}" in
        b)
            if [[ $OPTARG = -* ]]; then
                ((OPTIND--))
                continue
            fi
            BUILD_TAGS=${OPTARG}
            ;;
        d)
            DEVICE_TAGS=${OPTARG}
            ;;
    esac
done

echo "=============================================== Hack timeout"
cp /etc/systemd/system/bluetooth.target.wants/bluetooth.service /tmp/
sed -i 's,=full,=full\nTimeoutSec=1200\nTimeoutStartSec=1200\nExecStartPre=sleep 10,' /etc/systemd/system/bluetooth.target.wants/bluetooth.service
diff -u /tmp/bluetooth.service /etc/systemd/system/bluetooth.target.wants/bluetooth.service

find /etc |grep bluetooth |
while read line
do
echo "=============================================== $line"
cat $line
echo "==============================================="
done

echo "==============================================="
REQUIREDSOCKETS="dbus.socket security-manager.socket"
REQUIREDSERVICES="afm-system-daemon.service connman.service ofono.service weston.service bluetooth.service systemd-modules-load.service avahi-daemon.service neard.service"

ALL="${REQUIREDSOCKETS} ${REQUIREDSERVICES}"
RESULT="unknown"

# add delay for services to fully start
sleep 10

for i in ${ALL} ; do
    echo -e "\n\n########## Test for service ${i} being active ##########\n\n"
    RESULT=""
    if [[ ${i} == "weston.service" ]]; then
        if [[ ${DEVICE_TAGS} != *"screen"* ]] || [[ ${BUILD_TAGS} != *"screen"* ]]; then
            RESULT="skip"
        fi
    fi
    if [[ -z $RESULT ]]; then
        systemctl is-active ${i} >/dev/null 2>&1
        if [ $? -eq 0 ] ; then
            RESULT="pass"
        else
            RESULT="fail"
           echo "==============================================="
           echo "=============================================== journalctl start"
           journalctl -xe
           echo "=============================================== journalctl end"
           dmesg | tail
           echo "==============================================="
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
