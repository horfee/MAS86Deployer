#!/bin/bash


############################################
############ Beginning the work ############
############################################
source mas-script-functions.bash
source masmonitor.properties


echo_h1 "Deploying CP4D"
oc project "${cp4dnamespace}" > /dev/null 2>&1
if [[ "$?" == "1" ]]; then
  oc new-project "${cp4dnamespace}" --display-name "Cloud Pak For Data" > /dev/null 2>&1
fi

rm -rf tmp_monitor
mkdir tmp_monitor

domain=$(oc get Ingress.config cluster -o jsonpath='{.spec.domain}')

# Fetch client installer from https://github.com/IBM/cpd-cli/releases according to your system
echo -n "	Fetching CP4D install command line..."
cd tmp_monitor
mkdir cp4d

cpdcli_version=3.5.7
if [[ "$OSTYPE" == "darwin"* ]]; then
  wget https://github.com/IBM/cpd-cli/releases/download/v${cpdcli_version}/cpd-cli-darwin-EE-${cpdcli_version}.tgz
  tar zxvf cpd-cli-darwin-EE-${cpdcli_version}.tgz -C ./cp4d
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  wget https://github.com/IBM/cpd-cli/releases/download/v${cpdcli_version}/cpd-cli-linux-EE-${cpdcli_version}.tgz
  tar zxvf cpd-cli-linux-EE-${cpdcli_version}.tgz -C ./cp4d
fi


cd cp4d
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	Creating registry route..."
# ATTENTION : if you are not a the bastion node, you will have to create a route for registry
cat << EOF > ../create_registry_route.yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: registry
  namespace: openshift-image-registry
spec:
  host: registry-openshift-image-registry.${domain}
  to:
    kind: Service
    name: image-registry
  weight: 100
  port:
    targetPort: 5000-tcp
  tls:
    termination: passthrough
    insecureEdgeTerminationPolicy: None
  wildcardPolicy: None
EOF

oc apply -f ../create_registry_route.yaml > /dev/null 1>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"


sed -i -e "s/<enter_api_key>/${ER_KEY}/g" repo.yaml

echo "	Need to deploy CP4D services : $cp4dassemblies."

IFS="," read -ra assemblies <<< "$cp4dassemblies"
for assembly in "${assemblies[@]}"
do
  echo " 	Deploying CP4D $assembly assembly..."
  ./cpd-cli adm --assembly $assembly --namespace ${cp4dnamespace} --repo ./repo.yaml --apply --accept-all-licenses
  ./cpd-cli install --assembly $assembly --namespace ${cp4dnamespace} --repo ./repo.yaml --storageclass $cp4dstorageclass --transfer-image-to=registry-openshift-image-registry.${domain}/${cp4dnamespace} --target-registry-username=$(oc whoami) --target-registry-password=$(oc whoami -t) --insecure-skip-tls-verify --cluster-pull-prefix=image-registry.openshift-image-registry.svc:5000/${cp4dnamespace} --latest-dependency --accept-all-licenses
  echo "${COLOR_GREEN}Done${COLOR_RESET}"
done 

cd ../

echo "  Fetching CP4D token"

cp4dpassword=$(oc get Secret admin-user-details -n ${cp4dnamespace} -o jsonpath="{.data.initial_admin_password}" | base64 -d)
cp4duser=admin
cp4durl="https://$(oc get route -n ${cp4dnamespace} --no-headers | awk '{printf $2}')/icp4d-api/v1"

echo "  Getting CP4D token"
cp4dtoken=$(curl --insecure -s -X POST -d "{\"username\":\"${cp4duser}\",\"password\":\"${cp4dpassword}\"}" "${cp4durl}/authorize" -H 'Content-Type: application/json')
cp4dtokenvalid=$(echo $cp4dtoken | jq -r "._messageCode_")
if [[ "$cp4dtokenvalid" == "200" ]]; then
  cp4dtoken=$(echo $cp4dtoken | jq -r ".token")
else
  echo "invalid token"
  exit 1
fi

echo "  Creating a new db2 user"
cp4duserrole=zen_administrator_role

res=$(curl --insecure -s -X POST -H "Authorization: Bearer ${cp4dtoken}" -H "Content-Type: application/json" -H "cache-control: no-cache" -d "{\"user_name\":\"${cp4dmonitoruser}\",\"password\":\"${cp4dmonitorpassword}\",\"displayName\":\"MAS Monitor user\",\"user_roles\":[\"${cp4duserrole}\"],\"email\":\"masuser@zen.local\"}" "${cp4durl}/users")
#echo curl --insecure -s -X POST -H "Authorization: Bearer ${cp4dtoken}" -H "Content-Type: application/json" -H "cache-control: no-cache" -d "{\"user_name\":\"${cp4dmonitoruser}\",\"password\":\"${cp4dmonitorpassword}\",\"displayName\":\"MAS Monitor user\",\"user_roles\":[\"${cp4duserrole}\"],\"email\":\"masuser@zen.local\"}" "${cp4durl}/users"

resCode=$(echo "$res" | jq "._messageCode_" | tr -d '"')
echo "Rescode = $resCode"

if [[ "$resCode" != "200" ]]; then
  echo "Error during user creation..."
  echo $(echo \"$res\" | jq -r \".message\")
  exit 1
fi


# TODO create a DB2WH instance name IOTDB
# TODO grant masuer access to IOTDB
# TODO retrieve SSL certificate, url, port
echo "You must now log into Cloud Pak For Data dashboard, create a db2wh instance and grant access to user ${cp4dmonitoruser} to this new database "
echo "What is the deployment id of this new database ? "
echo -n "(1-65535)>"
read cpd4deploymentid

echo "What is the port number of this new database ? "
echo -n "(1-65535)>"
read cp4dport

echo "What is the database name ? (default should be BLUDB)"
echo -n ">"
read cp4ddb
#cp4dport=32257
cp4dhost=c-db2wh-${cpd4deploymentid}-db2u-engn-svc.${cp4dnamespace}.svc
#$(oc get route -n ${cp4dnamespace} --no-headers | awk '{printf $2}')
cp4durl="jdbc:db2://${cp4dhost}:${cp4dport}/${cp4ddb}:securityMechanism=9;sslConnection=true;encryptionAlgorithm=2;"

cpd4dcertificates=$(fetchCertificates $cp4dhost $cp4dport)
cpd4dcertificate1=$(getcert "${cpd4dcertificates}" 2 | sed 's/^/\ \ \ \ \ \ \ \ /g')
cpd4dcertificate2=$(getcert "${cpd4dcertificates}" 1 | sed 's/^/\ \ \ \ \ \ \ \ /g')


echo -n "Creating MAS JDBC Config..."

cat << EOF > tmp_monitor/mas_jdbc_config.yaml
apiVersion: config.mas.ibm.com/v1
kind: JdbcCfg
metadata:
  name: ${instanceid}-jdbc-system
  namespace: mas-${instanceid}-core
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
spec:
  certificates:
    - alias: jdbccert1
      crt: |-
${cpd4dcertificate1}
    - alias: jdbccert2
      crt: |-
${cpd4dcertificate2}
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-jdbc-creds-system
    driverOptions: {}
    sslEnabled: true
    url: ${cp4durl}
  displayName: MAS DB2 connection
  type: external
---
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-jdbc-creds-system
  namespace: mas-${instanceid}-core
data:
  username: $(echo -n "${cp4dmonitoruser}" | base64)
  password: $(echo -n "${cp4dmonitorpassword}" | base64)
type: Opaque
EOF

oc apply -f tmp_monitor/mas_jdbc_config.yaml > /dev/null 2>&1
echo "${COLOR_GREEN}Done${COLOR_RESET}"

echo -n "	JDBC Configuration ready              "
while [[ $(oc get JdbcCfg ${instanceid}-jdbc-system --ignore-not-found=true -o jsonpath="{.status.conditions[?(@.type=='Ready')].status}" -n mas-${instanceid}-core) != "True" ]];do sleep 5; done & 
showWorking $!
printf '\b'
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"


echo -n " Creating Kafka user..."
cat << EOF > tmp_monitor/kafka_iot_user.yaml
apiVersion: kafka.strimzi.io/v1beta2
kind: KafkaUser
metadata:
  labels:
    strimzi.io/cluster: ${kafkaclustername}
  name: ${kafkauser}
  namespace: ${kafkanamespace}
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
        type: allow
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: group
        type: allow
      - host: '*'
        operation: All
        resource:
          type: cluster
        type: allow
      - host: '*'
        operation: All
        resource:
          name: '*'
          patternType: prefix
          type: transactionalId
        type: allow
    type: simple
EOF

oc apply -f tmp_monitor/kafka_iot_user.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

fi

kafkauser_password=$(oc get Secret ${kafkauser} -n ${kafkanamespace} -o jsonpath='{.data.password}')

kafka_url1=${kafkaclustername}-kafka-0.${kafkaclustername}-kafka-brokers.${kafkanamespace}.svc
kafka_url2=${kafkaclustername}-kafka-1.${kafkaclustername}-kafka-brokers.${kafkanamespace}.svc
kafka_url3=${kafkaclustername}-kafka-2.${kafkaclustername}-kafka-brokers.${kafkanamespace}.svc



kafkacertificates=$(oc get Kafka maskafka -n mas-kafka -o json | jq -r ".status.listeners | .[]? | .certificates  | .[]?")
nbCertif=$(echo "${kafkacertificates}"| grep -o BEGIN | wc -w | tr -d ' ')

certifYaml=""
for ((i=1;i<=$nbCertif;i++))
do
  certifYaml+="    - alias: kafka${i}"$'\n'
  certifYaml+="      crt: |"$'\n'
  certifYaml+=$(getcert "${kafkacertificates}" $i | sed 's/^/\ \ \ \ \ \ \ \ /g')$'\n'
done

echo -n "Creating  MAS  Kafka config..."
cat << EOF > tmp_monitor/mas_kafka_config.yaml
apiVersion: config.mas.ibm.com/v1
kind: KafkaCfg
metadata:
  name: ${instanceid}-kafka-system
  labels:
    mas.ibm.com/configScope: system
    mas.ibm.com/instanceId: ${instanceid}
  namespace: mas-${instanceid}-core
spec:
  certificates:
${certifYaml}
  config:
    credentials:
      secretName: ${instanceid}-usersupplied-kafka-creds-system
    hosts:
      - host: ${kafka_url1}
        port: 9093
      - host: ${kafka_url2}
        port: 9093
      - host: ${kafka_url3}
        port: 9093
    saslMechanism: SCRAM-SHA-512
  displayName: Kafka service
  type: external
EOF

oc apply -f tmp_monitor/mas_kafka_config.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"

while [[ $(oc get KafkaCfg ${instanceid}-kafka-system --ignore-not-found=true -n mas-${instanceid}-core --no-headers -o jsonpath="{.metadata.uid}") == "" ]];do  sleep 1; done &
showWorking $!
printf '\b'
owneruid=$(oc get KafkaCfg ${instanceid}-kafka-system --ignore-not-found=true -n mas-${instanceid}-core --no-headers -o jsonpath="{.metadata.uid}")


echo -n "Creating MAS Kafka config credentials..."
cat  << EOF > tmp_monitor/mas_kafka_config_credentials.yaml
kind: Secret
apiVersion: v1
metadata:
  name: ${instanceid}-usersupplied-kafka-creds-system
  namespace: mas-${instanceid}-core
  ownerReferences:
    - apiVersion: config.mas.ibm.com/v1
      kind: KafkaCfg
      name: ${instanceid}-kafka-system
      uid: ${owneruid}
data:
  password: ${kafkauser_password}
  username: $(echo -n "${kafkauser}" | base64)
type: Opaque
EOF

oc apply -f tmp_monitor/mas_kafka_config_credentials.yaml > /dev/null 2>&1
echo -e "${COLOR_GREEN}[OK]${COLOR_RESET}"
