#!/bin/bash

urlencode() {
    # urlencode <string>
    old_lang=$LANG
    LANG=C
    
    old_lc_collate=$LC_COLLATE
    LC_COLLATE=C

    local length="${#1}"
    for (( i = 0; i < length; i++ )); do
        local c="${1:i:1}"
        case $c in
            [a-zA-Z0-9.~_-]) printf "$c" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done

    LANG=$old_lang
    LC_COLLATE=$old_lc_collate
}


#if [[ -z false ]]; then
rm /tmp/tokens.cookies
rm /tmp/output-step*

echo "Step 1 : Obtaining websession"
curl 'https://licensing.subscribenet.com/control/ibmr/login' \
  -i \
  -s \
  -H 'Connection: keep-alive' \
  -H 'Pragma: no-cache' \
  -H 'Cache-Control: no-cache' \
  -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="96", "Google Chrome";v="96"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -H 'Origin: https://licensing.subscribenet.com' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.55 Safari/537.36' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'Sec-Fetch-Mode: navigate' \
  -H 'Sec-Fetch-User: ?1' \
  -H 'Sec-Fetch-Dest: document' \
  -H 'Referer: https://licensing.subscribenet.com/control/ibmr/login' \
  -H 'Accept-Language: fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cookie: __utmv=175017023.|1=Partner=IBMR=1; PRTNR=ibmr; flexnet-http-cookie-123085=5ccba3d85890abf3aba3ab0acf8302ae2317b6a8ea83839c296c744bc87d8debd281c622; __utmc=175017023; __utmz=175017023.1637846540.3.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; __utma=175017023.573732691.1636446025.1637846540.1637853464.4; displayLLM=done; checkedReferrer=true; JSESSIONID=0000USGK0OiyU-iS7bWfKxYuUdi:-1; __utmt=1; __utmb=175017023.10.10.1637853464' \
  --location \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step1.html


echo "Step 2 : authenticating"
curl 'https://licensing.subscribenet.com/control/ibmr/login' \
  -s \
  -H 'Connection: keep-alive' \
  -H 'Pragma: no-cache' \
  -H 'Cache-Control: no-cache' \
  -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="96", "Google Chrome";v="96"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -H 'Origin: https://licensing.subscribenet.com' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.55 Safari/537.36' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'Sec-Fetch-Mode: navigate' \
  -H 'Sec-Fetch-User: ?1' \
  -H 'Sec-Fetch-Dest: document' \
  -H 'Referer: https://licensing.subscribenet.com/control/ibmr/login' \
  -H 'Accept-Language: fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cookie: __utmv=175017023.|1=Partner=IBMR=1; __utmc=175017023; __utmz=175017023.1637846540.3.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; __utma=175017023.573732691.1636446025.1637846540.1637853464.4; displayLLM=done; checkedReferrer=true; __utmt=1; __utmb=175017023.10.10.1637853464' \
  --data-raw 'nextURL=%2Fcontrol%2Fibmr%2Fibmrindex&action=authenticate&username=Jean-Philippe.alexandre%40fr.ibm.com&password=1ED-qVZ-3js-J3b' \
  --compressed \
  --location \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step2.html

newUrl=$(cat /tmp/output-step2.html | grep AppPoint | sed 's/^.*href="\(.*\)".*$/\1/g')

echo "Step 3 : selecting product : AppPoint"
curl "https://licensing.subscribenet.com/control/ibmr/${newUrl}" \
  -s \
  -H 'Cookie: __utmv=175017023.|1=Partner=IBMR=1; __utmc=175017023; __utmz=175017023.1637846540.3.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; __utma=175017023.573732691.1636446025.1637846540.1637853464.4; displayLLM=done; checkedReferrer=true; __utmt=1; __utmb=175017023.10.10.1637853464' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Accept-Encoding: gzip, deflate, br' \
  -H 'Host: licensing.subscribenet.com' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15' \
  -H 'Accept-Language: fr-FR,fr;q=0.9' \
  -H 'Referer: https://licensing.subscribenet.com/control/ibmr/ibmrindex' \
  -H 'Connection: keep-alive' \
  --compressed \
  --location \
  --cookie /tmp/tokens.cookies \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step3.html

oldUrl=${newUrl}
newUrl=$(cat /tmp/output-step3.html | grep "IBM MAXIMO APPLICATION SUITE AppPOINT LIC" | sed 's/^.*href="\(.*\)".*$/\1/g')

echo "Step 4 : selecting IBM MAXIMOAPPLICATION SUITE AppPOINT LIC"
curl "https://licensing.subscribenet.com/control/ibmr/${newUrl}" \
  -s \
  -H 'Connection: keep-alive' \
  -H 'Pragma: no-cache' \
  -H 'Cache-Control: no-cache' \
  -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="96", "Google Chrome";v="96"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.55 Safari/537.36' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'Sec-Fetch-Mode: navigate' \
  -H 'Sec-Fetch-User: ?1' \
  -H 'Sec-Fetch-Dest: document' \
  -H 'Referer: https://licensing.subscribenet.com/control/ibmr/${oldUrl}' \
  -H 'Accept-Language: fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cookie: __utmv=175017023.|1=Partner=IBMR=1; __utmc=175017023; __utmz=175017023.1637846540.3.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; displayLLM=done; snetpc=12967970:14896880:1637855331827:1637859619014; __utma=175017023.573732691.1636446025.1637853464.1637859628.5; __utmt=1; __utmb=175017023.1.10.1637859628' \
  --location \
  --cookie /tmp/tokens.cookies \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step4.html

#fi

newUrl=$(cat /tmp/output-step3.html | grep "IBM MAXIMO APPLICATION SUITE AppPOINT LIC" | sed 's/^.*href="\(.*\)".*$/\1/g')
cToken=$(cat /tmp/output-step4.html| grep 'name="cToken"' | sed 's/^.*\value="\(.*\)".*$/\1/g')
originParamElement=$(echo "$newUrl" | sed 's/.*=\(.*\)$/\1/g')

echo "CToken : ${cToken}"
echo "originParam-element : ${originParamElement}" 

echo "Step 5 : fetching parameters form"
curl 'https://licensing.subscribenet.com/control/ibmr/generatelicenses' \
  -s \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'Origin: https://licensing.subscribenet.com' \
  -H 'Cookie: __utma=175017023.2073768619.1637268584.1637851833.1637857512.5; __utmb=175017023.13.10.1637857512; __utmc=175017023; __utmv=175017023.|1=Partner=IBMR=1; __utmz=175017023.1637851833.4.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; displayLLM=done; __utmt=1;' \
  -H 'Accept-Language: fr-FR,fr;q=0.9' \
  -H 'Host: licensing.subscribenet.com' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.1 Safari/605.1.15' \
  -H "Referer: https://licensing.subscribenet.com/control/ibmr/${newUrl}" \
  -H 'Connection: keep-alive' \
  --data "cToken=$(urlencode ${cToken})" \
  --data "origin=view" \
  --data "productLine=IBM+AppPoint+Suites" \
  --data "originParam-plne=null" \
  --data "originParam-displayDetailedLicenseQuantity=null" \
  --data "originParam-element=${originParamElement}" \
  --data "isFlexPoint=false" \
  --data "generateLicenseRightKey0=IBMR_TELELOGIC%3A25105530%3A56376640%3Anull" \
  --location \
  --cookie /tmp/tokens.cookies \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step5.html


echo "Step 6 : generating licence file"
rlks_quantity=999
rlks_hostid=10005afe0b0a
rlks_hostname=sls-rlks-0.rlks
rlks_port=27000
expDate=$(sed -n '/input type="hidden" name="parameterGroup1_licenseExpDate"/,/" \/>/p' /tmp/output-step5.html | grep value | sed -n 's/.*value="\(.*\)".*/\1/p')
encoded_expDate=$(urlencode "$expDate")
encoded_cToken=$(echo "$encoded_cToken")

curl 'https://licensing.subscribenet.com/control/ibmr/generatelicenses' \
  -s \
  -H 'Connection: keep-alive' \
  -H 'Pragma: no-cache' \
  -H 'Cache-Control: no-cache' \
  -H 'sec-ch-ua: " Not A;Brand";v="99", "Chromium";v="96", "Google Chrome";v="96"' \
  -H 'sec-ch-ua-mobile: ?0' \
  -H 'sec-ch-ua-platform: "macOS"' \
  -H 'Upgrade-Insecure-Requests: 1' \
  -H 'Origin: https://licensing.subscribenet.com' \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -H 'User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/96.0.4664.55 Safari/537.36' \
  -H 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9' \
  -H 'Sec-Fetch-Site: same-origin' \
  -H 'Sec-Fetch-Mode: navigate' \
  -H 'Sec-Fetch-User: ?1' \
  -H 'Sec-Fetch-Dest: document' \
  -H 'Referer: https://licensing.subscribenet.com/control/ibmr/generatelicenses' \
  -H 'Accept-Language: fr-FR,fr;q=0.9,en-US;q=0.8,en;q=0.7' \
  -H 'Cookie: __utma=175017023.2073768619.1637268584.1637851833.1637857512.5; __utmb=175017023.13.10.1637857512; __utmc=175017023; __utmv=175017023.|1=Partner=IBMR=1; __utmz=175017023.1637851833.4.3.utmcsr=ibm.com|utmccn=(referral)|utmcmd=referral|utmcct=/; displayLLM=done; __utmt=1;' \
  --data "actionParam=process&origin=generate&originServlet=licenseproduct&originParam-orderKey=&originParam-displayDetailedLicenseQuantity=null&originParam-itemkey=&originParam-ordLnNum=&originParam-plne=null&originParam-element=${originParamElement}&generateLicenseRightKey0=IBMR_TELELOGIC%3A25105530%3A56376640%3Anull&parameterGroup1=IBMR_TELELOGIC%3A25105530%3A56376640%3Anull&parameterGroup1_licenseQty=${rlks_quantity}&parameterGroup1_maxDuration=&parameterGroup1_overrideExpDate=&parameterGroup1_productID=${originParamElement}&existing_host1=0&server_configuration1=single&parameterGroup1_svrHostIdType0=HST_TYP_ETHER&parameterGroup1_svrHostId0=${rlks_hostid}&parameterGroup1_svrHostName0=${rlks_hostname}&parameterGroup1_svrHostPort0=${rlks_port}&parameterGroup1_svrHostDscr0=&parameterGroup1_svrHostIdType1=HST_TYP_DSN&parameterGroup1_svrHostId1=&parameterGroup1_svrHostName1=&parameterGroup1_svrHostPort1=&parameterGroup1_svrHostDscr1=&parameterGroup1_svrHostIdType2=HST_TYP_DSN&parameterGroup1_svrHostId2=&parameterGroup1_svrHostName2=&parameterGroup1_svrHostPort2=&parameterGroup1_svrHostDscr2=" \
  --data "cToken=$encoded_cToken" \
  --data "parameterGroup1_licenseExpDate=$encoded_expDate" \
  --location \
  --cookie /tmp/tokens.cookies \
  --cookie-jar /tmp/tokens.cookies \
  -o /tmp/output-step6.html
