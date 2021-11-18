# MAS 8.x Deployer
## Automatic deployer of MAS 8.6 for quick start

This script is used to :
- deploy all pre-requisite of Maximo Appication Suite
- deploy Maximo Appication Suite
- deploy Maximo Manage
- deploy Maximo Scheduler Optimization



## How to use it

- You first need to have an openshift cluster, in version 4.6 or superior (4.7 and 4.8 are not tested but should work)
- You may need a domain name, to shorten url. Be careful : There are some limitation in software (eg: MAS Mobile) which will add a constraint on url length : url length must be less than 100 characters. having a domain name will be then useful to shorten the default url.
- You  may need to manually create a webhook / alter the script to add extra step to manage SSL certificates according to your domain name. Today cert-manager have built-in domain name support, such as cloudfare, google, azuredns, etc. (see https://cert-manager.io/docs/configuration/acme/dns01/)
This script does not manually generate ClusterIssuer, which should be on your behalf to create SSL certificate automatically.
- ensure you are logged in before running the scripts :
```
oc whoami
```
If you are not logged in, please log in with the command :
```
oc login --token=sha256~LTMSoYifev9r8K-...TLXOEF7AyXnzzEFqc --server=https://....containers.cloud.ibm.com:31710
```

In order to install automatically the software you have to :
- modify mas.properties file, in order to match your settings
- modify masmanage.properties file if you want to deploy MAS Manage
- modify masmso.properties file if you want to deploy MAS Maximo Scheduler Optimization
- install the pre-requisites 
- install MAS Core
- install MAS Manage
- install MAS MSO

## mas.properties file
*ER_KEY* is the entitlement key obtained through the container library software panel on myibm.ibm.com website. This value is mandatory and will be repeated in all properties file.

*domain* is the domain name that should be used to register all apps. If unset, the ingress subdomain will be resolved. If you purchased a domain, you should add a CNAME record to your DNS zone pointing to the ingress subdomain domain.

## MAS Pre-requisite
To install the pre-requisite, simply use :
```
./install_prereqs.sh
```
This will install : 
- Service Bindings Operator, version 0.8.0 (a new version is available but incompatible with MAS for now)
- MongoDB Community Edition, and create ssl self signed certificates
- BAS (Behavior Analytics Services) operator and an analytic proxy deployment (behind the scene it generate a Kafka Cluster, dedicated for BAS)
- Enable IBM Operator Catalog
- Install IBM Common Services operator, Operand Lifecycle Manager
- Cert-manager (without ClusterIssuer : you will have to create your own before continuing if you want to have valid certificates)
- IBM Suite License Service (AppPoints Server)

## MAS Core
MAS Core needs some software to be completely setup. When installing MAS Core, you can interact / setup the integration in 2 ways.
First  way is through a graphical dashboard, available on url https://admin.<domain>/intialsetup and the script will output the credentials on the console or available in a secret :
```
# instanceid is the value setup in the mas.properties file
namespace=mas-${instanceid}-core
echo -n "Username: "
oc get secret ${instanceid}-credentials-superuser -o jsonpath='{.data.username}' -n ${namespace} | base64 --decode && echo ""
echo -n "Password: "
oc get secret ${instanceid}-credentials-superuser -o jsonpath='{.data.password}' -n ${namespace} | base64 --decode && echo ""
```
Second way is to create all CustomResource directly within openshift. The operator will take care of them and create all bindings / configuration associated to them. These scripts use this way to configure everything.
To install MAS Core, simply use
```
./install_mas.sh
```

## MAS Manage
MAS Manage is not fully automated for now (not sure it will be) : the declaration of bundles is more complex / obscur and easy / quick to perform manually.
```
./install_mas_manage.sh 
```
This script will create :
- the database configuration
- persistent volume storage  (used for doclinks)
- the selected components (base, transportation, etc.)
- the selected languages
This script will _not_ create:
- the pod / bundles : you have to manually create them in the MAS dashboard. Once setup, just click on activate and your MAS Manage will be built and deployed

## MAS MSO
```
./install_mas_mso.sh 
```
Once deployed / activated, you will need to grant a user in MAS dashboard to MSO, in order to connect to MSO dashboard at https://<instanceid>.mso.<domain>/
Then navigate in the "Projects" section and copy the api key
In maximo system properties, you must now modify the values :
- optimization.mofapi.apikey : the apikey you just get from MSO dashboard
- optimization.mofapi.baseurl : https://<instanceid>.api.mso.<domain>
- optimization.mofui.url : https://<instanceid>.mso.<domain>

Save and refresh : you can now run optimization scenario within Scheduler.