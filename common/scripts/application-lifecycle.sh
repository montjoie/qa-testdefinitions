#!/bin/sh

set -x

export TERM=dumb
export COLUMNS=1000

AGLDRIVER=agl-driver

while [ $# -ge 1 ]
do
	case $1 in
	-b)
		shift
		BASEURL=$1
		shift
	;;
	*)
		echo "Unknown argument $1"
		exit 1
	;;
	esac
done

if [ -z "$BASEURL" ]; then
	echo "$0: missing BASEURL"
	echo "Usage: $0 -b BASEURL"
	exit 1
fi

do_afm_util()
{
	if [ $SERVICE_USER -eq 1 -o $APPLICATION_USER -eq 1 ];then
		su - $AGLDRIVER -c "afm-util $*"
	else
		afm-util $*
	fi
	return $?
}

wget -q $BASEURL -O index.html
if [ $? -ne 0 ];then
	echo "ERROR: Cannot wget $BASEURL"
	exit 1
fi

grep -o '[a-z-]*.wgt' index.html | sort | uniq |
while read wgtfile
do
	WGTNAME=$(echo $wgtfile | sed 's,.wgt$,,')
	SERVICE_PLATFORM=0
	SERVICE_USER=0
	APPLICATION_USER=0
	echo "DEBUG: fetch $wgtfile"
	wget -q $BASEURL/$wgtfile
	if [ $? -ne 0 ];then
		echo "ERROR: wget from $BASEURL/$wgtfile"
		continue
	fi

	echo "DEBUG: analyse wgt file"
	unzip $wgtfile
	if [ $? -ne 0 ];then
		# TODO Do not fail yet, busybox unzip seems to "fail with success" when checking CRC
		echo "ERROR: cannot unzip $wgtfile"
	fi
	if [ -f config.xml ];then
		grep hidden config.xml
		if [ $? -eq 0 ];then
			echo "DEBUG: hidden package"
		else
			echo "DEBUG: not hidden package"
		fi
		# a service sets urn:AGL:widget:provided-api
		grep "urn:AGL:widget:provided-api" config.xml
		if [ $? -eq 0 ] ; then
		    # we are a service, now determine the scope ...
		    grep "urn:AGL:permission::partner:scope-platform" config.xml
		    if [ $? -eq 0 ];then
			SERVICE_PLATFORM=1
		    else
			SERVICE_USER=1
		    fi
		else
		    # we are an application
		    APPLICATION_USER=1
		    # no other type known (yet)
		fi
	else
		echo "DEBUG: fail to unzip"
	fi

	echo "DEBUG: list current pkgs"
	# TODO mktemp
	LIST='list'
	afm-util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: afm-util list is empty"
		continue
	fi

	echo "DEBUG: check presence of $WGTNAME"
	NAMEID=$(grep id\\\":\\\"${WGTNAME}@ $LIST | cut -d\" -f4 | cut -d\\ -f1)
	if [ ! -z "$NAMEID" ];then
		echo "DEBUG: $WGTNAME already installed as $NAMEID"
		# need to kill then deinstall
		afm-util ps | grep -q $WGTNAME
		if [ $? -eq 0 ];then
			echo "DEBUG: kill $WGTNAME"
			afm-util kill $WGTNAME
			if [ $? -ne 0 ];then
				echo "ERROR: afm-util kill"
				lava-test-case afm-util-pre-kill-$WGTNAME --result fail
				continue
			else
				lava-test-case afm-util-pre-kill-$WGTNAME --result pass
			fi
		else
			echo "DEBUG: no need to kill $WGTNAME"
		fi

		echo "DEBUG: deinstall $WGTNAME"
		afm-util remove $NAMEID
		if [ $? -ne 0 ];then
			echo "ERROR: afm-util remove"
			lava-test-case afm-util-remove-$WGTNAME --result fail
			continue
		else
			lava-test-case afm-util-remove-$WGTNAME --result pass
		fi
	else
		echo "DEBUG: $WGTNAME not installed"
	fi
	grep id $LIST

	echo "DEBUG: install $wgtfile"
	OUT="out"
	afm-util install $wgtfile > $OUT
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util install"
		lava-test-case afm-util-install-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-install-$WGTNAME --result pass
	fi
	# message is like \"added\":\"mediaplayer@0.1\"
	NAMEID=$(grep d\\\":\\\"${WGTNAME}@ $OUT | cut -d\" -f4 | cut -d\\ -f1)
	if [ -z "$NAMEID" ];then
		echo "ERROR: Cannot get nameid"
		continue
	fi
	echo "DEBUG: $WGTNAME is installed as $NAMEID"

	afm-util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: afm-util list is empty"
		continue
	fi
	echo "DEBUG: Verify that $WGTNAME is installed"
	grep -q $NAMEID $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: $WGTNAME is not installed"
		# for debugging, give full output
		echo "DEBUG: start of list"
		cat $LIST
		echo "DEBUG: end of list"
	fi

	afm-util info $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util info"
		lava-test-case afm-util-info-$WGTNAME --result fail
	else
		lava-test-case afm-util-info-$WGTNAME --result pass
	fi

	echo "DEBUG: check if we see the package with systemctl list-units (before start)"
	systemctl list-units --full | grep "afm.*$WGTNAME"
	echo "DEBUG: check if we see the package with systemctl -a (before start)"
	systemctl -a |grep "afm.*$WGTNAME"

	echo "DEBUG: start $NAMEID"
	do_afm_util start $NAMEID > "rid"
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start"
		lava-test-case afm-util-start-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-start-$WGTNAME --result pass
	fi

	echo "DEBUG: check if we see the package with systemctl list-units (after start)"
	systemctl list-units --full | grep "afm.*$WGTNAME"
	echo "DEBUG: check if we see the package with systemctl -a (after start)"
	systemctl -a |grep "afm.*$WGTNAME"

	echo "DEBUG: Get RID for $NAMEID"
	PSLIST="pslist"
	afm-util ps > $PSLIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util ps"
		lava-test-case afm-util-ps-$WGTNAME --result fail
		continue
	else
		cat $PSLIST
		lava-test-case afm-util-ps-$WGTNAME --result pass
	fi
	# TODO, compare RID with the list in $PSLIST"
	RID="$(cat rid)"

	echo "DEBUG: status $NAMEID ($RID)"
	afm-util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util status"
		lava-test-case afm-util-status-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-status-$WGTNAME --result pass
	fi

	echo "DEBUG: kill $NAMEID ($RID)"
	afm-util kill $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util kill"
		lava-test-case afm-util-kill-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-kill-$WGTNAME --result pass
	fi

	echo "DEBUG: start2 $NAMEID"
	do_afm_util start $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start2"
		lava-test-case afm-util-start2-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-start2-$WGTNAME --result pass
	fi
done
