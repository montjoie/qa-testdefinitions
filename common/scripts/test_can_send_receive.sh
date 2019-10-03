#!/bin/sh


if [ ! -e /sys/class/net/can1 ];then
	lava-test-case canconfig_can0 --result skip
	lava-test-case canconfig_can1 --result skip
	lava-test-case start_can0 --result skip
	lava-test-case start_can1 --result skip
	lava-test-case send_frames_through_can0 --result skip
	lava-test-case receive_frames_through_can1 --result skip
	lava-test-case stop_can0 --result skip
	lava-test-case stop_can1 --result skip
	exit 0
fi

#Make sure always that the can interface is down before
#starting the config step.
ip link set can0 down
ip link set can1 down

#config the can interfaces
ip link set can0 type can bitrate 50000
if [ $? -eq 0 ];then
	lava-test-case canconfig_can0 --result pass
else
	lava-test-case canconfig_can0 --result fail
fi
sleep 3
ip link set can1 type can bitrate 50000
if [ $? -eq 0 ];then
	lava-test-case canconfig_can1 --result pass
else
	lava-test-case canconfig_can1 --result fail
fi
sleep 3
#bring up the devices
ip link set can0 up
if [ $? -eq 0 ];then
	lava-test-case start_can0 --result pass
else
	lava-test-case start_can0 --result fail
fi
sleep 3
ip link set can1 up
if [ $? -eq 0 ];then
	lava-test-case start_can1 --result pass
else
	lava-test-case start_can1 --result fail
fi
sleep 3
#send frames
cangen can0 &
if [ $? -eq 0 ];then
	lava-test-case send_frames_through_can0 --result pass
else
	lava-test-case send_frames_through_can0 --result fail
fi

#receive frames
file_can=$(mktemp)
candump can1 > $file_can &
sleep 3
if [ -s $file_can ];then
	lava-test-case receive_frames_through_can1 --result pass
else
	lava-test-case receive_frames_through_can1 --result fail
fi
rm $file_can

sleep 10
ip link set can0 down
if [ $? -eq 0 ];then
	lava-test-case stop_can0 --result pass
else
	lava-test-case stop_can0 --result fail
fi
sleep 3
ip link set can1 down
if [ $? -eq 0 ];then
	lava-test-case stop_can1 --result pass
else
	lava-test-case stop_can1 --result fail
fi
sleep 5
