#!/bin/sh

set -e
abort()
{
    echo >&2 '
***************
*** ABORTED ***
***************
'
    echo "Error encountered. Precheck failed..." >&2
    trap : 0
    exit 1
}
trap 'abort' 0

pyv=`python3 -c "import platform;print(platform.python_version())";`
if [ "$pyv" != "3.4.8" ]; then
   echo "You need Python 3.4.8 to run system tests"
   abort
fi

JCLIENTJAR='jclient.jar'
JCLOUDJAR='jcloudclient.jar'

# Installed s3cmd should have support for --max-retries
# This support is available in patched s3cmd rpm built by our team
# See <s3 server source>/rpms/s3cmd/buildrpm.sh
s3cmd --help | grep max-retries >/dev/null 2>&1
if [ "$?" == "0"  ] ;then
    printf "\nCheck S3CMD...OK"
else
    printf "\nInstalled s3cmd version does not support --max-retries."
    printf "\nPlease install patched version built from <s3server src>/rpms/s3cmd/"
    abort
fi

# Check s3iamcli is installed
if command -v s3iamcli >/dev/null 2>&1; then
    printf "\nCheck s3iamcli...OK"
else
    printf "\ns3iamcli not installed"
    printf "\nPlease install s3iamcli using rpm built from <s3server repo>/rpms/s3iamcli/"
    abort
fi

if [ -f $JCLIENTJAR ] ;then
    printf "\nCheck $JCLIENTJAR...OK"
else
    printf "\nCheck $JCLIENTJAR...Not found"
    abort
fi

if [ -f $JCLOUDJAR ] ;then
    printf "\nCheck $JCLOUDJAR...OK"
else
    printf "\nCheck $JCLOUDJAR...Not found"
    abort
fi

printf "\nCheck seagate host entries for system test..."
getent hosts seagatebucket.s3.seagate.com seagate-bucket.s3.seagate.com >/dev/null
getent hosts seagatebucket123.s3.seagate.com seagate.bucket.s3.seagate.com >/dev/null
getent hosts iam.seagate.com sts.seagate.com >/dev/null
printf "OK \n"

trap : 0
