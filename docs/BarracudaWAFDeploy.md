# Deploying Barracuda WAF in the Moodle setup

The instructions will enable you to deploy the Barracuda WAF in a scale set along with the fully configurable moodle deployment. 

## Important Note:

The template is optimized for a deployment where the "httpsTermination" parameter is set to VMSS (this is the default setting in the template) for the Moodle stack.

The template can be launched from the Azure management console or through the commandline on a linux machine.

## Fully configurable deployment with Barracuda WAF (Pay-As-You-Go License)

This deployment will add the Barracuda Web Application Firewall to the moodle infrastructure.
The link below will redirect you to the Azure management console allowing you to specify various launch parameters for your Moodle cluster deployment.

[![Deploy to Azure Fully Configurable](http://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Faravindan-barracuda%2FMoodle%2Fmaster%2Fazuredeploy-withbwafpayg.json)

## CLI based deployment

### Prerequisites

First we need to ensure our environment variables are correctly configured.

Optional (Required if the [azure-credentials](https://github.com/pendrica/azure-credentials) gem is used to auto-generate the SPN): 

```
AZUREUSERNAME=<azure user account>
AZUREPASSWD=<azure account password>
```
Required:

```
WAFPASSWD=<waf password> #for example @Testing123456
MOODLE_RG_LOCATION=<location/region> #for example "eastus"
```

### Deployment Steps

The following snippet of bash commands will help to set up the environment variables to the point where you      can execute ```az group deployment create```

1. Environment variables

```
{
    if [ -z "$MOODLE_RG_NAME" ]; then MOODLE_RG_NAME=moodle_$(date +%Y-%m-%d-%H); fi
    echo "----> Resource Group for deployment: $MOODLE_RG_NAME"
    echo "----> Deployment location: $MOODLE_RG_LOCATION"
    MOODLE_DEPLOYMENT_NAME=MasterDeploy
    echo "----> Deployment name: $MOODLE_DEPLOYMENT_NAME"
    MOODLE_SSH_KEY_FILENAME=~/.ssh/moodle_id_rsa
    echo "----> SSH key filename: $MOODLE_SSH_KEY_FILENAME"
    MOODLE_AZURE_WORKSPACE=~/.moodle
    echo "----> Workspace directory: $MOODLE_AZURE_WORKSPACE"
    mkdir -p $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME
    if [ ! -f "$MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME" ]; then echo "Workspace exists"; fi
    echo "----> Preparing to install the necessary packages and finally installing azure-cli"
    sleep 5
    if hash wget 2>/dev/null; then echo "wget installed";else sudo apt-get update && sudo apt-get install -y wget;fi
    sudo apt-get -y openssh-client
    AZ_REPO=$(lsb_release -cs)
    echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
    sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893
    sudo apt-get install -y apt-transport-https
    if hash az 2>/dev/null; then echo "Azure CLI Installed"; else sudo apt-get update && sudo apt-get install -y azure-cli;fi
    echo "----> Generating the SSH Key"
    sleep 5
    if [ ! -f "$MOODLE_SSH_KEY_FILENAME" ]; then ssh-keygen -t rsa -N "" -f $MOODLE_SSH_KEY_FILENAME; fi
    git clone https://github.com/aravindan-barracuda/Moodle.git $MOODLE_AZURE_WORKSPACE/arm_template
    ls $MOODLE_AZURE_WORKSPACE/arm_template
}
```
2. Creating Azure Service Principal credentials

    Follow the instructions in the article [Azure SPN instructions](https://docs.microsoft.com/en-us/azure/azure-resource-manager/resource-group-create-service-principal-portal) for creating Azure Service Principal credentials.

    Alternatively, in the code snippet below, a helper gem called ```azure-credentials``` is used to create SPN credentials that will be used in the WAF to enable access to the WAF system to the Azure fabric. This is required in cases where a multi-ip/multi-NIC configuration is choosen for the deployment of the scaleset. This requires  ruby to be installed on the client machine on which the code is executed.

```
{
    if hash jq 2>/dev/null; then echo "jq is already installed";else sudo apt-get install -y jq;fi
    if hash azure-credentials 2>/dev/null;then echo "azure-credentials gem is already installed";else gem install azure-credentials;fi
    echo "fetching azure SPN credentials..."
    azure-credentials -u $AZUREUSERNAME -p $AZUREPASSWD -t puppet -o $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.conf
    echo "converting the azure.conf file"
    hocon -i $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.conf get azure --json > $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.json
    cat $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.json
    echo "Creating the resource group on Azure..."
    az group create --name $MOODLE_RG_NAME --location $MOODLE_RG_LOCATION
    ssh_pub_key=`cat $MOODLE_SSH_KEY_FILENAME.pub`
    echo $ssh_pub_key
    CLIENT_ID=`cat $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.json | jq '.client_id'`
    echo "client id is $CLIENT_ID"
    TENANT_ID=`cat $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.json | jq '.tenant_id'`
    echo "tenant id is $TENANT_ID"
    CLIENT_SECRET=`cat $MOODLE_AZURE_WORKSPACE/arm_template/scripts/azure.json | jq '.client_secret'`
    echo "client secret is $CLIENT_SECRET"
    echo "Generated env variables"
}
```
3. Generating the Parameters JSON file.

The following code snippet will update the parameters json file with the appropriate JSON keys and values to deploy the WAF scale set.

```
{
    echo "Now creating the new parameters json file..." && sleep 2
    sed -i "s|WAF-PASSWORD|$WAFPASSWD|g" $MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy.parameters.json > $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
    sed -i "s|\"CLIENT-ID\"|$CLIENT_ID|g" $MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy.parameters.json > $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
    sed -i "s|\"TENANT-ID\"|$TENANT_ID|g" $MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy.parameters.json > $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
    sed -i "s|\"CLIENT-SECRET\"|$CLIENT_SECRET|g" $MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy.parameters.json > $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
    sed "s|GEN-SSH-PUB-KEY|$ssh_pub_key|g" $MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy.parameters.json > $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
    cat $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json
}
```
4. Deploying the application with Barracuda WAF

Finally, use the following command to deploy the Barracuda WAF with the Moodle fully configurable setup.

```
az group deployment create --name $MOODLE_DEPLOYMENT_NAME \
--resource-group $MOODLE_RG_NAME --template-file \
$MOODLE_AZURE_WORKSPACE/arm_template/azuredeploy-withbwafpayg.json \
--parameters $MOODLE_AZURE_WORKSPACE/$MOODLE_RG_NAME/azuredeploy.parameters.json

```




