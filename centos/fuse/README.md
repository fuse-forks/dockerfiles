# Docker images to setup a Red Hat JBoss Fuse test environment.

## BUG ALERT

- **6.1** When using JBoss Fuse 6.1 you might incur in an error while creating a fabric. This is because of a race condition bug in JBoss Fuse that has been fixed with Patch 02. So to have it all working, my suggestion is to download JBoss Fuse 6.1 Patch 02 from Red Hat Customer Portal, upload it in your built docker container (or build a docker image that automatically includes it) and than apply the patch as first operation, before starting a new fabric with commands similar to this:
```
patch:add file:///home/fuse/jboss-fuse-6.1.0.redhat-379-p2.zip
patch:install jboss-fuse-6.1.0.redhat-379-p2 
# interactive Karaf Shell will restart. Be patient.
```


- nsenter and a reason why you wouldn't want to use sshd in your docker containers. (but I still like to use it...) http://blog.docker.com/2014/06/why-you-dont-need-to-run-sshd-in-docker/

- <strike>be aware of this, in particular with the examples:
https://github.com/dotcloud/docker/issues/6390</strike>

- <strike>Recent evolution of Docker and SElinux support have introduce a possible bug while building the image. See: https://bugzilla.redhat.com/show_bug.cgi?id=1098120 </strike>

- <strike>The base centos docker image has evolved as well, removing some basic package that were available in past. This means that some build step could fail. This is easily fixed adding the missing packages at the yum installation steps. I am going to test and fix this problems as soon as I have time to test it.</strike>

## NOTE:
If you clone this repo This step require you to download JBoss Fuse distribution from 

http://www.jboss.org/products/fuse

This image supports different versions of JBoss Fuse distribution, you may use it to test also beta versions of the product. The build process will extract in the Docker image all the zip files it will find in your working folder. If it finds more than a file it will put all of them inside the  Docker it's going to be created. Most of the time you will want to have just a single zip file. 

## To build your Fuse image:
    # download docker file
	wget https://raw.github.com/paoloantinori/dockerfiles/master/centos/fuse/fuse/Dockerfile
    
    # check if base image has been updated
	docker pull pantinor/fuse
	
    # build your docker fuse image. you are expected to have either a copy of jboss-fuse-*.zip or a link to that file in the current folder.
    docker build -rm -t fuse .

## Multiple images with different Fuse versions
    # same steps than above. just, copy the different JBoss Fuse distribution in the working folder and build the image assigning a different name
    # assuming jboss-fuse-minimal-6.1.0.redhat-328.zip in the working folder
    docker build -rm -t fuse6.1 .


## To run your Fuse image
    docker run -t -i fuse
    # or 
    docker run -t -i fuse6.1

## To expose ports on localhost. Useful if you run docker in a VM like if you are on MacOSX or on Windows
    docker run -t -i -P fuse
    # and then to discover them 
    docker ps

## To run the examples
    sh name_of_script.sh

    # if you need to automatically expose ports on localhost (handy if you run docker daemon in a vm, like if you are using MacOSX or Windows)
    EXPOSE_PORTS=true sh name_of_script.sh
    
    # to discover the exposed ports
    docker ps

##### Note - ulimits

For a proper working behavior the user running the docker command should have `ulimits` values higher than those  set in the docker image.  
For this reason we assign them explicitly for the shell session.  
Not needed if the numbers you get from `ulimit -a` are already larger than `4096`.  
In case of bad behavior check what you have in `/etc/security/limits.conf`.  

    # set ulimits in your shell
    ulimit -u 4096
    ulimit -n 4096
    # if you receive an "operation not permitted error" invoke these 2 commands to give yourself higher limits
    sudo echo "$(whoami) - nproc 4096" >> /etc/security/limits.conf
    sudo echo "$(whoami) - nofile 4096" >> /etc/security/limits.conf


### Within the image you can
- start sshd server:
```service sshd start```
- start JBoss Fuse (example that uses the application user "fuse")
```sudo -u fuse /opt/rh/jboss-fuse-*/bin/fuse```
- install whatever you want with `yum install` since you have root access
    
#### Your first exercise:

> Note: most of the fabric commands use "localip" as resolver strategy since different Docker containers are not aware of their siebling DNS names.

- start a Docker fuse container.
```
docker run -t -i --name=fabric fuse
```

- start fuse as the "fuse" user
```
sudo -u fuse /opt/rh/jboss-fuse-*/bin/fuse
```

- create a new fabric with this command:
```
fabric:create -v --clean -g localip -r localip
```

- in another shell start a new docker fuse container
```
docker run -t -i --name=node fuse
```

- in another shell discover your docker node container ip:
```
docker inspect -format '{{ .NetworkSettings.IPAddress }}' node
```

- in your fabric container (first one) provision a couple of instances to that ip
```
container-create-ssh --resolver localip --user fuse --password fuse --path /opt/rh/fabric --host 172.17.0.3 zk 2
```

- in your fabric container control that the instances have been created:
```
container-list
```

- in your fabric container, tell the provisioned instances to join zookeeper ensemble
```
ensemble-add zk1 zk2
```

- verify your ensemble
```
ensemble-list
```

## suggestions
You  may find this alias useful to avoid ssh warnins when it notices you are connecting to the same ip address that has a fingreprint differente than the last time
```
alias sshi="ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o PreferredAuthentications=password"
```

##### Other examples:

https://github.com/paoloantinori/dockerfiles/tree/master/centos/fuse/examples


##### To build base image

This step is needed only if you don't want to download the base image from Docker public registry:
```
    docker build -t pantinor/fuse https://raw.github.com/paoloantinori/dockerfiles/master/centos/fuse/base/Dockerfile

    # or clone the repo and 
    # cd base/
    # docker build -rm -t pantinor/fuse .

```
