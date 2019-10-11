#!/bin/sh

if [ ! -e /sys/class/net/can1 ];then
	lava-test-case show_can_modules --result skip
	lava-test-case unload_can_raw_module --result skip
	lava-test-case unload_can_module --result skip
	lava-test-case unload_c_can_platform_module --result skip
	lava-test-case unload_c_can_module --result skipp
	lava-test-case unload_can_dev_module --result skip
	lava-test-case canconfig_can0 --result skip
	lava-test-case load_can_module --result skip
	lava-test-case load_can_raw_module --result skip
	lava-test-case load_c_can_module --result skip
	lava-test-case load_can_dev_module --result skip
	lava-test-case canconfig_can0 --result skip
        exit 0
fi
lsmod | grep can
if [ $? -eq 0 ];then
	lava-test-case show_can_modules --result pass
else
	lava-test-case show_can_modules --result fail
fi

sleep 4

rmmod can_raw
if [ $? -eq 0 ];then
	lava-test-case unload_can_raw_module --result pass
else
	lava-test-case unload_can_raw_module --result fail
fi

rmmod can
if [ $? -eq 0 ];then
	lava-test-case unload_can_module --result pass
else
	lava-test-case unload_can_module --result fail
fi

rmmod c_can_platform
if [ $? -eq 0 ];then
	lava-test-case unload_c_can_platform_module --result pass
else
	lava-test-case unload_c_can_platform_module --result fail
fi

rmmod c_can
if [ $? -eq 0 ];then
	lava-test-case unload_c_can_module --result pass
else
	lava-test-case unload_c_can_module --result fail
fi

rmmod can_dev
if [ $? -eq 0 ];then
	lava-test-case unload_can_dev_module --result pass
else
	lava-test-case unload_can_dev_module --result fail
fi

sleep 5

ip link set can0 type can bitrate 50000
if [ $? -eq 0 ];then
	lava-test-case canconfig_can0 --result fail
else
	lava-test-case canconfig_can0 --result pass
fi


sleep 5

modprobe can
if [ $? -eq 0 ];then
	lava-test-case load_can_module --result pass
else
	lava-test-case load_can_module --result fail
fi

modprobe can_raw
x=$?
sleep 5
if [ $x -eq 0 ];then
	lava-test-case load_can_raw_module --result pass
else
	lava-test-case load_can_raw_module --result fail
fi
sleep 3

modprobe c_can
if [ $? -eq 0 ];then
	lava-test-case load_c_can_module --result pass
else
	lava-test-case load_c_can_module --result fail
fi

modprobe c_can_platform
if [ $? -eq 0 ];then
	lava-test-case load_c_can_platform_module --result pass
else
	lava-test-case load_c_can_platform_module --result fail
fi

modprobe can_dev
if [ $? -eq 0 ];then
	lava-test-case load_can_dev_module --result pass
else
	lava-test-case load_can_dev_module --result fail
fi

sleep 5

#Make sure always that the can interface is down before
#starting the config step.
ip link set can0 down

ip link set can0 type can bitrate 50000
if [ $? -eq 0 ];then
	lava-test-case canconfig_can0 --result pass
else
	lava-test-case canconfig_can0 --result fail
fi

sleep 3
