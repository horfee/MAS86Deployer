#!/bin/bash


############################################
############ Beginning the work ############
############################################
source mas-script-functions.bash
source mas.properties

if [[ -z "${domain}" ]]; then 
  echo "Resolving domain through Ingress configuration..."
  domain=$(oc get Ingress.config cluster -o jsonpath='{.spec.domain}')
  echo "Domain is ${domain}"
else
  echo "Domain is preset with ${domain}"
fi


echo "Installing MAS 8.6 pre-reqs"
rm -rf tmp_prereqs
mkdir tmp_prereqs

echo "Installation of cert manager"
# technote : https://cert-manager.io/docs/installation/
#oc create namespace cert-manager
#oc project cert-manager
oc apply -f https://github.com/jetstack/cert-manager/releases/download/v1.6.0/cert-manager.yaml
if [[ -f "./install_webhook.sh" ]]; then
  ./install_webhook.sh
fi


echo "Instantiate Service Bindings Operator (SBO)"
cat << EOF > tmp_prereqs/sbo.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: rh-service-binding-operator
  namespace: openshift-operators
spec:
  channel: preview
  name: rh-service-binding-operator
  source: redhat-operators 
  sourceNamespace: openshift-marketplace
  installPlanApproval: Manual
  startingCSV: service-binding-operator.v0.8.0
EOF

oc apply -f tmp_prereqs/sbo.yaml

while [[ $(oc get Subscription rh-service-binding-operator -n openshift-operators -o jsonpath="{.status.conditions[*].type}") != *"InstallPlanPending"* ]];do sleep 5; done & 
showWorking $!
printf '\b'

# Find install plan
installplan=$(oc get installplan -n openshift-operators | grep -i service-binding | awk '{print $1}'); echo "installplan: $installplan"

# Approve install plan
oc patch installplan ${installplan} -n openshift-operators --type merge --patch '{"spec":{"approved":true}}'

echo -n "Operator ready              "
while [[ $(oc get ClusterServiceVersion -n openshift-operators service-binding-operator.v0.8.0 -o jsonpath="{.status.phase}" --ignore-not-found=true ) != "Succeeded" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

# installation Behavior Analytics Service
cat << EOF > cr.properties
####Change the values of these properties
projectName=${bas_projectName}
storageClassKafka=${bas_storageClassKafka}
storageClassZookeeper=${bas_storageClassZookeeper}
storageClassDB=${bas_storageClassDB}
storageClassArchive=${bas_storageClassArchive}
dbuser=${bas_dbuser}
dbpassword=${bas_dbpassword}
grafanauser=${bas_grafanauser}
grafanapassword=${bas_grafanapassword}
####Keeping the values of below properties to default is advised.
storageSizeKafka=5G
storageSizeZookeeper=5G
storageSizeDB=10G
storageSizeArchive=10G
eventSchedulerFrequency='*/10 * * * *'
prometheusSchedulerFrequency='@daily'
envType=lite
ibmproxyurl='https://iaps.ibm.com'
airgappedEnabled=false
imagePullSecret=bas-images-pull-secret
EOF
# modify cr.properties file to match your settings
# ATTENTION : dbuser and grafanauser values must be in lowercase with alphanumeric values !!!!
./install_bas.sh


echo "Installation of mongodb"
git clone https://github.com/ibm-watson-iot/iot-docs
#wget https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v0.6.0/config/rbac/kustomization.yaml -O iot-docs/mongodb/config/rbac/kustomization.yaml
#wget https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v0.6.0/config/rbac/role.yaml -O iot-docs/mongodb/config/rbac/role.yaml
#wget https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v0.6.0/config/rbac/role_binding.yaml -O iot-docs/mongodb/config/rbac/role_binding.yaml
#wget https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v0.6.0/config/rbac/service_account.yaml -O iot-docs/mongodb/config/rbac/service_account.yaml
#wget https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/v0.6.0/config/manager/manager.yaml -O iot-docs/mongodb/config/manager/manager.yaml


export MONGO_NAMESPACE
export MONGO_PASSWORD
export MONGODB_STORAGE_CLASS

cd iot-docs/mongodb/certs/
./generateSelfSignedCert.sh

cd ../
./install-mongo-ce.sh

cd ../../

echo "Enabling IBM catalog"
cat << EOF > tmp_prereqs/enable_ibm_operator_catalog.yaml

---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ibm-operator-catalog
  namespace: openshift-marketplace
spec:
  displayName: "IBM Operator Catalog"
  publisher: IBM
  sourceType: grpc
  image: icr.io/cpopen/ibm-operator-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: opencloud-operators
  namespace: openshift-marketplace
spec:
  displayName: IBMCS Operators
  publisher: IBM
  sourceType: grpc
  image: docker.io/ibmcom/ibm-common-service-catalog:latest
  updateStrategy:
    registryPoll:
      interval: 45m
---
apiVersion: v1
kind: Namespace
metadata:
  name: ibm-common-services
---
apiVersion: operators.coreos.com/v1alpha2
kind: OperatorGroup
metadata:
  name: operatorgroup
  namespace: ibm-common-services
spec:
  targetNamespaces:
  - ibm-common-services
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-common-service-operator
  namespace: ibm-common-services
spec:
  channel: v3
  installPlanApproval: Automatic
  name: ibm-common-service-operator
  source: opencloud-operators
  sourceNamespace: openshift-marketplace
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: odlm-scope
  namespace: ibm-common-services
data:
  namespaces: ibm-common-services

EOF
#---
#apiVersion: operators.coreos.com/v1alpha1
#kind: Subscription
#metadata:
#  name: operand-deployment-lifecycle-manager
#  namespace: ibm-common-services
#spec:
#  channel: v3
#  name: ibm-odlm
#  source: ibm-operator-catalog
#  sourceNamespace: openshift-marketplace
#  config:
#    env:
#    - name: INSTALL_SCOPE
#      value: namespaced

oc apply -f tmp_prereqs/enable_ibm_operator_catalog.yaml

echo -n "Operator catalog ready              "
while [[ $(oc get CatalogSource ibm-operator-catalog -n openshift-marketplace -o jsonpath="{.status.connectionState.lastObservedState}" --ignore-not-found=true ) != "READY" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo -n "Operand Deployment Lifecycle Manager              "
while [[ $(oc get ClusterServiceVersion -n ibm-common-services --no-headers | grep operand-deployment-lifecycle-manager | awk '{printf $1}') == "" ]];do sleep 1; done & showWorking $!
printf '\b'
operator_name=$(oc get ClusterServiceVersion -n ibm-common-services --no-headers | grep operand-deployment-lifecycle-manager | awk '{printf $1}')
while [[ $(oc get ClusterServiceVersion ${operator_name} -n ibm-common-services -o jsonpath="{.status.phase}"  --ignore-not-found=true ) != "Succeeded" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo "Installing SLS"
# create a project dedicated for SLS
oc new-project ${slsnamespace}
oc project ${slsnamespace}

echo "Instantiate operator"

cat << EOF > tmp_prereqs/install_sls.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-sls
  namespace: ${slsnamespace}
spec:
  targetNamespaces:
    - ${slsnamespace}
EOF
oc create -f tmp_prereqs/install_sls.yaml

echo "Activate subscription"
cat << EOF > tmp_prereqs/install_sls_subscription.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-sls
  namespace: ${slsnamespace}
  labels:
    operators.coreos.com/ibm-sls.${slsnamespace}: ''
spec:
  channel: 3.x
  installPlanApproval: Automatic
  name: ibm-sls
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

oc create -f tmp_prereqs/install_sls_subscription.yaml

while [[ $(oc get ClusterServiceVersion -n ${slsnamespace} --no-headers | grep ibm-sls | awk '{printf $1}') == "" ]];do sleep 1; done & showWorking $!
printf '\b'

operator_name=$(oc get ClusterServiceVersion -n ${slsnamespace} --no-headers | grep ibm-sls | awk '{printf $1}')
while [[ $(oc get ClusterServiceVersion ${operator_name} -n ${slsnamespace} -o jsonpath="{.status.phase}"  --ignore-not-found=true ) != "Succeeded" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo "Create LicenseService instance"
cat << EOF > tmp_prereqs/sls_mongo_credentials.yaml
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: sls-mongo-credentials
  namespace: ${slsnamespace}
stringData:
  username: 'admin'
  password: '${MONGO_PASSWORD}'
EOF

oc -n ${slsnamespace} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username="cp" --docker-password=${ER_KEY}
oc -n ${slsnamespace} apply -f tmp_prereqs/sls_mongo_credentials.yaml

# retrieve mongo self signed certificates
mongoCACertificate=$(cat iot-docs/mongodb/certs/ca.pem  | sed 's/^/\ \ \ \ \ \ \ \ \ \ /g')
mongoServerCertificate=$(cat iot-docs/mongodb/certs/mongodb.pem | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p'| sed 's/^/\ \ \ \ \ \ \ \ \ \ /g')

cat << EOF > tmp_prereqs/sls_instance.yaml
apiVersion: sls.ibm.com/v1
kind: LicenseService
metadata:
  namespace: ${slsnamespace}
  name: sls
  labels:
    app.kubernetes.io/instance: ibm-sls
    app.kubernetes.io/managed-by: olm
    app.kubernetes.io/name: ibm-sls
spec:
  domain: >-
    ${domain}
  license:
    accept: true
  mongo:
    authMechanism: ${mongoAuthMechanism}
    certificates:
      - alias: ca
        crt: |-
${mongoCACertificate}
      - alias: server
        crt: |-
${mongoServerCertificate}
    configDb: ${mongoConfigDB}
    nodes:
      - host: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-1.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-2.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
    secretName: sls-mongo-credentials
  rlks:
    storage:
      class: ${rlks_storageclass}
      size: ${rlks_storagesize}
  settings:
    auth:
      enforce: true
    compliance:
      enforce: true
    reconciliation:
      enabled: true
      reconciliationPeriod: 1800
    registration:
      open: true
    reporting:
      maxDailyReports: 90
      maxHourlyReports: 24
      maxMonthlyReports: 12
      reportGenerationPeriod: 3600
      samplingPeriod: 900
EOF

oc apply -f tmp_prereqs/sls_instance.yaml

while [[ $(oc get LicenseService sls -n ${slsnamespace} -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}"  --ignore-not-found=true) != "True" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "[8/] Deploying Kafka for MAS"
oc project "${kafkanamespace}" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "${kafkanamespace}" --display-name "MAS Kafka" > /dev/null 2>&1
fi

namespace=$(oc config view --minify -o 'jsonpath={..namespace}')

operator_name=$(oc get ClusterServiceVersion strimzi-cluster-operator.v0.22.1 -n ${namespace} -o jsonpath="{.spec.install.spec.deployments[0].name}")
if [[ -z ${operator_name} ]]; then  # We must deploy operatorgroup, operator and cluster as no strimzi operator in this namespace have been found

echo "  Installing operator"
echo "	Operator will be by default set up to manual on channel 8.x"

cat << EOF > tmp_prereqs/strimzi_operatorgroup.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kafka-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

oc apply -f tmp_prereqs/strimzi_operatorgroup.yaml > /dev/null 2>&1
echo "	Operator group created"

cat << EOF > tmp_prereqs/strimzi_operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: strimzi-kafka-operator
  namespace: ${namespace}
spec:
  channel: strimzi-0.22.x
  installPlanApproval: Manual
  name: strimzi-kafka-operator
  source: community-operators
  sourceNamespace: openshift-marketplace
EOF

oc apply -f tmp_prereqs/strimzi_operator.yaml > /dev/null 2>&1
echo "	Operator created"

while [[ $(oc get Subscription strimzi-kafka-operator -n ${namespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'

echo "	Approving manual installation"
# Find install plan
installplan=$(oc get subscription strimzi-kafka-operator -o jsonpath="{.status.installplan.name}" -n ${namespace})
echo "	installplan: $installplan"

# Approve install plan
oc patch installplan ${installplan} -n ${namespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

while [[ $(oc get ClusterServiceVersion -n ${namespace} --no-headers | grep strimzi-cluster-operator | awk '{printf $1}') == "" ]];do sleep 1; done & showWorking $!
printf '\b'

operator_name=$(oc get ClusterServiceVersion strimzi-cluster-operator.v0.22.1 -n ${namespace} -o jsonpath="{.spec.install.spec.deployments[0].name}")


echo -n "	Operator ready              "
while [[ $(oc get deployment/${operator_name} --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

fi

echo_h2 " Instanciating kafka cluster"

cat << EOF > tmp_prereqs/kafka_instance.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: Kafka
metadata:
  namespace: ${namespace}
  name: ${kafkaclustername}
spec:
  kafka:
    config:
      offsets.topic.replication.factor: 3
      transaction.state.log.replication.factor: 3
      transaction.state.log.min.isr: 2
      log.message.format.version: '2.7'
      inter.broker.protocol.version: '2.7'
    version: 2.7.0
    authorization:
      type: simple
    storage:
      volumes:
        - id: 0
          size: 100Gi
          deleteClaim: true
          class: ${kafkastorageclass}
          type: persistent-claim
      type: jbod
    replicas: 3
    jvmOptions:
      '-Xms': 3072m
      '-Xmx': 3072m
    listeners:
      - name: plain
        port: 9092
        type: internal
        tls: false
        authentication:
          type: scram-sha-512
      - name: tls
        port: 9093
        type: internal
        tls: true
        authentication:
          type: scram-sha-512
  entityOperator:
    topicOperator: {}
    userOperator: {}
  zookeeper:
    storage:
      class: ${kafkastorageclass}
      deleteClaim: true
      size: 10Gi
      type: persistent-claim
    replicas: 3
    jvmOptions:
      '-Xms': 768m
      '-Xmx': 768m
EOF

oc apply -f tmp_prereqs/kafka_instance.yaml > /dev/null 2>&1

echo -n "	Kafka ready              "
while [[ $(oc get Kafka ${kafkaclustername} --ignore-not-found=true -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" -n ${namespace}) != "True" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"