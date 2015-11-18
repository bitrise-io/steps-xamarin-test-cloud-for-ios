#!/bin/bash

#
# Validate required inputs

if [[ -z ${test_cloud_path} ]] ; then
  echo "Missing required input: test_cloud_path"
  exit 1
fi

if [[ -z ${ipa_path} ]] ; then
  echo "Missing required input: ipa_path"
  exit 1
fi

if [[ -z ${API_KEY} ]] ; then
  echo "Missing required input: API_KEY"
  exit 1
fi

if [[ -z ${user} ]] ; then
  echo "Missing required input: user"
  exit 1
fi

if [[ -z ${assembly_dir} ]] ; then
  echo "Missing required input: assembly_dir"
  exit 1
fi

if [[ -z ${devices} ]] ; then
  echo "Missing required input: devices"
  exit 1
fi

#
# Print configs
echo
echo '========== Configs =========='
echo " * test_cloud_path: ${test_cloud_path}"
echo " * ipa_path: ${ipa_path}"
echo " * api_key: ***"
echo " * user: ${user}"
echo " * assembly_dir: ${assembly_dir}"
echo " * devices: ${devices}"
echo " * app_name: ${app_name}"
echo " * async: ${async}"
echo " * category: ${category}"
echo " * fixture: ${fixture}"
echo " * nunit_xml: ${nunit_xml}"
echo " * series: ${series}"
echo " * dsym: ${dsym}"
echo " * parallelization: ${parallelization}"


#
# Build command

cmd="mono ${test_cloud_path} submit ${ipa_path} ${api_key}"
cmd="$cmd --user ${user}"
cmd="$cmd --assembly-dir ${assembly_dir}"
cmd="$cmd --devices ${devices}"

if [[ -n ${app_name} ]] ; then
  cmd="$cmd --app-name ${app_name}"
fi

if [[ ${async} == "yes" ]] ; then
  cmd="$cmd --async"
fi

if [[ -n ${category} ]] ; then
  cmd="$cmd --category ${category}"
fi

if [[ -n ${fixture} ]] ; then
  cmd="$cmd --fixture ${fixture}"
fi

if [[ -n ${nunit_xml} ]] ; then
  cmd="$cmd --nunit-xml ${nunit_xml}"
fi

if [[ -n ${series} ]] ; then
  cmd="$cmd --series ${series}"
fi

if [[ -n ${dsym} ]] ; then
  cmd="$cmd --dsym ${dsym}"
fi

if [[ -n ${parallelization} ]] ; then
  if [[ ${parallelization} == "" ]] ; then
    cmd="$cmd --fixture-chunk"
  elif [[ $parallelization == "" ]]; then
    cmd="$cmd --test-chunk"
  else
    echo " (!) invalid parallelization value: $parallelization"
  fi
fi

echo
echo $cmd

#
# Perform command

echo
eval $cmd
