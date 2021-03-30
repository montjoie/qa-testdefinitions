#!/bin/sh

if [ -z "$PYARTIPROXY_IP" ];then
	#echo "ERROR: cannot upload, no PYARTIPROXY_IP"
	#exit 1
	# TODO
	echo "DEBUG: No PYARTIPROXY_IP variable, fallback to baylibre one"
	PYARTIPROXY_IP=10.1.1.47
fi

if [ -z "$1" ];then
	echo "ERROR: missing path argument"
	exit 1
fi

if [ -z "$2" ];then
	echo "ERROR: missing filename argument"
	exit 1
fi

curl --silent --show-error -F "filename=$2" -F "data=@$1" http://$PYARTIPROXY_IP:9090/cgi-bin/pyartiproxy.py --output curl.out
if [ $? -ne 0 ];then
	echo "ERROR: with curl"
fi
echo "==========================="
cat curl.out
echo "==========================="
