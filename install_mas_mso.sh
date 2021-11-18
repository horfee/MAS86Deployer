#!/bin/bash


############################################
############ Beginning the work ############
############################################
source mas-script-functions.bash
source masmso.properties

echo_h1 "Deploying MAS MSO"
oc project "mas-${instanceid}-mso" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${instanceid}-mso" --display-name "MAS MSO (${instanceid})" > /dev/null 2>&1
fi

rm -rf tmp
mkdir tmp


export namespace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo -n "[INIT] Creating IBM entitlement secret... "
oc -n ${namespace} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ER_KEY} > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo_h2 "[1/6] Installing operator"
echo "	Operator will be by default set up to manual on channel 8.x"

cat << EOF > tmp/mas_operatorgroup.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-mas-mso-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

oc apply -f tmp/mas_operatorgroup.yaml > /dev/null 2>&1
echo "	Operator group created"

cat << EOF > tmp/mas_operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-mso
  namespace: ${namespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-mso
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

oc apply -f tmp/mas_operator.yaml > /dev/null 2>&1
echo "	Operator created"

while [[ $(oc get Subscription ibm-mas-mso -n ${namespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'

echo "	Approving manual installation"
# Find install plan
installplan=$(oc get subscription ibm-mas-mso -o jsonpath="{.status.installplan.name}" -n ${namespace})
echo "	installplan: $installplan"

# Approve install plan
oc patch installplan ${installplan} -n ${namespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo -n "	Operator ready              "
while [[ $(oc get deployment/ibm-mas-mso-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "[1/1] Creating Service Bindings"
cat << EOF > tmp/mas_mso_bindings.yaml
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-coreidp-binding
  namespace: mas-${instanceid}-mso
  labels:
    mas.ibm.com/applicationId: mso
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: internal.mas.ibm.com
      kind: CoreIDP
      name: ${instanceid}-coreidp
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-mongo-binding
  namespace: mas-${instanceid}-mso
  labels:
    mas.ibm.com/applicationId: mso
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: config.mas.ibm.com
      kind: MongoCfg
      name: ${instanceid}-mongo-system
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-suite-binding
  namespace: mas-${instanceid}-mso
  labels:
    mas.ibm.com/applicationId: mso
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: core.mas.ibm.com
      kind: Suite
      name: ${instanceid}
      namespace: mas-${instanceid}-core
      version: v1

EOF

oc apply -f tmp/mas_mso_bindings.yaml > /dev/null 2>&1

echo_h2 "[1/2] Instanciating MSO app"
cat << EOF > tmp/mas_mso_app.yaml
apiVersion: apps.mas.ibm.com/v1
kind: MSOApp
metadata:
  name: ${instanceid}
  namespace: mas-${instanceid}-mso
  labels:
    mas.ibm.com/applicationId: mso
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindings:
    mongo: system
  components: {}
EOF

oc apply -f tmp/mas_mso_app.yaml > /dev/null 2>&1


echo -n "	MSO Config Ready      "
while [[ $(oc get MSOApp ${instanceid} --ignore-not-found=true -n mas-${instanceid}-core --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "Creating MSO workspace..."

cat << EOF > tmp/mas_mso_workspace.yaml
apiVersion: apps.mas.ibm.com/v1
kind: MSOWorkspace
metadata:
  name: ibm-mas-mso-${instanceid}-${workspaceid}
  namespace: mas-${instanceid}-mso
  labels:
    mas.ibm.com/applicationId: mso
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  bindings:
    manage: workspace
  settings:
    executionService:
      logLevel: info
      maxWorkerMemory: 4096m
      queueWorkers: 3
      replicas: 3
      resources:
        limits:
          cpu: '3'
          memory: 16Gi
        requests:
          cpu: '0.01'
          memory: 196Mi

EOF

oc apply -f tmp/mas_mso_app.yaml > /dev/null 2>&1


echo -n "	MSO Workspace Ready      "
while [[ $(oc get MSOWorkspace ${instanceid}-${workspaceid} --ignore-not-found=true -n mas-${instanceid}-mso --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"