#!/bin/sh -e
#
# Copyright (c) 2020 Seagate Technology LLC and/or its Affiliates
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# For any questions about this software or licensing,
# please email opensource@seagate.com or cortx-questions@seagate.com.
#

# S3 server start script in deployment environment.
#   Usage: s3startsystem.sh <process FID>
#             where process FID: S3 server process FID generated by halon.

usage() { echo "Usage: $0 [-F <process FID>] [-P <FID file path>]" \
               "[-C <Config path>]" \
               "(specify [-d] to disable_daemon mode)" 1>&2; exit 1; }

while getopts ":F:P:C:d" x; do
    case "${x}" in
        F)
            fid=${OPTARG}
            ;;
        P)
            ha_config=${OPTARG}
            ;;
        C)
            s3_config_file=${OPTARG}
            ;;
        d)
            disable_daemon=1
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [[ ! -r $ha_config ]]
then
  echo "config file '$ha_config' either doesn't exist or not readable"
  exit 1
else
  source $ha_config
fi


# Ensure default working dir is present
s3_working_dir=`python -c '
import yaml;
print yaml.load(open("'$s3_config_file'"))["S3_SERVER_CONFIG"]["S3_DAEMON_WORKING_DIR"];
' | tr -d '\r\n'
`"s3server-$fid"

mkdir -p $s3_working_dir

# Log dir configured in s3config.yaml
s3_log_dir=`python -c '
import yaml;
print yaml.load(open("'$s3_config_file'"))["S3_SERVER_CONFIG"]["S3_LOG_DIR"];
' | tr -d '\r\n'
`"/s3server-$fid"
mkdir -p $s3_log_dir

#set the maximum size of core file to unlimited
ulimit -c unlimited

#Set the open file limit to 10240
ulimit -n 10240

# Start the s3server
export PATH=$PATH:/opt/seagate/cortx/s3/bin
local_ep=$MOTR_S3SERVER_EP
ha_ep=$MOTR_HA_EP
profile_fid="<$MOTR_PROFILE_FID>"
process_fid="<$MOTR_PROCESS_FID>"
s3port=$MOTR_S3SERVER_PORT


# s3server cmd parameters allowing to fake some motr functionality
# --fake_motr_writeobj - stub for motr write object with all zeros
# --fake_motr_readobj - stub for motr read object with all zeros
# --fake_motr_createidx - stub for motr create idx - does nothing
# --fake_motr_deleteidx - stub for motr delete idx - does nothing
# --fake_motr_getkv - stub for motr get key-value - read from memory hash map
# --fake_motr_putkv - stub for motr put kye-value - stores in memory hash map
# --fake_motr_deletekv - stub for motr delete key-value - deletes from memory hash map
# for proper KV mocking one should use following combination
#    --fake_motr_createidx true --fake_motr_deleteidx true --fake_motr_getkv true --fake_motr_putkv true --fake_motr_deletekv true


extra_options=()
if [[ $disable_daemon == 1 ]]; then
  extra_options=("${extra_options[@]}" --disable_daemon true)
fi

pid_filename="/var/run/s3server.${fid}.pid"
set -x

s3server --s3pidfile "$pid_filename" \
         --motrlocal "$local_ep" --motrha "$ha_ep" \
         --motrprofilefid "$profile_fid" --motrprocessfid "$process_fid" \
         --s3port "$s3port" --log_dir "$s3_log_dir" \
         "${extra_options[@]}"
