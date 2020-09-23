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
set -x
	if [ $SERVICE_USER -eq 1 -o $APPLICATION_USER -eq 1 ];then
		su - $AGLDRIVER -c "afm-util $*"
	else
		afm-util $*
	fi
	return $?
}

do_afm_test()
{
	set -x
	if [ $SERVICE_USER -eq 1 -o $APPLICATION_USER -eq 1 ];then
		su - $AGLDRIVER -c "afm-test -l $*"
	else
		afm-test -l $*
	fi
	return $?
}

# work in tmp folder to allow different users to access files (smack)
TOPDIR=$(mktemp -d)
cd $TOPDIR

if [ ! -f index.html ] ; then
	wget -q $BASEURL -O index.html
	if [ $? -ne 0 ];then
	    echo "ERROR: Cannot wget $BASEURL"
		exit 1
	fi
fi

# first download all files
grep -o '[a-z-]*.wgt' index.html | sort | uniq |
while read wgtfile
do
	# remove extension and the debug state
	echo "DEBUG: fetch $wgtfile"

	if [ ! -f $wgtfile ] ; then
		wget -q $BASEURL/$wgtfile
		if [ $? -ne 0 ];then
			echo "ERROR: wget from $BASEURL/$wgtfile"
			continue
		fi
	fi
	# do adapt security
	chmod -R a+rwx ${TOPDIR}
	chsmack -a "*" ${TOPDIR}/*
done

inspect_wgt() {
	wgtfile=$1
	WGTNAME=$2

	export SERVICE_PLATFORM=0
	export SERVICE_USER=0
	export APPLICATION_USER=0

	CURDIR="$(pwd)"
	ZIPOUT="$(mktemp -d)"
	cd $ZIPOUT

	echo "DEBUG: analyse wgt file"
	unzip $CURDIR/$wgtfile
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
			export SERVICE_PLATFORM=1
		    else
			export SERVICE_USER=1
		    fi
		else
		    # we are an application
		    export APPLICATION_USER=1
		    # no other type known (yet)
		fi
		# the file naming convention is servicename.wgt
		# but some didnt respect it
		export WGTSERVICENAME=$(grep 'id=.*' config.xml | sed 's,^.*id=,id=,' | cut -d= -f2 | cut -d'"' -f2)
		if [ -z "$WGTSERVICENAME" ];then
			echo "WARN: failed to find name in config.xml, fallback to filename"
			export WGTSERVICENAME="$WGTNAME"
		else
			echo "DEBUG: detected service name as $WGTSERVICENAME"
		fi
	else
		echo "DEBUG: fail to unzip"
	fi

	cd $CURDIR
	rm -r $ZIPOUT
}

# check if WGTNAME is running
check_service_running() {
	WGTNAME=$1
	RUNNING=0

	echo "DEBUG: check_service_running with systemctl list-units -full"
	systemctl list-units --full | grep "afm.*$WGTNAME--"
	if [ $? -eq 0 ];then
		RUNNING=1
	fi
	echo "DEBUG: check_service_running with systemctl -a"
	systemctl -a |grep "afm.*$WGTNAME--"
	if [ $? -eq 0 ];then
		if [ $RUNNING -eq 0 ];then
			echo "ERROR: inconsistent results"
		fi
		RUNNING=1
	fi
	return $RUNNING
}

do_release_test() {
	WGTNAME=$1
	wgtfile=$2
	# we need the full name (with -test, -debug etc..) for LAVA test case
	WGTNAMEF=$(echo $2 | sed 's,.wgt,,')

	echo "INFO: do_release_test $WGTNAME $wgtfile"

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

	# SPEC-3599 uninstall homescreen if testing homescreen-demo-ci
	if [ "$WGTSERVICENAME" == 'native-app-qt' ];then
		grep -q \"homescreen\" $LIST
		if [ $? -eq 0 ];then
			echo "INFO: Remove homescreen since we test homescreen-demo-ci"
			afm-util kill 'homescreen'
			afm-util remove 'homescreen'
		else
			echo "INFO: homescreen is not here"
		fi
	fi

	echo "DEBUG: check presence of $WGTNAME"
	NAMEID=$(grep id\\\":\\\"${WGTSERVICENAME}\" $LIST | cut -d\" -f4 | cut -d\\ -f1)
	if [ ! -z "$NAMEID" ];then
		echo "DEBUG: $WGTNAME already installed as $NAMEID"
		# need to kill then deinstall
		do_afm_util ps --all | grep -q $WGTNAME
		if [ $? -eq 0 ];then
			echo "DEBUG: kill $WGTNAME"
			do_afm_util kill $WGTNAME
			if [ $? -ne 0 ];then
				echo "ERROR: afm-util kill"
				#lava-test-case afm-util-pre-kill-$WGTNAME --result fail
				#continue
			#else
			#	lava-test-case afm-util-pre-kill-$WGTNAME --result pass
			fi
		else
			echo "DEBUG: no need to kill $WGTNAME"
		fi

		echo "DEBUG: deinstall $WGTNAME"
		afm-util remove $NAMEID
		if [ $? -ne 0 ];then
			echo "ERROR: afm-util remove"
			#lava-test-case afm-util-remove-$WGTNAMEF --result fail
			journalctl -b | tail -40
			#continue
		else
			lava-test-case afm-util-remove-$WGTNAMEF --result pass
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
		lava-test-case afm-util-install-$WGTNAMEF --result fail
		continue
	else
		lava-test-case afm-util-install-$WGTNAMEF --result pass
	fi
	# message is like \"added\":\"mediaplayer@0.1\"
	NAMEID=$(grep d\\\":\\\"${WGTSERVICENAME}\" $OUT | cut -d\" -f4 | cut -d\\ -f1)
	if [ -z "$NAMEID" ];then
		echo "ERROR: Cannot get nameid"
		echo "DEBUG: ========== DUMPING output =========="
		cat $OUT
		echo "DEBUG: ========== END DUMP =========="
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

	do_afm_util info $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util info"
		lava-test-case afm-util-info-$WGTNAMEF --result fail
	else
		lava-test-case afm-util-info-$WGTNAMEF --result pass
	fi

	echo "DEBUG: check if we see the package with systemctl list-units (before start)"
	systemctl list-units --full | grep "afm.*$WGTNAME--"
	echo "DEBUG: check if we see the package with systemctl -a (before start)"
	systemctl -a |grep "afm.*$WGTNAME--"

	echo "DEBUG: start $NAMEID"
	do_afm_util start $NAMEID > "rid"
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start"
		lava-test-case afm-util-start-$WGTNAMEF --result fail
		journalctl -an 200
		continue
	else
		lava-test-case afm-util-start-$WGTNAMEF --result pass
	fi

	check_service_running $WGTNAME

	echo "DEBUG: Get RID for $NAMEID"
	PSLIST="pslist"
	afm-util ps --all > $PSLIST
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util ps"
		lava-test-case afm-util-ps-$WGTNAMEF --result fail
		continue
	else
		cat $PSLIST
		lava-test-case afm-util-ps-$WGTNAMEF --result pass
	fi
	# TODO, compare RID with the list in $PSLIST"
	RID="$(cat rid)"
	if [ "$RID" == 'null' ];then
		sleep 20
		echo "DEBUG: retry start $NAMEID"
		do_afm_util start $NAMEID > "rid"
		if [ $? -ne 0 ];then
			echo "ERROR: afm-util start"
			lava-test-case afm-util-start-$WGTNAMEF --result fail
			continue
		fi
		RID="$(cat rid)"
	fi

	if [ "$RID" == 'null' ];then
		echo "ERROR: RID is null, service fail to start"
		lava-test-case afm-util-status-$WGTNAMEF --result fail
		continue
	fi

	echo "DEBUG: status $NAMEID ($RID)"
	do_afm_util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util status"
		lava-test-case afm-util-status-$WGTNAMEF --result fail
		continue
	else
		lava-test-case afm-util-status-$WGTNAMEF --result pass
	fi

	echo "DEBUG: kill $NAMEID ($RID)"
	do_afm_util kill $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util kill"
		lava-test-case afm-util-kill-$WGTNAMEF --result fail
		continue
	else
		lava-test-case afm-util-kill-$WGTNAMEF --result pass
	fi

	echo "DEBUG: start2 $NAMEID"
	do_afm_util start $NAMEID > rid
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util start2"
		lava-test-case afm-util-start2-$WGTNAMEF --result fail
		journalctl -an 200
		continue
	else
		lava-test-case afm-util-start2-$WGTNAMEF --result pass
	fi
	RID="$(cat rid)"
	if [ "$RID" == 'null' ];then
		echo "ERROR: RID is null"
		continue
	fi
	sleep 10
	echo "DEBUG: status2 $NAMEID ($RID)"
	do_afm_util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: afm-util status2"
		lava-test-case afm-util-status2-$WGTNAMEF --result fail
		continue
	else
		lava-test-case afm-util-status2-$WGTNAMEF --result pass
	fi
}

WGTNAMES=$(grep -o '[a-z-]*.wgt' index.html | sed 's,.wgt$,,' | sed 's,-debug$,,' | sed 's,-test$,,' | sed 's,-coverage$,,' | sort | uniq)
for WGTNAME in $WGTNAMES
do
	if [ -e $WGTNAME.wgt ];then
		inspect_wgt $WGTNAME.wgt $WGTNAME
		do_release_test $WGTNAME $WGTNAME.wgt
	else
		echo "WARN: cannot find $WGTNAME.wgt"
	fi
	if [ -e $WGTNAME-test.wgt ];then
		# wgt-test do not have the same permissions in the config.xml as the parent wgt
		# so keep the value from last run
		#inspect_wgt $WGTNAME-test.wgt
		check_service_running $WGTNAME
		if [ $? -eq 1 ];then
			do_afm_test $TOPDIR/$WGTNAME-test.wgt
			if [ $? -eq 0 ];then
				lava-test-case run-test-$WGTNAME --result pass
			else
				lava-test-case run-test-$WGTNAME --result fail
			fi
		else
			echo "DEBUG: $WGTNAME is not running, skipping test"
			lava-test-case run-test-$WGTNAME --result skip
		fi
	else
		echo "WARN: cannot find $WGTNAME.wgt"
	fi
	if [ -e $WGTNAME-debug.wgt ];then
		inspect_wgt $WGTNAME-debug.wgt $WGTNAME
		do_release_test $WGTNAME $WGTNAME-debug.wgt
	fi
	if [ -e $WGTNAME-coverage.wgt ];then
		inspect_wgt $WGTNAME-coverage.wgt $WGTNAME
		do_release_test $WGTNAME $WGTNAME-coverage.wgt
		check_service_running $WGTNAME
		if [ $? -eq 1 ];then
			afm-util install $TOPDIR/$WGTNAME-test.wgt
			do_afm_test $TOPDIR/$WGTNAME-test.wgt
			if [ $? -eq 0 ];then
				lava-test-case run-test-$WGTNAME --result pass
			else
				lava-test-case run-test-$WGTNAME --result fail
			fi
		else
			echo "DEBUG: $WGTNAME is not running, skipping test"
			lava-test-case run-test-$WGTNAME --result skip
		fi
	fi
done

