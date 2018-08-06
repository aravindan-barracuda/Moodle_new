# Custom Script for Linux

#!/bin/bash

# The MIT License (MIT)
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Common functions definitions

function get_setup_params_from_configs_json
{
    local configs_json_path=${1}    # E.g., /var/lib/cloud/instance/moodle_on_azure_configs.json

    (dpkg -l jq &> /dev/null) || (apt -y update; apt -y install jq)

    # Wait for the cloud-init write-files user data file to be generated (just in case)
    local wait_time_sec=0
    while [ ! -f "$configs_json_path" ]; do
        sleep 15
        let "wait_time_sec += 15"
        if [ "$wait_time_sec" -ge "1800" ]; then
            echo "Error: Cloud-init write-files didn't complete in 30 minutes!"
            return 1
        fi
    done

    local json=$(cat $configs_json_path)

    export lbdns=$(echo $json | jq -r .wafProfile.lbdns)
    export wafpasswd=$(echo $json | jq -r .wafProfile.wafpasswd)
    export waflbdns=$(echo $json | jq -r .wafProfile.waflbdns)
    export siteFQDN=$(echo $json | jq -r .siteProfile.siteURL)
    
}
get_setup_params_from_configs_json $moodle_on_azure_configs_json_path || exit 99
echo $lbdns >> /tmp/vars.txt
echo $wafpasswd >> /tmp/vars.txt
echo $waflbdns >> /tmp/vars.txt
{
# Check for the WAF availability

for i in 8000 8001; do
(curl -I http://$waflbdns:$i/|grep "200")>/tmp/status-$i

# Login Token
export LOGIN_TOKEN=$(curl -X POST "http://$waflbdns:$i/restapi/v3/login" -H "Content-Type: application/json" -H "accept: application/json" -d '{"username":"admin","password":"'$wafpasswd'"}'| jq -r .token)
curl -X GET "http://$waflbdns:$i/restapi/v3/system?groups=WAN Configuration" -H "accept: application/json" -H "Content-Type: application/json" -u "'$LOGIN_TOKEN':" > /tmp/wafip.txt
export ipfile=$(cat /tmp/wafip.txt)
export wafip=$(echo $ipfile | jq -r '.data.System."WAN Configuration"."ip-address"')
export wafip=$(echo $ipfile | jq -r '.data.System."WAN Configuration".mask')

# Creating the certificate

curl -X POST "http://$waflbdns:$i/restapi/v3/certificates" -H "accept: application/json" -u "'$LOGIN_TOKEN':" -H "Content-Type: application/json" -d '{ "allow_private_key_export": "Yes", "city": "San Franscisco", "common_name": ""$siteFQDN"", "country_code": "US", "curve_type": "secp256r1", "key_size": "2048", "key_type": "rsa", "name": "moodle_cert", "organization_name": "Moodle", "organization_unit": "MoodleTeam", "state": "CA"}'

# Creating the service

curl -X POST "http://$waflbdns:$i/restapi/v3/services" -H "accept: application/json" -u "'$LOGIN_TOKEN':" -H "Content-Type: application/json" -d '{ "address-version": "IPv4", "app-id": "moodle", "certificate": "moodle_cert", "group": "default", "ip-address": "'$wafip'", "mask": "'$wafipmask'", "name": "moodle_service", "port": 443, "status": "On", "type": "HTTPS", "vsite": "default"}'

# Creating the server

curl -X POST "http://$waflbdns:$i/restapi/v3/services/moodle_service/servers" -H "accept: application/json" -u "'$LOGIN_TOKEN':" -H "Content-Type: application/json" -d '{ "hostname": "'$lbdns'", "status": "In Service", "identifier": "Hostname", "address-version": "IPv4", "name": "moodle_server", "port": 443}'

# Enabling SSL on the server

curl -X PUT "http://$waflbdns:$i/restapi/v3/services/moodle_service/servers/moodle_server/ssl-policy" -H "accept: application/json" -u "'$LOGIN_TOKEN':" -H "Content-Type: application/json" -d '{ "enable-ssl-compatibility-mode": "No", "enable-https": "Yes", "enable-tls-1": "No", "enable-tls-1-2": "Yes", "enable-ssl-3": "No", "enable-sni": "No", "validate-certificate": "No", "enable-tls-1-1": "Yes", "client-certificate": ""}'

 
OUTPUT = $(curl -X GET "http://$waflbdns:$i/restapi/v3/services?category=operational" -u "'$LOGIN_TOKEN':" )
echo "$OUTPUT" } > /tmp/setup.log
done

