#!/bin/bash


############################################
############ Beginning the work ############
############################################
source mas-script-functions.bash
source masmanage.properties

echo_h1 "Deploying MAS Manage"
oc project "mas-${instanceid}-manage" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${instanceid}-manage" --display-name "MAS Manage (${instanceid})" > /dev/null 2>&1
fi

rm -rf tmp_manage
mkdir tmp_manage


export namespace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo -n "[INIT] Creating IBM entitlement secret... "
oc -n ${namespace} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ER_KEY} > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo_h2 "[1/6] Installing operator"
echo "	Operator will be by default set up to manual on channel 8.x"

cat << EOF > tmp_manage/mas_operatorgroup.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-mas-manage-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

oc apply -f tmp_manage/mas_operatorgroup.yaml > /dev/null 2>&1
echo "	Operator group created"

cat << EOF > tmp_manage/mas_operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas-manage.mas-demo-manage
  namespace: ${namespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas-manage
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

oc apply -f tmp_manage/mas_operator.yaml > /dev/null 2>&1
echo "	Operator created"

while [[ $(oc get Subscription ibm-mas-manage.mas-demo-manage -n ${namespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'

echo "	Approving manual installation"
# Find install plan
installplan=$(oc get subscription ibm-mas-manage.mas-demo-manage -o jsonpath="{.status.installplan.name}" -n ${namespace})
echo "	installplan: $installplan"

# Approve install plan
oc patch installplan ${installplan} -n ${namespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo -n "	Operator ready              "
while [[ $(oc get deployment/ibm-mas-manage-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "[1/1] Creating Service Bindings"
cat << EOF > tmp_manage/mas_manage_bindings.yaml
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-suite-binding
  namespace: mas-${instanceid}-manage
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: core.mas.ibm.com
      kind: Suite
      name: ${instanceid}
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${workspaceid}-coreidp-binding
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: internal.mas.ibm.com
      kind: CoreIDP
      name: ${workspaceid}-coreidp
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${workspaceid}-coreidp-binding
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: internal.mas.ibm.com
      kind: CoreIDP
      name: ${workspaceid}-coreidp
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-${workspaceid}-jdbc-binding
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: config.mas.ibm.com
      kind: JdbcCfg
      name: ${instanceid}-jdbc-wsapp-${workspaceid}-manage
      namespace: mas-${instanceid}-core
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-${workspaceid}-add-binding
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: asset-data-dictionary.ibm.com
      kind: DataDictionaryWorkspace
      name: ${instanceid}-${workspaceid}
      namespace: mas-${instanceid}-add
      version: v1
---
apiVersion: binding.operators.coreos.com/v1alpha1
kind: ServiceBinding
metadata:
  name: ${instanceid}-${workspaceid}-smtp-binding
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  bindAsFiles: true
  namingStrategy: lowercase
  services:
    - group: config.mas.ibm.com
      kind: SmtpCfg
      name: ${instanceid}-smtp-system
      namespace: mas-${instanceid}-core
      version: v1
EOF

oc apply -f tmp_manage/mas_manage_bindings.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo_h2 "[1/2] Instanciating Manage app"
cat << EOF > tmp_manage/mas_manage_app.yaml
apiVersion: apps.mas.ibm.com/v1
kind: ManageApp
metadata:
  labels:
    app.kubernetes.io/instance: ${instanceid}
    app.kubernetes.io/managed-by: ibm-mas-manage
    app.kubernetes.io/name: ibm-mas-manage
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
  name: ${instanceid}
  namespace: mas-${instanceid}-manage
spec:
  license:
    accept: true
EOF

oc apply -f tmp_manage/mas_manage_app.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"


echo_h2 "[6/6] Instanciating Manage JDBC configuration"
if [[ $jdbcurl == *"sslConnection=true"* ]]; then
  jdbcsslenabled=true

  echo "	Retriving JDBC SSL certificate"
  jdbccrt=$(fetchCertificates jdbcserver jdbcport)
  jdbccrt=$(getcert $jdbccrt 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
else
  echo "	SSL disabled"
  jdbcsslenabled=false
fi

owneruid=$(oc get Suite ${instanceid} -n mas-${instanceid}-core -o jsonpath="{.metadata.uid}")

echo -n "	Creating JDBC configuration... "
if [[ "$jdbcsslenabled" == "true" ]]; then

cat << EOF > tmp_manage/mas_manage_jdbc_cfg.yaml
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${instanceid}-jdbc-wsapp-${workspaceid}-manage
  namespace: mas-${instanceid}-core
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/configScope: workspace-application
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  certificates:
    - alias: cacert
      crt: |-
${jdbccrt}
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-jdbc-creds-wsapp-${workspaceid}-manage
    driverOptions: {}
    sslEnabled: ${jdbcsslenabled}
    url: >-
      ${jdbcurl}
  displayName: Maximo Manage Database
  type: external
EOF

else

cat << EOF > tmp_manage/mas_manage_jdbc_cfg.yaml
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${instanceid}-jdbc-wsapp-${workspaceid}-manage
  namespace: mas-${instanceid}-core
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/configScope: workspace-application
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-jdbc-creds-wsapp-${workspaceid}-manage
    driverOptions: {}
    sslEnabled: ${jdbcsslenabled}
    url: >-
      ${jdbcurl}
  displayName: Maximo Manage Database
  type: external
EOF


fi
oc apply -f tmp_manage/mas_manage_jdbc_cfg.yaml > /dev/null 2>&1

cat << EOF > tmp_manage/mas_manage_jdbc_cfg_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-jdbc-creds-wsapp-${workspaceid}-manage
  namespace: mas-${instanceid}-core
data:
  password: $(echo -n ${jdbcpassword} | base64)
  username: $(echo -n ${jdbcusername} | base64)
type: Opaque

EOF

oc apply -f tmp_manage/mas_manage_jdbc_cfg_credentials.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"


echo -n "	JDBC Config Ready      "
while [[ $(oc get JdbcCfg ${instanceid}-jdbc-wsapp-${workspaceid}-manage --ignore-not-found=true -n mas-${instanceid}-core --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "Creating Manage configuration..."

cat << EOF > tmp_manage/mas_manage_config_encryptionkey.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-manage-db--es
  namespace: mas-${instanceid}-manage
data:
  MXE_SECURITY_CRYPTOX_KEY: $(echo -n ${cryptox_key} | base64)
  MXE_SECURITY_CRYPTO_KEY: $(echo -n ${crypto_key} | base64)
  MXE_SECURITY_OLD_CRYPTOX_KEY: $(echo -n ${oldcryptox_key} | base64)
  MXE_SECURITY_OLD_CRYPTO_KEY: $(echo -n ${oldcrypto_key} | base64)
type: Opaque

EOF

oc apply -f tmp_manage/mas_manage_config_encryptionkey.yaml > /dev/null 2>&1

IFS="," read -ra tmplangs <<< "$manageadditionallang"
langs=""
for i in "${tmplangs[@]}"
do
  langs+="        - $i"$'\n'
done 


IFS="," read -ra tmpmodules <<< "$managemodules"
modules=""
for i in "${tmpmodules[@]}"
do
  IFS=":" read -ra currentmodule <<< "$i"
  modules+="    ${currentmodule[0]}:"$'\n'
  modules+="      version: ${currentmodule[1]}"$'\n'
done 


managecerts=""
for file in "$(ls managecerts/*.crt)"
do 
  if [[ -f "$file" ]]; then
    tmpalias=$(basename $file)
    managecerts+="- alias: ${tmpalias%.*}"$'\n'
    managecerts+="  crt: |-"$'\n'
    managecerts+="$(cat ${file} | sed 's/^/\ \ \ \ /g' )"
  fi
done
managecerts=$(echo -n "${managecerts}" | sed 's/^/\ \ \ \ \ \ \ \ /g')

cat << EOF > tmp_manage/mas_manage_config.yaml
apiVersion: apps.mas.ibm.com/v1
kind: ManageWorkspace
metadata:
  name: ${instanceid}-${workspaceid}
  namespace: mas-${instanceid}-manage
  labels:
    mas.ibm.com/applicationId: manage
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
spec:
  bindings:
    jdbc: workspace-application
  components:
${modules}
  settings:
    db:
      dbSchema: ${jdbcschema}
      encryptionSecret: ${instanceid}-manage-db--es
      maxinst:
        bypassUpgradeVersionCheck: false
        db2Vargraphic: ${managedb2Vargraphic}
        demodata: ${managedemodata}
        indexSpace: ${manageindexspace}
        tableSpace: ${managetablespace}
    deployment:
      buildTag: ${managebuildtag}
      mode: up
      importedCerts:
${managecerts}
      persistentVolumes:
        - mountPath: /mnt/maximodocs
          pvcName: doclinks-pvc
          volumeName: ''
          size: ${managedoclinkssize}
          storageClassName: ${managedoclinksstorageclass}
      serverTimezone: ${manageservertimezone}
    languages:
      baseLang: ${managebaselang}
      secondaryLangs:
${langs}

EOF

oc apply -f tmp_manage/mas_manage_config.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo "${COLOR_RED}You now have to log in MAS dashboard and choose the bundle types${COLOR_RESET}"

echo -n "	Workspace Config Ready      "
while [[ $(oc get ManageWorkspace  --ignore-not-found=true -n mas-${instanceid}-demo --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


if [[ -z "$(oc get Kafka ${kafkaclustername} -n ${kafkanamespace})" == *"NotFound"* ]]; then

echo_h1 "Deploying Kafka for MAS"
oc project "${kafkanamespace}" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "${kafkanamespace}" --display-name "MAS Kafka" > /dev/null 2>&1
fi

namespace=$(oc config view --minify -o 'jsonpath={..namespace}')

operator_name=$(oc get ClusterServiceVersion strimzi-cluster-operator.v0.22.1 -n ${namespace} -o jsonpath="{.spec.install.spec.deployments[0].name}")
if [[ -z ${operator_name} ]]; then  # We must deploy operatorgroup, operator and cluster as no strimzi operator in this namespace have been found

echo_h2 "[1/4] Installing operator"
echo "	Operator will be by default set up to manual on channel 8.x"

cat << EOF > tmp_manage/strimzi_operatorgroup.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kafka-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

oc apply -f tmp_manage/strimzi_operatorgroup.yaml > /dev/null 2>&1
echo "	Operator group created"

cat << EOF > tmp_manage/strimzi_operator.yaml
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

oc apply -f tmp_manage/strimzi_operator.yaml > /dev/null 2>&1
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

fi # end of strimzi operator instanciation

echo_h2 "[2/4] Instanciating kafka cluster"

cat << EOF > tmp_manage/kafka_instance.yaml
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

oc apply -f tmp_manage/kafka_instance.yaml > /dev/null 2>&1

fi #end if Kafka Cluster must be created

echo -n "	Kafka ready              "
while [[ $(oc get Kafka ${kafkaclustername} --ignore-not-found=true -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" -n ${namespace}) != "True" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

fi

echo_h2 "[3/4] Creating user..."
cat << EOF > tmp_manage/kafka_user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  labels:
    strimzi.io/cluster: ${kafkaclustername}
  name: ${kafkauser}
  namespace: ${namespace}
spec:
  authentication:
    type: scram-sha-512
  authorization:
    acls:
      - host: '*'
        operation: All
        resource:
          name: manage-
          patternType: prefix
          type: topic
        type: allow
    type: simple
EOF
oc apply -f tmp_manage/kafka_user.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h2 "[3/4] Creating topics..."
cat << EOF > tmp_manage/kafka_topics.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-cqin
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-cqinerr
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-sqin
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-sqout
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-notf
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-notferr
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
---
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaTopic
metadata:
  labels:
    strimzi.io/cluster: maskafka
  name: manage-weather
  namespace: mas-kafka
spec:
  config:
    retention.ms: 604800000
    segment.bytes: 1073741824
  partitions: 10
  replicas: 3
EOF

oc apply -f tmp_manage/kafka_topics.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
echo "MAS Manage kafka user     : $kafkauser"
echo "MAS Manage kafka password : $(oc get Secret $kafkauser -n $kafkanamespace -o jsonpath=\"{.data.password}\" | base64 -d)"