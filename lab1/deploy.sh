#!/bin/bash

if [ $# -lt 1 ]; then
  echo 1>&2 "$0: not enough arguments"
  echo "Usage: $0 CONFIG_FILE"
  exit 2
fi
az account show -o none
CONFIG_FILE="$1"

echo $CONFIG_FILE
# Instalation
# sudo apt-get update
# sudo apt-get upgrade -y

# sudo apt install jq -y
# sudo apt-get install azure-cli -y


RESOURCE_GROUP="$(jq -r '.resource_group' "$CONFIG_FILE")"

echo $RESOURCE_GROUP

echo "Creating Resource Group"
# Resource Group
az group create --name $RESOURCE_GROUP --location westeurope

# Network
NETWORK_ADDRESS_PREFIX="$(jq -r '.network.address_prefix' "$CONFIG_FILE")"

echo "Creating Virtual Network"
az network vnet create \
    --name VNet \
    --resource-group $RESOURCE_GROUP \
    --address-prefix $NETWORK_ADDRESS_PREFIX

# Network Security Group

readarray -t NETWORK_SECURITY_GROUPS < <(jq -c '.network_security_group[]' "$CONFIG_FILE")

echo "Creating Groups"

for GROUP in "${NETWORK_SECURITY_GROUPS[@]}"; do
    # echo $GROUP

    GROUP_NAME="$(jq -r '.name' <<< $GROUP)"
    
    echo "  Creating $GROUP_NAME"
    
    az network nsg create \
        --resource-group $RESOURCE_GROUP \
        --name $GROUP_NAME

    readarray -t RULES < <(jq -c '.rule[]' <<< $GROUP)

    for RULE in "${RULES[@]}"; do
        # echo $RULE

        RULE_NAME=$(jq -r '.name' <<< $RULE)
        RULE_PRIORITY=$(jq -r '.priority' <<< $RULE)
        RULE_SOURCE_ADDRESS_PREFIX=$(jq -r '.source_address_prefixes' <<< $RULE)
        RULE_SOURCE_PORT_RANGES=$(jq -r '.source_port_ranges' <<< $RULE)
        RULE_DESTINATION_ADDRESS_PREFIX=$(jq -r '.destination_address_prefixes' <<< $RULE)
        RULE_DESTINATION_PORT_RANGES=$(jq -r '.destination_port_ranges' <<< $RULE)
    
        echo "      Creating $RULE_NAME"

        az network nsg rule create \
            --resource-group $RESOURCE_GROUP \
            --nsg-name $GROUP_NAME \
            --name $RULE_NAME \
            --access Allow \
            --protocol Tcp \
            --priority $RULE_PRIORITY \
            --source-address-prefix "$RULE_SOURCE_ADDRESS_PREFIX" \
            --source-port-range "$RULE_SOURCE_PORT_RANGES" \
            --destination-address-prefix "$RULE_DESTINATION_ADDRESS_PREFIX" \
            --destination-port-range "$RULE_DESTINATION_PORT_RANGES"
    done
done

# Subnet

readarray -t SUBNETS < <(jq -c '.subnet[]' "$CONFIG_FILE")

echo "Creating Network Subnets"

for SUBNET in "${SUBNETS[@]}"; do
    # echo $SUBNET

    SUBNET_NAME=$(jq -r '.name' <<< $SUBNET)
    SUBNET_ADDRESS_PREFIX=$(jq -r '.address_prefix' <<< $SUBNET)
    SUBNET_NETWORK_SECURITY_GROUP=$(jq -r '.network_security_group' <<< $SUBNET)
    echo "  $SUBNET_NAME"

    az network vnet subnet create \
        --resource-group $RESOURCE_GROUP \
        --vnet-name VNet \
        --name $SUBNET_NAME \
        --address-prefix $SUBNET_ADDRESS_PREFIX \
        --network-security-group "$SUBNET_NETWORK_SECURITY_GROUP"
done

# Public IP

readarray -t PUBLIC_IPS < <(jq -c '.public_ip[]' "$CONFIG_FILE")
echo "Creating Public IPs"
for PUBLIC_IP in "${PUBLIC_IPS[@]}"; do

    PUBLIC_IP_NAME=$(jq -r '.name' <<< $PUBLIC_IP)
    echo "  $PUBLIC_IP_NAME"

    az network public-ip create \
        --resource-group $RESOURCE_GROUP \
        --name $PUBLIC_IP_NAME
done

# Virtual Machine

readarray -t VIRTUAL_MACHINES < <(jq -c '.virtual_machine[]' "$CONFIG_FILE")
echo "Creating Virtual Machines"
for VM in "${VIRTUAL_MACHINES[@]}"; do
    # echo $VM

    VM_NAME=$(jq -r '.name' <<< $VM)
    VM_SUBNET=$(jq -r '.subnet' <<< $VM)
    VM_PRIVATE_IP_ADDRESS=$(jq -r '.private_ip_address' <<< $VM)
    VM_PUBLIC_IP_ADDRESS=$(jq -r '.public_ip_address' <<< $VM)
    echo "  $VM_NAME"
    az vm create \
        --resource-group $RESOURCE_GROUP \
        --vnet-name VNet \
        --name $VM_NAME \
        --subnet $VM_SUBNET \
        --nsg "" \
        --private-ip-address "$VM_PRIVATE_IP_ADDRESS" \
        --public-ip-address "$VM_PUBLIC_IP_ADDRESS" \
        --image Ubuntu2204 \
        --generate-ssh-keys
        
        # --data-disk-sizes-gb 10 \
        # --size Standard_DS2_v2 \
    
    readarray -t DEPLOY < <(jq -c '.deploy[]' <<< $VM)

    for SERVICE in "${DEPLOY[@]}"; do
        echo $SERVICE

        SERVICE_TYPE=$(jq -r '.type' <<< $SERVICE)
        SERVICE_PORT=$(jq -r '.port' <<< $SERVICE)

        case $SERVICE_TYPE in
            frontend)
                echo Setting up frontend

                # SERVER_IP=$(jq -r '.backend_address' <<< $SERVICE)
                SERVER_ADDRESS=$(jq -r '.backend_address' <<< $SERVICE)
                SERVER_IP=$(az network public-ip show --resource-group "$RESOURCE_GROUP"  --name "$SERVER_ADDRESS"  --query "ipAddress" --output tsv)
                SERVER_PORT=$(jq -r '.backend_port' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts "@./frontend.sh" \
                    --parameters "$SERVER_IP" "$SERVER_PORT" "$SERVICE_PORT"
            ;;

            nginx)
                echo Setting up nginx

                SERVER_ADDRESS=$(jq -r '.backend_address' <<< $SERVICE)
                SERVER_PORT1=$(jq -r '.backend_port1' <<< $SERVICE)
                SERVER_PORT2=$(jq -r '.backend_port2' <<< $SERVICE)
                SERVER_PORT3=$(jq -r '.backend_port3' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts '@./nginx.sh' \
                    --parameters "$SERVICE_PORT"  "$SERVER_ADDRESS" "$SERVER_PORT1"  "$SERVER_PORT2" "$SERVER_PORT3"
            ;;

            nginx-get)
                echo Setting up nginx-get

                SERVER_ADDRESS=$(jq -r '.server_address' <<< $SERVICE)
                GET_PORT=$(jq -r '.get_port' <<< $SERVICE)
                DEFAULT_PORT=$(jq -r '.default_port' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts '@./nginx-get.sh' \
                    --parameters "$SERVICE_PORT"  "$SERVER_ADDRESS" "$GET_PORT"  "$DEFAULT_PORT"
            ;;


            backend)
                echo Setting up backend

                DATABASE_ADDRESS=$(jq -r '.database_ip' <<< $SERVICE)
                DATABASE_PORT=$(jq -r '.database_port' <<< $SERVICE)
                DATABASE_USER=$(jq -r '.database_user' <<< $SERVICE)
                DATABASE_PASSWORD=$(jq -r '.database_password' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts "@./back.sh" \
                    --parameters "$SERVICE_PORT" "$DATABASE_ADDRESS" "$DATABASE_PORT" "$DATABASE_USER" "$DATABASE_PASSWORD"
            ;;

            database)
                echo Setting up database

                DATABASE_USER=$(jq -r '.user' <<< $SERVICE)
                DATABASE_PASSWORD=$(jq -r '.password' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts "@./db.sh" \
                    --parameters "$SERVICE_PORT" "$DATABASE_USER" "$DATABASE_PASSWORD"
            ;;

            database-slave)
                echo Setting up database slave

                DATABASE_USER=$(jq -r '.user' <<< $SERVICE)
                DATABASE_PASSWORD=$(jq -r '.password' <<< $SERVICE)
                MASTER_DATABASE_ADDRESS=$(jq -r '.master_address' <<< $SERVICE)
                MASTER_DATABASE_PORT=$(jq -r '.master_port' <<< $SERVICE)

                az vm run-command invoke \
                    --resource-group $RESOURCE_GROUP \
                    --name $VM_NAME \
                    --command-id RunShellScript \
                    --scripts "@./db-slave.sh" \
                    --parameters "$SERVICE_PORT" "$DATABASE_USER" "$DATABASE_PASSWORD" "$MASTER_DATABASE_ADDRESS" "$MASTER_DATABASE_PORT"
            ;;

            *)
                echo 1>&2 "Unknown service type!"
                exit 1
            ;;
        esac
    done
done

for PUBLIC_IP in "${PUBLIC_IPS[@]}"; do
    echo $PUBLIC_IP

    PUBLIC_IP_NAME=$(jq -r '.name' <<< $PUBLIC_IP)

    az network public-ip show \
      --resource-group "$RESOURCE_GROUP" \
      --name "$PUBLIC_IP_NAME" \
      --query "ipAddress" \
      --output tsv
done



