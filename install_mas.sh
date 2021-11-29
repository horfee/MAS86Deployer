#!/bin/bash


############################################
############ Beginning the work ############
############################################
source mas-script-functions.bash
source mas.properties

echo_h1 "Deploying Maximo Application Suite"
oc project "mas-${instanceid}-core" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "mas-${instanceid}-core" --display-name "Maximo Application Suite" > /dev/null 2>&1
fi

rm -rf tmp_mas
mkdir tmp_mas


namespace=$(oc config view --minify -o 'jsonpath={..namespace}')

echo -n "[INIT] Creating IBM entitlement secret... "
oc -n ${namespace} create secret docker-registry ibm-entitlement --docker-server=cp.icr.io --docker-username=cp  --docker-password=${ER_KEY} > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

if [[ -z "${domain}" ]]; then 
  echo "Resolving domain through Ingress configuration..."
  domain=$(oc get Ingress.config cluster -o jsonpath='{.spec.domain}')
  echo "Domain is ${domain}"
else
  echo "Domain is preset with ${domain}"
fi

echo_h2 "[1/8] Installing operator"
echo "	Operator will be by default set up to manual on channel 8.x"

cat << EOF > tmp_mas/mas_operatorgroup.yaml
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ibm-mas-operatorgroup
  namespace: ${namespace}
spec:
  targetNamespaces:
    - ${namespace}
EOF

oc apply -f tmp_mas/mas_operatorgroup.yaml > /dev/null 2>&1
echo "	Operator group created"

cat << EOF > tmp_mas/mas_operator.yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ibm-mas
  namespace: ${namespace}
spec:
  channel: 8.x
  installPlanApproval: Manual
  name: ibm-mas
  source: ibm-operator-catalog
  sourceNamespace: openshift-marketplace
EOF

oc apply -f tmp_mas/mas_operator.yaml > /dev/null 2>&1
echo "	Operator created"

while [[ $(oc get Subscription ibm-mas -n ${namespace} --ignore-not-found=true -o jsonpath='{.status.state}') != "UpgradePending" ]];do sleep 5; done & 
showWorking $!
printf '\b'

echo "	Approving manual installation"
# Find install plan
installplan=$(oc get subscription ibm-mas -o jsonpath="{.status.installplan.name}" -n ${namespace})
echo "	installplan: $installplan"

# Approve install plan
oc patch installplan ${installplan} -n ${namespace} --type merge --patch '{"spec":{"approved":true}}' > /dev/null 2>&1

echo -n "	Operator ready              "
while [[ $(oc get deployment/ibm-mas-operator --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "1" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo -n "	Instanciating the suite... "
cat << EOF > tmp_mas/mas_suite.yaml
apiVersion: core.mas.ibm.com/v1
kind: Suite
metadata:
  name: ${instanceid}
  namespace: ${namespace}
  labels:
    mas.ibm.com/instanceId: ${instanceid}
spec:
  domain: "${domain}"
  settings:
    icr:
      cp: "cp.icr.io/cp"
      cpopen: "icr.io/cpopen"
  license:
    accept: true
EOF


if [ ! -z ${clusterissuer+x} ]; then

  if  [ -z ${clusterissuer_renew} ]; then
    clusterissuer_renew="720h0m0s"
  fi

  if  [ -z ${clusterissuer_duration} ]; then
    clusterissuer_duration="8760h0m0s"
  fi

  cat << EOF >> tmp_mas/mas_suite.yaml
  certificateIssuer:
    name: ${clusterissuer}
    renewBefore: ${clusterissuer_renew}
    duration: ${clusterissuer_duration}
EOF
fi

oc apply -f tmp_mas/mas_suite.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 1
while [[ $(oc get Suite ${instanceid} --ignore-not-found=true -n ${namespace} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'

echo -n "	Admin dashboard ready       "
while [[ $(oc get deployment/${instanceid}-admin-dashboard --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "1" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo -n "	Core API ready              "
while [[ $(oc get deployment/${instanceid}-coreapi --ignore-not-found=true -o jsonpath='{.status.readyReplicas}' -n ${namespace}) != "3" ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

owneruid=$(oc get Suite ${instanceid} -n ${namespace} -o jsonpath="{.metadata.uid}")


echo_h1 "Installation Summary"
echo_h2 "Administration Dashboard URL"
echo_highlight "https://admin.${domain}"

echo_h2 "Super User Credentials"
echo -n "Username: "
oc get secret ${instanceid}-credentials-superuser -o jsonpath='{.data.username}' -n ${namespace} | base64 --decode && echo ""
echo -n "Password: "
oc get secret ${instanceid}-credentials-superuser -o jsonpath='{.data.password}' -n ${namespace} | base64 --decode && echo ""


echo_h2 "[2/8] Instanciating Mongo configuration"
echo "	Retriving certificates from mongodb generated scripts"
mongosvc=$(oc get service -n ${MONGO_NAMESPACE} | grep -i ClusterIP | awk '{printf $1}')
mongopod=$(oc get pods --selector app=$mongosvc -n mongo | sed '2!d' | awk '{printf $1}')
tmpcert=$(oc -n mongo -c mongod exec $mongopod -- openssl s_client -connect localhost:27017 -showcerts 2>&1 < /dev/null  | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')
mongoCACertificate=$(getcert "$tmpcert" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
mongoServerCertificate=$(getcert "$tmpcert" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')

echo -n "	Creating mongo configuration... "
cat << EOF > tmp_mas/mas_mongocfg.yaml
apiVersion: config.mas.ibm.com/v1
kind: MongoCfg
metadata:
  name: ${instanceid}-mongo-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
spec:
  certificates:
    - alias: cacert
      crt: |-
${mongoCACertificate}
    - alias: servercert
      crt: |-
${mongoServerCertificate}
  config:
    authMechanism: DEFAULT
    configDb: admin
    credentials:
      secretName: ${instanceid}-usersupplied-mongo-creds-system
    hosts:
      - host: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-1.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
      - host: mas-mongo-ce-2.mas-mongo-ce-svc.mongo.svc.cluster.local
        port: 27017
  displayName: mas-mongo-ce-0.mas-mongo-ce-svc.mongo.svc.cluster.local
  type: external
EOF

oc apply -f tmp_mas/mas_mongocfg.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 1
while [[ $(oc get MongoCfg ${instanceid}-mongo-system --ignore-not-found=true -n ${namespace} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
mongoowneruid=$(oc get MongoCfg ${instanceid}-mongo-system -n ${namespace} -o jsonpath="{.metadata.uid}")
mongocfgpassword=$(oc -n ${MONGO_NAMESPACE} get secret mas-mongo-ce-admin-password -o jsonpath="{.data.password}" | base64 -d)

echo -n "	Creating mongo configuration credentials... "
cat << EOF > tmp_mas/mas_mongocfg_mongo_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-mongo-creds-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: MongoCfg
      name: ${instanceid}-mongo-system
      uid: ${mongoowneruid}
data:
  password: $(echo -n "${mongocfgpassword}" | base64)
  username: $(echo -n "admin" | base64 )
type: Opaque  
EOF

oc apply -f tmp_mas/mas_mongocfg_mongo_credentials.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	Mongo Config Ready      "
while [[ $(oc get MongoCfg ${instanceid}-mongo-system --ignore-not-found=true -n ${namespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h2 "[3/8] Instanciating BAS configuration"
echo "	Retrieving BAS endpoint"
bas_endpoint=$(oc get routes bas-endpoint -n "${bas_projectName}" | awk 'NR==2 {print $2}')
bas_url=https://$bas_endpoint

echo "	Retrieving BAS API KEY"
bas_apikey=$( oc get secret bas-api-key --output="jsonpath={.data.apikey}" -n ${bas_projectName})

echo "	Retriving BAS certificates"
bas_certificates=$(fetchCertificates $bas_endpoint 443)
basCA1Certificate=$(getcert "$bas_certificates" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')
basCA2Certificate=$(getcert "$bas_certificates" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
#basCA3Certificate=$(getcert "$bas_certificates" 3 | sed 's/^/\ \ \ \ \ \ \ \ /g')
#basCA4Certificate=$(wget -qO - https://letsencrypt.org/certs/lets-encrypt-r3-cross-signed.pem | sed 's/^/\ \ \ \ \ \ \ \ /g')
basCA5Certificate=$(wget -qO - https://letsencrypt.org/certs/isrgrootx1.pem | sed 's/^/\ \ \ \ \ \ \ \ /g')

echo -n "	Creating BAS configuration... "
cat << EOF > tmp_mas/mas_bascfg.yaml
apiVersion: config.mas.ibm.com/v1
kind: BasCfg
metadata:
  name: ${instanceid}-bas-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
spec:
  certificates:
    - alias: cacert1
      crt: |-
${basCA1Certificate}
    - alias: cacert2
      crt: |-
${basCA2Certificate}
    - alias: cacert5
      crt: |-
${basCA5Certificate}
  config:
    contact:
      email: ${contact_email}
      firstName: ${contact_firstname}
      lastName: ${contact_lastname}
    credentials:
      secretName: ${instanceid}-usersupplied-bas-creds-system
    url: '${bas_url}'
  displayName: System BAS Configuration
EOF

oc apply -f tmp_mas/mas_bascfg.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 1
while [[ $(oc get BasCfg ${instanceid}-bas-system --ignore-not-found=true -n ${namespace} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
basowneruid=$(oc get BasCfg ${instanceid}-bas-system -n ${namespace} -o jsonpath="{.metadata.uid}")

echo -n "	Creating BAS configuration credentials... "
cat << EOF > tmp_mas/mas_bascfg_bas_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-bas-creds-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: BasCfg
      name: ${instanceid}-bas-system
      uid: ${basowneruid}
data:
  api_key: ${bas_apikey} 
type: Opaque
EOF

oc apply -f tmp_mas/mas_bascfg_bas_credentials.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	BAS Config Ready      "
while [[ $(oc get BasCfg ${instanceid}-bas-system --ignore-not-found=true -n ${namespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h2 "[4/8] Instanciating SLS configuration"
echo "	Retriving SLS url"
sls_url=$(oc get ConfigMap sls-suite-registration -n ${slsnamespace} -o jsonpath="{.data.url}")

echo "	Retriving SLS configuration"
slscertificate=$(oc get ConfigMap sls-suite-registration -n ${slsnamespace} -o jsonpath="{.data.ca}"| sed 's/^/\ \ \ \ \ \ \ \ /g')

echo "	Retriving SLS registrationKey"
slsRegistrationKey=$(oc get ConfigMap sls-suite-registration -n ${slsnamespace} -o jsonpath="{.data.registrationKey}" | base64 )

echo -n "	Creating SLS configuration... "
cat << EOF > tmp_mas/mas_slsconfig.yaml
apiVersion: config.mas.ibm.com/v1
kind: SlsCfg
metadata:
  name: ${instanceid}-sls-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
spec:
  certificates:
    - alias: cacert
      crt: |-
${slscertificate}
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-sls-creds-system
    url: >-
      ${sls_url}
  displayName: System SLS Configuration
EOF

oc apply -f tmp_mas/mas_slsconfig.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

sleep 1
while [[ $(oc get SlsCfg ${instanceid}-sls-system --ignore-not-found=true -n ${namespace} --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
slsowneruid=$(oc get SlsCfg ${instanceid}-sls-system -n ${namespace} -o jsonpath="{.metadata.uid}")

echo -n "	Creating SLS configuration credentials... "
cat << EOF > tmp_mas/mas_slscfg_sls_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-sls-creds-system
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: SlsCfg
      name: ${instanceid}-sls-system
      uid: ${slsowneruid}
data:
  registrationKey: ${slsRegistrationKey} 
type: Opaque
EOF

oc apply -f tmp_mas/mas_slscfg_sls_credentials.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	SLS Config Ready      "
while [[ $(oc get SlsCfg ${instanceid}-sls-system --ignore-not-found=true -n ${namespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo "SLS host is : $(oc get -n ${slsnamespace} cm sls-rlks-cfg -o jsonpath='{.data.embedded\.yaml}' | head -4 | grep host | awk '{printf $2}' | tr -d '"')"
echo "SLS id is   : $(oc get -n ${slsnamespace} cm sls-rlks-cfg -o jsonpath='{.data.embedded\.yaml}' | head -4 | grep id | awk '{printf $3}' | tr -d '"')"
echo "SLS port is : $(oc get -n ${slsnamespace} cm sls-rlks-cfg -o jsonpath='{.data.embedded\.yaml}' | head -4 | grep lmgrdPort | awk '{printf $2}' | tr -d '"')"

echo_h2 "[5/8] Instanciating of workspace configuration"
echo "	workspace id is $workspaceid"

echo -n "	Creating Workspace configuration... "
cat << EOF > tmp_mas/mas_wsconfig.yaml
apiVersion: core.mas.ibm.com/v1
kind: Workspace
metadata:
  name: ${instanceid}-${workspaceid}
  namespace: ${namespace}
  labels:
    mas.ibm.com/instanceId: ${instanceid}
    mas.ibm.com/workspaceId: ${workspaceid}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid}
      uid: ${owneruid}
spec:
  displayName: ${workspacedisplayname}
  settings: {}
EOF

oc apply -f tmp_mas/mas_wsconfig.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	Workspace Config Ready      "
while [[ $(oc get Workspace ${instanceid}-${workspaceid} --ignore-not-found=true -n ${namespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

exit 0


echo_h2 "[6/8] Instanciating Manage JDBC configuration"
if [[ $jdbcurl == *"sslConnection=true"* ]]; then
  jdbcsslenabled=true

  echo "	Retriving JDBC SSL certificate"
  jdbccrt=$(fetchCertificates jdbcserver jdbcport)#openssl s_client -servername ${jdbcserver} -connect ${jdbcserver}:${jdbcport} -showcerts 2>&1 < /dev/null  | sed -ne '/BEGIN\ CERTIFICATE/,/END\ CERTIFICATE/p')
  jdbccrt=$(getcert $jdbccrt 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
else
  echo "	SSL disabled"
  jdbcsslenabled=false
fi

echo "	Creating JDBC configuration... "
cat << EOF > tmp_mas/mas_manage_jdbc_cfg.yaml
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${instanceid}-jdbc-wsapp-${workspaceid}-manage
  namespace: ${namespace}
  ownerReferences:
    - apiVersion: core.mas.ibm.com/v1
      kind: Suite
      name: ${instanceid)}
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

oc apply -f tmp_mas/mas_manage_jdbc_cfg.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "JDBC Config Ready      "
while [[ $(oc get JdbcCfg ${instanceid}-jdbc-wsapp-${workspaceid}-manage--ignore-not-found=true -n ${namespace} --no-headers) != *"Ready"* ]];do  sleep 5; done &
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo_h2 "[7/8] Creating kafka user..."

cat << EOF > tmp_mas/kafka_user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  name: ${kafkauser}
  labels:
    strimzi.io/cluster: ${kafkaclustername}
  namespace: ${namespace}
spec:
  authentication:
    type: scram-sha-512
  authorization:
    acls:
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: topic
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: group
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: literal
          type: topic
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: literal
          type: group
    type: simple
EOF

oc apply -f tmp_mas/kafka_user.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

echo_h2 "[8/8] Configuring MAS kafka"

kafkacert=$(oc get Kafka ${kafkaclustername} -n ${namespace} -o jsonpath="{.status.listeners[?(@.type=='tls')].certificates[0]}"| sed 's/^/\ \ \ \ \ \ \ \ \ \ /g')
kafkahost=$(oc get Kafka ${kafkaclustername} -n ${namespace} -o jsonpath="{.status.listeners[?(@.type=='tls')].addresses[0].host}")
kafkaport=$(oc get Kafka ${kafkaclustername} -n ${namespace} -o jsonpath="{.status.listeners[?(@.type=='tls')].addresses[0].port}")
kafkauserpassword=$(oc get secret $(oc get KafkaUser ${kafkauser} -n ${namespace} -o jsonpath="{.status.secret}") -n ${namespace} -o jsonpath="{.data.password}")

cat << EOF > tmp_mas/mas_config_kafka.yaml
apiVersion: config.mas.ibm.com/v1
kind: KafkaCfg
metadata:
  name: ${instanceid}-kafka-system
  namespace: mas-${instanceid}-core
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
spec:
  certificates:
    - alias: kafka
      crt: |-
${kafkacert}
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-kafka-creds-system
    hosts:
      - host: ${kafkahost}
        port: ${kafkaport}
    saslMechanism: SCRAM-SHA-512
  displayName: MAS Kafka configuration
  type: external
EOF

oc apply -f tmp_mas/mas_config_kafka.yaml > /dev/null 2>&1

cat << EOF > tmp_mas/mas_config_kafka_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-kafka-creds-system
  namespace: mas-${instanceid}-core
data:
  password: $(echo -n "${kafkauser}" | base64)
  username: ${kafkauserpassword}
type: Opaque  
EOF

oc apply -f tmp_mas/mas_config_kafka_credentials.yaml > /dev/null 2>&1

echo -n "	Configuration ready              "
while [[ $(oc get KafkaCfg ${instanceid}-kafka-system --ignore-not-found=true -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" -n mas-${instanceid}-core) != "True" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
