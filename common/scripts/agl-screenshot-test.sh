#!/bin/bash

set -x

REF_IMAGE="$1"

if [ -z "${REF_IMAGE}" ]; then
	echo "No reference image passed"
	exit 125
fi

if [ ! -f "${REF_IMAGE}" ]; then
	echo "Reference image is not found"
	exit 125
fi

# Enable the test picture and disable cursor and any other application from being displayed
sed -i '/^\[core\]/a activate-by-default=false' /etc/xdg/weston/weston.ini
# setup homescreen env variable
sed -i '/^\[core\]/a hide-cursor=true' /etc/xdg/weston/weston.ini
# enable red/green/blue test screen
echo 'HOMESCREEN_DEMO_CI=1' > /etc/afm/unit.env.d/screenshot
sync
sleep 2
# restart weston@display
systemctl restart weston@display.service
sleep 60

if test ! grep -q 'Usable area:' /run/platform/display/compositor.log ; then
sleep 60
fi
if test ! grep -q 'Usable area:' /run/platform/display/compositor.log ; then
cat /run/platform/display/compositor.log
echo "CONTINUING ANYWAY !"
fi


AGL_SCREENSHOOTER=/usr/bin/agl-screenshooter

if [ -z "$AGL_SCREENSHOOTER" ]; then
	echo "Failed to find agl-screenshooter. Compositor too old?"
	exit 127
fi

#echo "Found agl-screenshoooter in $AGL_SCREENSHOOTER"
rm -rf agl-screenshot-*.png

if $AGL_SCREENSHOOTER; then
	echo "Screenshot taken"
else
	exit 127
fi

REF_IMAGE_SHA1SUM=`sha1sum ${REF_IMAGE} | awk -F ' ' '{print $1}'`
IMAGE_SHA1SUM=`sha1sum agl-screenshot-*.png | awk -F ' ' '{print $1}'`

if [ "${REF_IMAGE_SHA1SUM}" == "${IMAGE_SHA1SUM}" ]; then
	echo "Screenshot matches the reference image" 
	FINALRET=0
else
	echo "Screenshot does not match the reference image" 
	FINALRET=127
	for i in agl-screenshot-*.png ${REF_IMAGE} ; do
		set +x
		curl --upload-file "$i" https://transfer.sh/$(basename "$i") && echo ""
		set -x
	done
	echo "#########################"
	cat /run/platform/display/*.log
	echo "#########################"
	journalctl -b --no-pager -a 
	echo "#########################"
fi


# cleanup
sed -i '/activate-by-default=false/d' /etc/xdg/weston/weston.ini
sed -i '/hide-cursor=true/d' /etc/xdg/weston/weston.ini
#rm -rf /etc/systemd/system/weston@.service.d
rm -rf /etc/afm/unit.env.d/screenshot
systemctl daemon-reload
sync
sleep 2
systemctl restart weston@display.service
sleep 5

exit $FINALRET
