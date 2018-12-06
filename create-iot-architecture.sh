#!/bin/bash

#########################################################################
########################### IoT Architecture ############################
#########################################################################

########################### General configuration ############################
echo "########################### General configuration ############################"

### Add the IOT Extension for Azure CLI. You only need to install this the first time. You need it to create the device identity.
extension_check=$(az extension list | grep azure-cli-iot-ext)
if [ -z "$extension_check" ]; then
    az extension add --name azure-cli-iot-ext
fi

## Set names for azure resources
export LOCATION="westeurope" # for location in france, iot hub is not available
export IOT_RESOURCE_GROUP="connected_bar_resources"
export IOT_HUB_CONSUMER_GROUP="connected_bar_hub_consumers"
export IOT_HUB_NAME="connected_bar_hub_$RANDOM"
export IOT_COSMOS_NAME="connected_bar_cosmos"
export IOT_COSMOS_DB_NAME="connected_bar_cosmosdb"
export IOT_COSMOS_COLLECtiON_NAME="connected_bar_collection"
export IOT_STORAGE_NAME="storage_for_connected_bar"
export IOT_FUNCTIONAPP_NAME="connected_bar_function_app"
export IOT_EDGE_DEVICE_NAME="myEdgeDevice"
export PROJECT_REPOSITORY_URL="https://github.com/ysennoun/iot-platform-within-azure.git"
export IOT_CONTAINER_REGISTRY="IotEdgeRegistery"

## Create the resource group to be used by all the resources
az group create --name $IOT_RESOURCE_GROUP --location $LOCATION

## Create the IoT hub. The IoT hub name must be globally unique, so add a random number to the end.
az iot hub create --name IOT_HUB_NAME --resource-group $IOT_RESOURCE_GROUP --sku F1 --location $LOCATION
IOT_HUB_CONNECTION_STRING=$(az iot hub show-connection-string --hub-name $iotHubName --output tsv)

########################### IoT hub ############################
echo "########################### IoT hub ############################"
### Add a consumer group to the IoT hub.
az iot hub consumer-group create --hub-name $IOT_HUB_NAME --name IOT_HUB_CONSUMER_GROUP

## Create an IoT device and an IoT edge device. Then, we retrieve connection strings
az iot hub device-identity create --hub-name $IOT_HUB_NAME --device-id $IOT_EDGE_DEVICE_NAME --edge-enabled
EDGE_CONNECTION_STRING=$(az iot hub device-identity show-connection-string --device-id $IOT_EDGE_DEVICE_NAME --hub-name $IOT_HUB_NAME --output tsv)

########################### CosmosDB ############################
echo "########################### CosmosDB ############################"
## Create a DocumentDB API Cosmos DB account
az cosmosdb create \
    --name $IOT_COSMOS_NAME \
    --kind GlobalDocumentDB \
    --resource-group $IOT_RESOURCE_GROUP \
    --max-interval 10 \
    --max-staleness-prefix 200

## Create a database
az cosmosdb database create \
    --name $IOT_COSMOS_NAME \
    --db-name $IOT_COSMOS_DB_NAME \
    --resource-group $IOT_RESOURCE_GROUP

## Create a collection
az cosmosdb collection create \
    --collection-name $IOT_COSMOS_COLLECtiON_NAME \
    --name $IOT_COSMOS_NAME \
    --db-name $IOT_COSMOS_DB_NAME \
    --resource-group $IOT_RESOURCE_GROUP

## Get the Azure Cosmos DB connection string.
IOT_COSMOSDB_ENDPOINT=$(az cosmosdb show \
    --name $IOT_COSMOS_NAME \
    --resource-group $IOT_RESOURCE_GROUP \
    --query documentEndpoint \
    --output tsv)
IOT_COSMOSDB_PRIMARY_KEY=$(az cosmosdb list-keys \
    --name $IOT_COSMOS_NAME \
    --resource-group $IOT_RESOURCE_GROUP \
    --query primaryMasterKey \
    --output tsv)

########################### Function App ############################
echo "########################### Function App ############################"
### Create a serverless function app
az storage account create \
  --name $IOT_STORAGE_NAME \
  --location $LOCATION \
  --resource-group $IOT_RESOURCE_GROUP \
  --sku Standard_LRS

az functionapp create \
  --deployment-source-url $PROJECT_REPOSITORY_URL \
  --name $IOT_FUNCTIONAPP_NAME \
  --resource-group $IOT_RESOURCE_GROUP \
  --storage-account $IOT_STORAGE_NAME \
  --consumption-plan-location $LOCATION

## Configure function app settings to use the Azure Cosmos DB connection string.
az functionapp config appsettings set \
    --name $IOT_FUNCTIONAPP_NAME \
    --resource-group $IOT_RESOURCE_GROUP \
    --setting CosmosDB_Endpoint=$IOT_COSMOSDB_ENDPOINT  \
       CosmosDB_Key=$IOT_COSMOSDB_PRIMARY_KEY \
       CosmosDB_Name=$IOT_COSMOS_DB_NAME \
       CosmosDB_Collection_Name=$IOT_COSMOS_COLLECtiON_NAME \
       IotHub_Key=$IOT_HUB_CONNECTION_STRING \

########################### Container Registry ############################
echo "########################### Container Registry ############################"
az acr create --resource-group $IOT_RESOURCE_GROUP --name $IOT_CONTAINER_REGISTRY --sku Basic
CONTAINER_REGISTRY_ADDRESS=$(az acr show --name $IOT_CONTAINER_REGISTRY --query loginServer)
CONTAINER_REGISTRY_PASSWORD=$(az acr credential show --name $IOT_CONTAINER_REGISTRY --query "passwords[0].value")

########################### Api management ############################
echo "########################### Api management ############################"
az group deployment create \
 --resource-group $IOT_RESOURCE_GROUP \
 --template-file api-management-creation-deployment.json

########################### Output ############################
echo "########################### Output ############################"
fileName="output.txt"
rm -f ${fileName}
echo "IOT_HUB_CONNECTION_STRING="$IOT_HUB_CONNECTION_STRING >> ${fileName}
echo "EDGE_CONNECTION_STRING="$EDGE_CONNECTION_STRING >> ${fileName}
echo "CONTAINER_REGISTRY_ADDRESS="$CONTAINER_REGISTRY_ADDRESS >> ${fileName}
echo "CONTAINER_REGISTRY_NAME="$IOT_CONTAINER_REGISTRY >> ${fileName}
echo "CONTAINER_REGISTRY_PASSWORD="$CONTAINER_REGISTRY_PASSWORD >> ${fileName}
