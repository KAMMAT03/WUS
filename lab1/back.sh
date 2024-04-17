#!/bin/bash

DIRECTORY="$RANDOM"

echo $DIRECTORY
cd ~/
mkdir $DIRECTORY
cd $DIRECTORY

SERVER_PORT=$1
DATABASE_ADDRESS=$2
DATABASE_PORT=$3
DATABASE_USER=$4
DATABASE_PASSWORD=$5

CONFIG_FOLDER="/src/main/resources/"

sudo apt-get update
sudo apt-get upgrade -y
sudo apt-get install openjdk-17-jdk -y

sudo apt-get install openjdk-17-jdk -y


git clone https://github.com/spring-petclinic/spring-petclinic-rest.git

cd spring-petclinic-rest

sed -i "s/=hsqldb/=mysql/g" ./src/main/resources/application.properties 
sed -i "s/9966/$SERVER_PORT/g" ./src/main/resources/application.properties

sed -i "s/localhost/$DATABASE_ADDRESS/g" ./src/main/resources/application-mysql.properties
sed -i "s/3306/$DATABASE_PORT/g" ./src/main/resources/application-mysql.properties
sed -i "s/pc/$DATABASE_USER/g" ./src/main/resources/application-mysql.properties
sed -i "s/=petclinic/=$DATABASE_PASSWORD/g" ./src/main/resources/application-mysql.properties

# ./mvnw clean install
./mvnw spring-boot:run &
