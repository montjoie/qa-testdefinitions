#!/bin/bash

REQUIREDPTESTS="acl attr xmlsec1 libxml2 lua"
# NOT: systemd openssl openssh
# Check if ptest packages are installed

echo "Testing these components: $REQUIREDPTESTS"

command -v ptest-runner >/dev/null 2>&1
if [ $? -ne 0 ] ; then
    lava-test-case ptest-installed --result SKIP
else
    lava-test-case ptest-installed --result PASS

    # Run ptests for specified packages
    for unit in ${REQUIREDPTESTS}; do
	ptest-runner -L ${unit}
    done

    lava-test-case ptest-runtime --measurement $SECONDS --units seconds --result PASS
fi

# Wait for LAVA to parse all the tests from stdout
sleep 15
