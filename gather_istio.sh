#!/bin/bash

# Copyright 2019 Red Hat, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BASE_COLLECTION_PATH="/must-gather"

# The following CRDs are not managed by the Maistra operator but it
# will create instances of them.
DEPENDENCY_CRS="jaegers.jaegertracing.io kialis.kiali.io"

# Get the namespaces of all control planes in the cluster
function getControlPlanes() {
  local result=()

  local namespaces
  namespaces=$(oc get ServiceMeshControlPlane --all-namespaces -o jsonpath='{.items[*].metadata.namespace}')
  for namespace in ${namespaces}; do
    result+=("${namespace}")
  done

  echo "${result[@]}"
}

# Get the members of a mesh (namespaces that belongs to a certain control plane).
# $1 = Namespace of the control plane - e.g. "istio-system"
# Returns a space-separated list of member namespaces (e.g. "bookinfo bookinfo2")
function getMembers() {
  local cp="${1}"

  local output
  output="$(oc -n "${cp}" get ServiceMeshMemberRoll default -o jsonpath='{.status.members[*]}' 2>/dev/null)"

  if [ -z "${output}" ]; then
    return
  fi

  echo "${output}"
}

# Get the CRD's that belong to Maistra
function getCRDs() {
  local result=()
  local output
  output=$(oc get crd -lmaistra-version -o jsonpath='{.items[*].metadata.name}')
  for crd in ${output}; do
    result+=("${crd}")
  done

  # Get the remaining CRD's that don't contain a maistra label. See https://issues.jboss.org/browse/MAISTRA-799
  local output
  output=$(oc get crd -l'!maistra-version' -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' | grep -E 'maistra|istio')
  for crd in ${output}; do
    result+=("${crd}")
  done

  echo "${result[@]}"
}

# getPilotName gets the name of the Pilot instance in that namespace. 
function getPilotName() {
  local namespace="${1}"

  oc get pods -n "${namespace}" -l 'app in (istiod,pilot)'  -o jsonpath="{.items[0].metadata.name}"
}

# getSynchronization dumps the synchronization status for the specified control plane
# to a file in the control plane directory of the control plane namespace
# Arguments:
#		namespace of the control plane
#	Returns:
#		nothing
function getSynchronization() {
  local namespace="${1}"

  local pilotName
  pilotName=$(getPilotName "${namespace}")

  echo
  echo "Collecting /debug/syncz from ${pilotName} in namespace ${cp}"

  local logPath=${BASE_COLLECTION_PATH}/namespaces/${namespace}
  mkdir -p "${logPath}"
  oc exec "${pilotName}" -n "${namespace}" -c discovery -- /usr/local/bin/pilot-discovery request GET /debug/syncz > "${logPath}/debug-syncz.json" 2>&1
}

# getEnvoyConfigForPodsInNamespace dumps the envoy config for the specified namespace and
# control plane to a file in the must-gather directory for each pod
# Arguments:
#   namespace of the control plane
#   namespace to dump
# Returns:
#   nothing
function getEnvoyConfigForPodsInNamespace() {
  local controlPlaneNamespace="${1}"
  local pilotName
  pilotName=$(getPilotName "${controlPlaneNamespace}")
  local podNamespace="${2}"

  echo
  echo "Collecting Envoy config for pods in ${podNamespace}, control plane namespace ${controlPlaneNamespace}"

  local pods
  pods="$(oc get pods -n "${podNamespace}" -o jsonpath='{ .items[*].metadata.name }')"
  for podName in ${pods}; do
    if [ -z "$podName" ]; then
        continue
    fi

    if oc get pod -o yaml "${podName}" -n "${podNamespace}" | grep -q proxyv2; then
      echo "Collecting config_dump and stats for pod ${podName}.${podNamespace}"

      local logPath=${BASE_COLLECTION_PATH}/namespaces/${podNamespace}/pods/${podName}
      mkdir -p "${logPath}"

      oc exec "${pilotName}" -n "${controlPlaneNamespace}" -c discovery -- bash -c "/usr/local/bin/pilot-discovery request GET /debug/config_dump?proxyID=${podName}.${podNamespace}" > "${logPath}/config_dump_istiod.json" 2>&1
      oc exec -n "${podNamespace}" "${podName}" -c istio-proxy -- /usr/local/bin/pilot-agent request GET config_dump > "${logPath}/config_dump_proxy.json" 2>&1
      oc exec -n "${podNamespace}" "${podName}" -c istio-proxy -- /usr/local/bin/pilot-agent request GET stats > "${logPath}/proxy_stats" 2>&1
    fi
  done
}

function version() {
  if [[ -n $OSSM_MUST_GATHER_VERSION ]] ; then
    echo "${OSSM_MUST_GATHER_VERSION}"
  else
    echo "0.0.0-unknown"
  fi
}

function inspect() {
  local resource ns
  resource=$1
  ns=$2

  echo
  if [ -n "$ns" ]; then
    echo "Inspecting resource ${resource} in namespace ${ns}"
    oc adm inspect "--dest-dir=${BASE_COLLECTION_PATH}" "${resource}" -n "${ns}"
  else
    echo "Inspecting resource ${resource}"
    oc adm inspect "--dest-dir=${BASE_COLLECTION_PATH}" "${resource}"
  fi
}

function inspectNamespace() {
  local ns
  ns=$1

  inspect "ns/$ns"
  for crd in $crds; do
    inspect "$crd" "$ns"
  done
  inspect net-attach-def,roles,rolebindings "$ns"
}

function main() {
  local crds controlPlanes members smcpName
  echo
  echo "Executing Istio gather script"
  echo

  versionFile="${BASE_COLLECTION_PATH}/version"
  echo "openshift-service-mesh/must-gather"> "$versionFile"
  version >> "$versionFile"

  operatorNamespace=$(oc get pods --all-namespaces -l name=istio-operator -o jsonpath="{.items[0].metadata.namespace}")

  validatingwebhookconfigurations=$(oc get validatingwebhookconfiguration -o custom-columns=NAME:.metadata.name | grep maistra)
  for validatingwebhookconfiguration in $validatingwebhookconfigurations; do
    inspect "validatingwebhookconfiguration/$validatingwebhookconfiguration"
  done

  mutatingwebhookconfigurations=$(oc get mutatingwebhookconfiguration -o custom-columns=NAME:.metadata.name | grep maistra)
  for mutatingwebhookconfiguration in $mutatingwebhookconfigurations; do
    inspect "mutatingwebhookconfiguration/$mutatingwebhookconfiguration"
  done

  inspect nodes

  for r in $(oc get clusterroles,clusterrolebindings -l maistra-version,maistra.io/owner= -oname); do
    inspect "$r"
  done

  crds="$(getCRDs)"
  for crd in ${crds}; do
    inspect "crd/${crd}"
  done

  controlPlanes="$*"
  if [ -z "${controlPlanes}" ]; then
    controlPlanes="$(getControlPlanes)"
  fi

  inspect "ns/$operatorNamespace"
  inspect clusterserviceversion "${operatorNamespace}"

  for cp in ${controlPlanes}; do
      smcpName="$(oc get smcp -n "${cp}" -o jsonpath='{.items[*].metadata.name}')"
      if [[ -z "$smcpName" ]]; then
        echo "ERROR: namespace ${cp} does not contain a ServiceMeshControlPlane object"
        exit 1
      fi

      echo
      echo "Processing control plane namespace: ${cp}"

      crds="$crds" inspectNamespace "$cp"
      inspect "mutatingwebhookconfiguration/istiod-${smcpName}-${cp}"
      inspect "validatingwebhookconfiguration/istio-validator-${smcpName}-${cp}"
      getEnvoyConfigForPodsInNamespace "${cp}" "${cp}"
      getSynchronization "${cp}"

      for r in $(oc get clusterroles,clusterrolebindings -l maistra.io/owner="$cp" -oname); do
        inspect "$r"
      done

      for cr in ${DEPENDENCY_CRS}; do
        inspect "${cr}" "${cp}"
      done

      members=$(getMembers "${cp}")
      for member in ${members}; do
          if [ -z "$member" ]; then
              continue
          fi

          echo "Processing ${cp} member ${member}"
          crds="$crds" inspectNamespace "$member"
          getEnvoyConfigForPodsInNamespace "${cp}" "${member}"
       done
  done

  echo
  echo
  echo "Done"
  echo
}

main "$@"
