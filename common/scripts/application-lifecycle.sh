#!/bin/sh

export TERM=dumb

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

wget -q $BASEURL -O index.html
if [ $? -ne 0 ];then
	echo "ERROR: Cannot wget $BASEURL"
	exit 1
fi

do_afm_util()
{
	if [ $NEED_SU -eq 1 ];then
		su - agl-driver -c "afm-util $*"
	else
		afm-util $*
	fi
	return $?
}

grep -o '[a-z-]*.wgt' index.html | sort | uniq |
while read wgtfile
do
	NEED_SU=0
	WGTNAME=$(echo $wgtfile | sed 's,.wgt$,,')
	echo "DEBUG: fetch $wgtfile"
	wget -q $BASEURL/$wgtfile
	if [ $? -ne 0 ];then
		echo "ERROR: wget from $BASEURL/$wgtfile"
		continue
	fi

	echo "DEBUG: analyse wgt file"
	unzip $wgtfile
	if [ -e config.xml ];then
		grep hidden config.xml
		if [ $? -eq 0 ];then
			echo "DEBUG: hidden package"
		else
			echo "DEBUG: not hidden package"
		fi
		grep -q 'urn:AGL:permission::partner:scope-platform' config.xml
		if [ $? -ne 0 ];then
			NEED_SU=1
		fi
	else
		echo "DEBUG: fail to unzip"
	fi

	echo "DEBUG: list current pkgs"
	# TODO mktemp
	LIST='list'
	do_afm_util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: do_afm_util list is empty"
		continue
	fi

	echo "DEBUG: check presence of $WGTNAME"
	NAMEID=$(grep id\\\":\\\"${WGTNAME}@ $LIST | cut -d\" -f4 | cut -d\\ -f1)
	if [ ! -z "$NAMEID" ];then
		echo "DEBUG: $WGTNAME already installed as $NAMEID"
		# need to kill then deinstall
		do_afm_util ps | grep -q $WGTNAME
		if [ $? -eq 0 ];then
			echo "DEBUG: kill $WGTNAME"
			do_afm_util kill $WGTNAME
			if [ $? -ne 0 ];then
				echo "ERROR: do_afm_util kill"
				lava-test-case afm-util-pre-kill-$WGTNAME --result fail
				continue
			else
				lava-test-case afm-util-pre-kill-$WGTNAME --result pass
			fi
		else
			echo "DEBUG: no need to kill $WGTNAME"
		fi

		echo "DEBUG: deinstall $WGTNAME"
		do_afm_util remove $NAMEID
		if [ $? -ne 0 ];then
			echo "ERROR: do_afm_util remove"
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
	do_afm_util install $wgtfile > $OUT
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util install"
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

	do_afm_util list --all > $LIST
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util list exit with error"
		continue
	fi
	if [ ! -s "$LIST" ];then
		echo "ERROR: do_afm_util list is empty"
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
		echo "ERROR: do_afm_util info"
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
		echo "ERROR: do_afm_util start"
		lava-test-case afm-util-start-$WGTNAME --result fail
	    echo "==============================================="
	    echo "=============================================== journalctl start"
	    journalctl -xe
	    echo "=============================================== journalctl end"
	    echo "==============================================="
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
	do_afm_util ps > $PSLIST
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util ps"
		lava-test-case afm-util-ps-$WGTNAME --result fail
		continue
	else
		cat $PSLIST
		lava-test-case afm-util-ps-$WGTNAME --result pass
	fi
	# TODO, compare RID with the list in $PSLIST"
	RID="$(cat rid)"

	echo "DEBUG: status $NAMEID ($RID)"
	do_afm_util status $RID
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util status"
		lava-test-case afm-util-status-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-status-$WGTNAME --result pass
	fi

	echo "DEBUG: kill $NAMEID ($RID)"
	do_afm_util kill $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util kill"
		lava-test-case afm-util-kill-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-kill-$WGTNAME --result pass
	fi

	echo "DEBUG: start2 $NAMEID"
	do_afm_util start $NAMEID
	if [ $? -ne 0 ];then
		echo "ERROR: do_afm_util start2"
		lava-test-case afm-util-start2-$WGTNAME --result fail
		continue
	else
		lava-test-case afm-util-start2-$WGTNAME --result pass
	fi
done
