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

#!/bin/sh
# Simple helper script to rebuild all s3 related binaries & install.
set -e

usage() {
  echo 'Usage: ./rebuildall.sh [--no-motr-rpm][--use-build-cache][--no-check-code]'
  echo '                       [--no-clean-build][--no-s3ut-build][--no-s3mempoolut-build][--no-s3mempoolmgrut-build]'
  echo '                       [--no-s3server-build][--no-motrkvscli-build][--no-base64-encoder-decoder-build][--no-auth-build]'
  echo '                       [--no-jclient-build][--no-jcloudclient-build][--no-java-tests]'
  echo '                       [--no-install][--just-gen-build-file][--valgrind_memcheck]'
  echo '                       [--bazel_cpu_usage_limit <max_cpu_percentage>][--bazel_ram_usage_limit <max_ram_percentage>]'
  echo '                       [--help]'
  echo 'Optional params as below:'
  echo '          --no-motr-rpm              : Use motr libs from source code (third_party/motr) location'
  echo '                                       Default is (false) i.e. use motr libs from pre-installed'
  echo '                                       motr rpm location (/usr/lib64)'
  echo '          --use-build-cache          : Use build cache for third_party and motr, Default (false)'
  echo '                                      If cache is missing, third_party and motr will be rebuilt'
  echo '                                      Ensuring consistency of cache is responsibility of caller'
  echo '          --no-check-code            : Do not check code for formatting style, Default (false)'
  echo '          --no-clean-build           : Do not clean before build, Default (false)'
  echo '                                       Use this option for incremental build.'
  echo '                                       This option is not recommended, use with caution.'
  echo '          --no-s3ut-build            : Do not build S3 UT, Default (false)'
  echo '          --no-s3mempoolut-build     : Do not build Memory pool UT, Default (false)'
  echo '          --no-s3mempoolmgrut-build  : Do not build Memory pool Manager UT, Default (false)'
  echo '          --no-s3server-build        : Do not build S3 Server, Default (false)'
  echo '          --no-motrkvscli-build    : Do not build motrkvscli tool, Default (false)'
  echo '          --no-base64-encoder-decoder-build    : Do not build base64_encoder_decoder tool, Default (false)'
  echo '          --no-s3background-build    : Do not build s3background process, Default (false)'
  echo '          --no-s3msgbus-build    : Do not build s3msgbus, Default (false)'
  echo '          --no-s3cipher-build    : Do not build s3cipher, Default (false)'
  echo '          --no-s3confstoretool-build    : Do not build s3confstoretool process, Default (false)'
  echo '          --no-s3addbplugin-build    : Do not build s3 addb plugin library, Default (false)'
  echo '          --no-auth-build            : Do not build Auth Server, Default (false)'
  echo '          --no-jclient-build         : Do not build jclient, Default (false)'
  echo '          --no-jcloudclient-build    : Do not build jcloudclient, Default (false)'
  echo '          --no-s3iamcli-build        : Do not build s3iamcli, Default (false)'
  echo '          --no-java-tests            : Do not run java tests, Default (false)'
  echo '          --no-install               : Do not install binaries after build, Default (false)'
  echo '          --just-gen-build-file      : Do not do anything, only produce BUILD file'
  echo '          --valgrind_memcheck        : Compile with debug flags and zero optimization to support valgrind memcheck'
  echo '          --bazel_cpu_usage_limit    : Specify max percentage of CPU that bazel can consume during s3 build (integer), Value Range: 1-99, Default is 70'
  echo '          --bazel_rpm_usage_limit    : Specify max percentage of RAM that bazel can consume during s3 build (integer), Value Range: 1-99, Default is 70'
  echo '          --help (-h)                : Display help'
}

declare -a dev_includes_array
declare -a dev_lib_search_paths_array
declare -a rpm_includes_array
declare -a rpm_lib_search_paths_array

declare -a link_libs_array

# Example cmd run and output
# CMD: PKG_CONFIG_PATH=./third_party/motr pkg-config --cflags-only-I motr
# OUTPUT: -I/root/s3server/third_party/motr -I/root/s3server/third_party/motr/extra-libs/gf-complete/include -I/usr/src/lustre-client-2.12.3/libcfs/include \
# -I/usr/src/lustre-client-2.12.3/lnet/include -I/usr/src/lustre-client-2.12.3/lnet/include/uapi/linux -I/usr/src/lustre-client-2.12.3/lustre/include \
# -I/usr/src/lustre-client-2.12.3/lustre/include/uapi/linux
#
# CMD: PKG_CONFIG_PATH=./third_party/motr pkg-config --libs motr
# OUTPUT: -L/root/s3server/third_party/motr/motr/.libs -lmotr
#
get_motr_pkg_config_dev() {
  s3_src_dir=$1
  includes=$(PKG_CONFIG_PATH=$s3_src_dir/third_party/motr pkg-config --cflags-only-I motr)
  for include in $includes
  do
    if [[ "$include" == *"third_party"* ]] # exclude other paths
    then
      inc_path=$(echo $include | sed 's/^.*third_party/\/third_party/')
      dev_includes_array+=( $inc_path )
    fi
  done
  #printf '%s\t\n' "${dev_includes_array[@]}"
  libs=$(PKG_CONFIG_PATH=$s3_src_dir/third_party/motr pkg-config --libs motr)
  for lib in $libs
  do
    if [[ "$lib" == *"third_party"* ]] # this is 'L' part
    then
      lib_path=$(echo $lib | sed 's/^.*third_party/\/third_party/')
      dev_lib_search_paths_array+=( $lib_path )
    elif [[ ${lib:0:2} == '-l' ]]
    then
      link_libs_array+=( $lib )
    fi
  done
}

# Example cmd run and output
# CMD: pkg-config --cflags-only-I motr
# OUTPUT: -I/usr/include/motr -I/usr/src/lustre-client-2.12.3/libcfs/include -I/usr/src/lustre-client-2.12.3/lnet/include \
# -I/usr/src/lustre-client-2.12.3/lnet/include/uapi/linux -I/usr/src/lustre-client-2.12.3/lustre/include \
# -I/usr/src/lustre-client-2.12.3/lustre/include/uapi/linux \
#
# CMD: pkg-config --libs motr
# OUTPUT: -lmotr
get_motr_pkg_config_rpm() {
  s3_src_dir=$1
  pkg_config_path="$PKG_CONFIG_PATH:$s3_src_dir"
  includes=$(PKG_CONFIG_PATH=$pkg_config_path pkg-config --cflags-only-I motr)
  for include in $includes
  do
    if [[ "$include" != *"lustre-client"* ]] # exclude include paths from 'lustre-client*'
    then
      inc_path=${include#"-I"}
      rpm_includes_array+=( $inc_path )
    fi
  done
  #printf '%s\t\n' "${rpm_includes_array[@]}"

  libs=$(PKG_CONFIG_PATH=$pkg_config_path pkg-config --libs motr)
  for lib in $libs
  do
    if [[ ${lib:0:2} == '-L' ]] # this is 'L' part
    then
      rpm_lib_search_paths_array+=( $lib )
    elif [[ ${lib:0:2} == '-l' ]]
    then
      link_libs_array+=( $lib )
    fi
  done
}

# read the options
OPTS=`getopt -o h --long no-motr-rpm,use-build-cache,no-check-code,no-clean-build,\
no-s3ut-build,no-s3mempoolut-build,no-s3mempoolmgrut-build,no-s3server-build,\
no-motrkvscli-build,no-s3background-build,no-s3msgbus-build,no-s3cipher-build,no-s3confstoretool-build,\
no-s3addbplugin-build,no-auth-build,no-jclient-build,no-jcloudclient-build,\
no-s3iamcli-build,no-java-tests,no-install,just-gen-build-file,valgrind_memcheck,\
bazel_cpu_usage_limit:,bazel_ram_usage_limit:,\
help -n 'rebuildall.sh' -- "$@"`

eval set -- "$OPTS"

no_motr_rpm=0
use_build_cache=0
no_check_code=0
no_clean_build=0
no_s3ut_build=0
no_s3mempoolut_build=0
no_s3mempoolmgrut_build=0
no_s3server_build=0
no_motrkvscli_build=0
no_base64_encoder_decoder_build=0
no_s3background_build=0
no_s3msgbus_build=0
no_s3cipher_build=0
no_s3confstoretool_build=0
no_s3addbplugin_build=0
no_auth_build=0
no_jclient_build=0
no_jcloudclient_build=0
no_s3iamcli_build=0
no_java_tests=0
no_install=0
just_gen_build_file=0
valgrind_memcheck=0
bazel_cpu_limit=70
bazel_ram_limit=70

# extract options and their arguments into variables.
while true; do
  case "$1" in
    --no-motr-rpm) no_motr_rpm=1; shift ;;
    --use-build-cache) use_build_cache=1; shift ;;
    --no-check-code) no_check_code=1; shift ;;
    --no-clean-build)no_clean_build=1; shift ;;
    --no-s3ut-build) no_s3ut_build=1; shift ;;
    --no-s3mempoolut-build) no_s3mempoolut_build=1; shift ;;
    --no-s3mempoolmgrut-build) no_s3mempoolmgrut_build=1; shift ;;
    --no-s3server-build) no_s3server_build=1; shift ;;
    --no-motrkvscli-build) no_motrkvscli_build=1; shift ;;
    --no-base64-encoder-decoder-build) no_base64_encoder_decoder_build=1; shift ;;
    --no-s3background-build) no_s3background_build=1; shift ;;
	--no-s3msgbus-build) no_s3msgbus_build=1; shift ;;
    --no-s3cipher-build) no_s3cipher_build=1; shift ;;
    --no-s3confstoretool-build) no_s3confstoretool_build=1; shift ;;
    --no-s3addbplugin-build) no_s3addbplugin_build=1; shift ;;
    --no-auth-build) no_auth_build=1; shift ;;
    --no-jclient-build) no_jclient_build=1; shift ;;
    --no-jcloudclient-build) no_jcloudclient_build=1; shift ;;
    --no-s3iamcli-build) no_s3iamcli_build=1; shift ;;
    --no-install) no_install=1; shift ;;
    --no-java-tests) no_java_tests=1; shift ;;
    --just-gen-build-file) just_gen_build_file=1; shift ;;
    --valgrind_memcheck) valgrind_memcheck=1; shift ;;
    --bazel_cpu_usage_limit) bazel_cpu_limit=$2; shift 2 ;;
    --bazel_ram_usage_limit) bazel_ram_limit=$2; shift 2 ;;
    -h|--help) usage; exit 0;;
    --) shift; break ;;
    *) echo "Internal error!" ; exit 1 ;;
  esac
done

set -x

# Used to store third_party build artifacts
S3_SRC_DIR=`pwd`
BUILD_CACHE_DIR=$HOME/.seagate_src_cache

# Used to store motr include paths which are read from 'pkg-config --cflags'
motr_include_path="\"-I"
declare MOTR_LINK_LIB_

prepare_BUILD_file() {
  # Prepare BUILD file

  # Defined as a function because it's needed in two places.  Place 1 at start
  # of process (to handle cases when cmdline args requiest to just generate
  # BUILD).  Second place -- after motr build.  Note: if motr was not build
  # before, this function will generate error, this is why two places are
  # needed.

  # Define the paths
  if [ $no_motr_rpm -eq 1 ] # use motr libs from source code (built location or cache)
  then
    MOTR_INC_="MOTR_INC=./third_party/motr/"

    # set motr_include_path for 'copts' in BUILD file
    get_motr_pkg_config_dev $S3_SRC_DIR
    for path in "${dev_includes_array[@]}"
    do
      motr_include_path=$motr_include_path"."$path"\", \"-I"
    done
    # remove last ', "-I' # motr_include_path='"-I./third_party/motr", "-I./third_party/motr/extra-libs/gf-complete/include", \"-I'
    motr_include_path=${motr_include_path%", \"-I"}

    MOTR_LIB_="MOTR_LIB=."
    for lib_path in "${dev_lib_search_paths_array[@]}"
    do
      MOTR_LIB_=$MOTR_LIB_$lib_path"\", -L."  # '-L' is being appended at first index in 'BUILD' file itself
    done
    # remove last '\", -L.'
    MOTR_LIB_=${MOTR_LIB_%"\", -L."}

    for lib in "${link_libs_array[@]}"
    do
      MOTR_LINK_LIB_=$lib" "
    done
    # remove last blank space
    MOTR_LINK_LIB_=${MOTR_LINK_LIB_%" "}

    MOTR_HELPERS_LIB_="MOTR_HELPERS_LIB=./third_party/motr/helpers/.libs/"
  else
    # use motr libs from pre-installed motr rpm location
    get_motr_pkg_config_rpm $S3_SRC_DIR
    for path in "${rpm_includes_array[@]}"
    do
      motr_include_path=$motr_include_path$path"\", \"-I"
    done
    # remove last ', "-I'
    motr_include_path=${motr_include_path%", \"-I"}

    MOTR_INC_="MOTR_INC=/usr/include/motr/"
    if [ ${#rpm_lib_search_paths_array[@]} -eq 0 ]
    then
      MOTR_LIB_="MOTR_LIB=/usr/lib64/"
    else
      MOTR_LIB_="MOTR_LIB=."
      for lib_path in "${rpm_lib_search_paths_array[@]}"
      do
        MOTR_LIB_=$MOTR_LIB_$lib_path"\", -L."  # '-L' is being appended at first index in 'BUILD' file itself
      done
      # remove last '\", -L.'
      MOTR_LIB_=${MOTR_LIB_%"\", -L."}
    fi

    MOTR_HELPERS_LIB_="MOTR_HELPERS_LIB=/usr/lib64/"

    for lib in "${link_libs_array[@]}"
    do
      MOTR_LINK_LIB_=$lib" "
    done
    # remove last blank space
    MOTR_LINK_LIB_=${MOTR_LINK_LIB_%" "}
  fi

  release_debug_valgrind_flags='"-O3"'
  if [ $valgrind_memcheck -eq 1 ]; then
      release_debug_valgrind_flags='"-O0", "-fno-inline", "-g", "-g3"'
  fi

  cat BUILD.template > BUILD

  # set motr library search path in 'BUILD' file
  sed -i 's|MOTR_DYNAMIC_INCLUDES|'"$motr_include_path"'|g' BUILD

  # set motr link library in 'BUILD' file
  sed -i 's/MOTR_LINK_LIB/'"$MOTR_LINK_LIB_"'/g' BUILD

  # set build flags in 'BUILD' file
  sed -i 's|RELEASE_DEBUG_VALGRIND_FLAGS|'"$release_debug_valgrind_flags"'|g' BUILD
}

if [ $just_gen_build_file -eq 1 ]; then
  prepare_BUILD_file
  exit
fi


if [ $no_check_code -eq 0 ]
then
  ./checkcodeformat.sh
fi

# Build steps for third_party and motr
if [ $no_motr_rpm -eq 0 ]
then
  # RPM based build, build third_party except motr
  ./build_thirdparty.sh --no-motr-build
else
  if [ $use_build_cache -eq 0 ]
  then
    # Rebuild all third_party
    ./build_thirdparty.sh
  else
    # Use build cache
    if [ ! -d ${BUILD_CACHE_DIR} ]
    then
      # Rebuild all third_party
      ./build_thirdparty.sh

      # Copy to CACHE
      rm -rf ${BUILD_CACHE_DIR}
      mkdir -p ${BUILD_CACHE_DIR}

      echo "Sync third_party(,motr) binaries from third_party/"
      rsync -aW $S3_SRC_DIR/third_party/motr/ $BUILD_CACHE_DIR/motr
      cd $S3_SRC_DIR/third_party/motr/ && git rev-parse HEAD > $BUILD_CACHE_DIR/cached_motr.git.rev && cd -

      mkdir -p $BUILD_CACHE_DIR/libevent
      rsync -aW $S3_SRC_DIR/third_party/libevent/s3_dist $BUILD_CACHE_DIR/libevent
      cd $S3_SRC_DIR/third_party/libevent/ && git rev-parse HEAD > $BUILD_CACHE_DIR/cached_libevent.git.rev && cd -

      mkdir -p $BUILD_CACHE_DIR/libevhtp
      rsync -aW $S3_SRC_DIR/third_party/libevhtp/s3_dist $BUILD_CACHE_DIR/libevhtp
      cd $S3_SRC_DIR/third_party/libevhtp/ && git rev-parse HEAD > $BUILD_CACHE_DIR/cached_libevhtp.git.rev && cd -

      mkdir -p $BUILD_CACHE_DIR/jsoncpp
      rsync -aW $S3_SRC_DIR/third_party/jsoncpp/dist $BUILD_CACHE_DIR/jsoncpp
      cd $S3_SRC_DIR/third_party/jsoncpp/ && git rev-parse HEAD > $BUILD_CACHE_DIR/cached_jsoncpp.git.rev && cd -
    fi  # build cache not present
    # Copy from cache
    rsync -aW $BUILD_CACHE_DIR/ $S3_SRC_DIR/third_party/
  fi  # if [ $use_build_cache -eq 0 ]
fi  # if [ $no_motr_rpm -eq 0 ]

cp -f $S3_SRC_DIR/third_party/jsoncpp/dist/jsoncpp.cpp $S3_SRC_DIR/server/jsoncpp.cc

# Do we want a clean S3 build?
if [ $no_clean_build -eq 0 ]
then
  if [[ $no_s3ut_build -eq 0   || \
      $no_s3server_build -eq 0 || \
      $no_motrkvscli_build -eq 0 || \
      $no_base64_encoder_decoder_build -eq 0 || \
      $no_s3mempoolmgrut_build -eq 0 || \
      $no_s3mempoolut_build -eq 0 ]]
  then
    bazel shutdown
    bazel clean --expunge
  fi
fi

prepare_BUILD_file
# Add max CPU and RAM usage percentage for bazel.
# Default value will be 70 but user can change value from jenkins-build.sh script.
cpu_limit_input=$(echo $bazel_cpu_limit | awk '{ printf "%.1f", $1/100 }')
ram_limit_input=$(echo $bazel_ram_limit | awk '{ printf "%.1f", $1/100 }')
cpu_resource_limit_param="--local_cpu_resources=HOST_CPUS*$cpu_limit_input"
ram_resource_limit_param="--local_ram_resources=HOST_RAM*$ram_limit_input"

if [ $no_s3ut_build -eq 0 ]
then
  bazel build //:s3ut --cxxopt="-std=c++11" --define $MOTR_INC_ \
                      --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                      --spawn_strategy=standalone \
                      --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"

  bazel build //:s3utdeathtests --cxxopt="-std=c++11" --define $MOTR_INC_ \
                                --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                                --spawn_strategy=standalone \
                                --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

if [ $no_s3mempoolut_build -eq 0 ]
then
  bazel build //:s3mempoolut --cxxopt="-std=c++11" --spawn_strategy=standalone \
                             --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

if [ $no_s3mempoolmgrut_build -eq 0 ]
then
  bazel build //:s3mempoolmgrut --cxxopt="-std=c++11" --define $MOTR_INC_ \
                      --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                      --spawn_strategy=standalone \
                      --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

assert_addb_plugin_autogenerated_sources_are_correct() {
  cd server
  ./addb-codegen.py
  if test -n "`git diff s3_addb_*_auto*`"; then
    echo "ERROR (FATAL): There are changes in list of action classes!" >&2
    echo "You need to re-generate addb files.  To do that," >&2
    echo "cd to server/ folder and run addb-codegen.py script." >&2
    echo "Make sure to save your changes to git." >&2
    exit 1
  fi
  cd ..
}

if [ $no_s3server_build -eq 0 ]
then
  assert_addb_plugin_autogenerated_sources_are_correct
  bazel build //:s3server --cxxopt="-std=c++11" --define $MOTR_INC_ \
                          --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                          --spawn_strategy=standalone \
                          --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

if [ $no_s3addbplugin_build -eq 0 ]
then
  assert_addb_plugin_autogenerated_sources_are_correct
  bazel build //:s3addbplugin --define $MOTR_INC_ \
                              --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                              --spawn_strategy=standalone \
                              --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

if [ $no_motrkvscli_build -eq 0 ]
then
  bazel build //:motrkvscli --cxxopt="-std=c++11" --define $MOTR_INC_ \
                              --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                              --spawn_strategy=standalone \
                              --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

if [ $no_base64_encoder_decoder_build -eq 0 ]
then
    bazel build //:base64_encoder_decoder --cxxopt="-std=c++11" --define $MOTR_INC_ \
                              --define $MOTR_LIB_ --define $MOTR_HELPERS_LIB_ \
                              --spawn_strategy=standalone \
                              --strip=never "$cpu_resource_limit_param" "$ram_resource_limit_param"
fi

# Just to free up resources
bazel shutdown

if [ $no_motr_rpm -eq 1 ]
then
  if [ $no_s3msgbus_build -eq 0 ]
  then
    cd s3cortxutils/s3msgbus
    if [ $no_clean_build -eq 0 ]
    then
      python36 setup.py install --force
    else
      python36 setup.py install
    fi
    cd -
  fi
  if [ $no_s3cipher_build -eq 0 ]
  then
    cd s3cortxutils/s3cipher
    if [ $no_clean_build -eq 0 ]
    then
      python36 setup.py install --force
    else
      python36 setup.py install
    fi
    cd -      
  fi
  if [ $no_s3confstoretool_build -eq 0 ]
  then
    cd s3cortxutils/s3confstore
    if [ $no_clean_build -eq 0 ]
    then
      python36 setup.py install --force
    else
      python36 setup.py install
    fi
    cd -      
  fi
fi

extra_mvnbuild_pkg_opts=""
extra_mvn_pkg_opts=""
if [ $no_java_tests -eq 1 ]; then
  extra_mvnbuild_pkg_opts+=" --skip-tests"
  extra_mvn_pkg_opts+=" -Dmaven.test.skip=true"
fi

if [ $no_auth_build -eq 0 ]
then
  cd auth
  if [ $no_clean_build -eq 0 ]
  then
    ./mvnbuild.sh clean
  fi
  ./mvnbuild.sh package $extra_mvnbuild_pkg_opts
  cd -
fi

if [ $no_jclient_build -eq 0 ]
then
  cd auth-utils/jclient/
  if [ $no_clean_build -eq 0 ]
  then
    mvn clean
  fi
  mvn package $extra_mvn_pkg_opts
  cp target/jclient.jar ../../st/clitests/
  cp target/classes/jclient.properties ../../st/clitests/
  cd -
fi

if [ $no_jcloudclient_build -eq 0 ]
then
  cd auth-utils/jcloudclient
  if [ $no_clean_build -eq 0 ]
  then
    mvn clean
  fi
  mvn package $extra_mvn_pkg_opts
  cp target/jcloudclient.jar ../../st/clitests/
  cp target/classes/jcloud.properties ../../st/clitests/
  cd -
fi

# This will handle the copying of sample file to config file
if [ $no_install -eq 0 ]
then
  if [[ $EUID -ne 0 ]]; then
    command -v sudo
    if [ $? -ne 0 ]
    then
      echo "sudo required to run makeinstall"
      exit 1
    else
      sudo ./makeinstall
    fi
  else
    ./makeinstall
  fi
fi

if [ $no_motr_rpm -eq 1 ]
then
  if [ $no_s3background_build -eq 0 ]
  then
    cd s3backgrounddelete
    if [ $no_clean_build -eq 0 ]
    then
      python36 setup.py install --force
    else
      python36 setup.py install
    fi
    cd -
  fi
fi

if [ $no_motr_rpm -eq 1 ]
then
  if [ $no_s3iamcli_build -eq 0 ]
  then
    cd auth-utils/s3iamcli/

    # Remove the s3iamcli config file if present in root directory
    rm -f /root/.sgs3iamcli/config.yaml

    if [ $no_clean_build -eq 0 ]
    then
      python36 setup.py install --force
    else
      python36 setup.py install
    fi
    # Assert to check if the certificates are installed.
    #rpm -q stx-s3-client-certs
    cd -
  fi
fi
