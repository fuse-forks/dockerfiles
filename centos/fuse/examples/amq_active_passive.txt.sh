#!/bin/bash

##########################################################################################################
# Description:
# This example will guide you to provision a Fabric node + 2 ActiveMQ managed nodes
# 
# See http://tmielke.blogspot.co.uk/2013/08/creating-activemq-broker-cluster.html
#
# Dependencies:
# - docker 
# - sshpass, used to avoid typing the pass everytime (not needed if you are invoking the commands manually)
# to install on Fedora/Centos/Rhel: 
# sudo yum install -y docker-io sshpass
#
# to install on MacOSX:
# sudo port install sshpass
# or
# brew install https://raw.github.com/eugeneoden/homebrew/eca9de1/Library/Formula/sshpass.rb
#
# Prerequesites:
# - run docker in case it's not already
# sudo service docker start
#
# Notes:
# - if you don't want to use docker, just assign to the ip addresses of your own boxes to environment variable
#######################################################################################################


################################################################################################
#####             Preconfiguration and helper functions. Skip if not interested.           #####
################################################################################################

# set debug mode
set -x

# configure logging to print line numbers
export PS4='+(${BASH_SOURCE}:${LINENO}): ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'


# ulimits values needed by the processes inside the container
ulimit -u 4096
ulimit -n 4096

########## docker lab configuration


# remove old docker containers with the same names
docker stop -t 0 root  
docker stop -t 0 brok01 
docker stop -t 0 brok02 
docker rm root 
docker rm brok01 
docker rm brok02 

# create shared folder used by the 2 instances of the broker to share same data
rm -rf ./demo_shared_data ; mkdir -p ./demo_shared_data ; chmod o+rwx ./demo_shared_data

# expose ports to localhost, uncomment to enable always
# EXPOSE_PORTS="-P"
if [[ x$EXPOSE_PORTS == xtrue ]] ; then EXPOSE_PORTS=-P ; fi

# halt on errors
set -e

# create your lab
docker run -d -t -i $EXPOSE_PORTS --name root fuse
docker run -d -t -i $EXPOSE_PORTS --name brok01 -v ./demo_shared_data:/opt/rh/data fuse
docker run -d -t -i $EXPOSE_PORTS --name brok02 -v ./demo_shared_data:/opt/rh/data fuse

# assign ip addresses to env variable, despite they should be constant on the same machine across sessions
IP_ROOT=$(docker inspect -format '{{ .NetworkSettings.IPAddress }}' root)
IP_BROK01=$(docker inspect -format '{{ .NetworkSettings.IPAddress }}' brok01)
IP_BROK02=$(docker inspect -format '{{ .NetworkSettings.IPAddress }}' brok02)

########### aliases to preconfigure ssh and scp verbose to type options

# full path of your ssh, used by the following helper aliases
SSH_PATH=$(which ssh) 
### ssh aliases to remove some of the visual clutter in the rest of the script
# alias to connect to your docker images
alias ssh="$SSH_PATH -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR"
alias ssh2host="$SSH_PATH -o UserKnownHostsFile=/dev/null -o ConnectionAttempts=180 -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR fuse@$IP_ROOT"
# alias to connect to the ssh server exposed by JBoss Fuse. uses sshpass to script the password authentication
alias ssh2fabric="sshpass -p admin $SSH_PATH -p 8101 -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR admin@$IP_ROOT"
# alias to connect to the ssh server exposed by JBoss Fuse. uses sshpass to script the password authentication
alias ssh2brok01="sshpass -p admin $SSH_PATH -p 8101 -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR admin@$IP_BROK01"
alias ssh2brok02="sshpass -p admin $SSH_PATH -p 8101 -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR admin@$IP_BROK02"
# alias for scp to inline flags to disable ssh warnings
alias scp="scp -o ConnectionAttempts=180 -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password -o LogLevel=ERROR"


################################################################################################
#####                             Tutorial starts here                                     #####
################################################################################################


# create shared data folder inside docker container and assign permissions
ssh fuse@$IP_BROK01 "mkdir -p /opt/rh/data ; sudo chown fuse:fuse /opt/rh/data" 
ssh fuse@$IP_BROK02 "mkdir -p /opt/rh/data ; sudo chown fuse:fuse /opt/rh/data" 

# upload amq configuration to docker container
scp resources/amq-configuration.xml fuse@$IP_ROOT:/home/fuse/

# start fuse on root node (yes, that initial backslash is required to not use the declared alias)
ssh2host "/opt/rh/jboss-fuse-*/bin/start"


############################# here you are starting to interact with Fuse/Karaf

# wait for critical components to be available before progressing with other steps
ssh2fabric "wait-for-service -t 300000 org.linkedin.zookeeper.client.LifecycleListener"
ssh2fabric "wait-for-service -t 300000 org.fusesource.fabric.maven.MavenProxy"


# create a new fabric AND wait for the Fabric to be up and ready to accept the following commands
ssh2fabric "fabric:create --clean -r localip -g localip ; wait-for-service -t 300000 org.jolokia.osgi.servlet.JolokiaContext" 

# stop default broker created automatically with fabric
ssh2fabric "stop org.jboss.amq.mq-fabric" 

# import broker xml configuration in zookeeper registry
ssh2fabric  "import -v -t /fabric/configs/versions/1.0/profiles/mq-base/amq-configuration.xml /home/fuse/amq-configuration.xml"


# create broker profile and add location of shared message store
ssh2fabric "fabric:mq-create my_broker_profile"

# assign values for the placeholders in amq-configuration.xml (externalized since you may want different values in dev and in prod )
ssh2fabric "fabric:profile-edit --pid org.fusesource.mq.fabric.server-my_broker_profile/data=/opt/rh/data           my_broker_profile"
ssh2fabric "fabric:profile-edit --pid org.fusesource.mq.fabric.server-my_broker_profile/openwire-port=61616         my_broker_profile"
ssh2fabric "fabric:profile-edit --pid org.fusesource.mq.fabric.server-my_broker_profile/broker-name=my_broker       my_broker_profile"
ssh2fabric "fabric:profile-edit --pid org.fusesource.mq.fabric.server-my_broker_profile/group=my_group              my_broker_profile"
ssh2fabric "fabric:profile-edit --pid org.fusesource.mq.fabric.server-my_broker_profile/config=zk:/fabric/configs/versions/1.0/profiles/mq-base/amq-configuration.xml my_broker_profile"


# remove hawtio and install newer version
ssh2fabric "fabric:profile-edit --delete -r mvn:io.hawt/hawtio-karaf/1.0/xml/features my_broker_profile"
ssh2fabric "fabric:profile-edit -r mvn:io.hawt/hawtio-karaf/1.2.3/xml/features my_broker_profile"
ssh2fabric "fabric:profile-edit --features hawtio my_broker_profile"


# provision container nodes
ssh2fabric "container-create-ssh --resolver localip --host $IP_BROK01 --user fuse  --path /opt/rh/fabric --profile my_broker_profile brok01"
ssh2fabric "container-create-ssh --resolver localip --host $IP_BROK02 --user fuse  --path /opt/rh/fabric --profile my_broker_profile brok02"

# show current containers
ssh2fabric "cluster-list"

set +x
echo "
----------------------------------------------------
ActiveMQ Active/Passive Demo with shared data folder
----------------------------------------------------
FABRIC ROOT: 
- ip:          $IP_ROOT
- ssh:         ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fuse@$IP_ROOT
- karaf:       ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP_ROOT -p8101
- tail logs:   ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fuse@$IP_ROOT 'tail -F /opt/rh/jboss-fuse-*/data/log/fuse.log'

BROKER 1: 
- ip:         $IP_BROK01
- ssh:        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fuse@$IP_BROK01
- karaf:      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP_BROK01 -p8101
- hawtio:     http://$IP_BROK01:8013/hawtio 
              user/pass: admin/admin
- tail logs:  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $IP_BROK01 -l fuse 'tail -F /opt/rh/fabric/brok01/fuse-fabric-*/data/log/karaf.log'

BROKER 2: 
- ip:         $IP_BROK02
- ssh:        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null fuse@$IP_BROK02
- karaf:      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null admin@$IP_BROK02 -p8101
- hawtio:     http://$IP_BROK02:8013/hawtio
              user/pass: admin/admin
- tail logs:  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $IP_BROK02 -l fuse 'tail -F /opt/rh/fabric/brok02/fuse-fabric-*/data/log/karaf.log'

NOTE: If you are using Docker in a VM you may need extra config to route the traffic to the containers. One way to bypass this can be setting the environment variable EXPOSE_PORTS=true before running this script and than to use 'docker ps' to discover the exposed ports on your localhost.
----------------------------------------------------
Use command:

cluster-list

in Karaf on Fabric Root, to see the status of your Active/Passive ActiveMQ Cluster.

Note that in Hawtio, only the active node will have ActiveMQ tab enabled

See http://tmielke.blogspot.co.uk/2013/08/creating-activemq-broker-cluster.html

"

