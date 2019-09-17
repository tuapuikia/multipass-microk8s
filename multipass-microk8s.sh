#!/usr/bin/env bash

# Configure your settings
# Name for the cluster/configuration files
NAME=$1
# Ubuntu image to use (xenial/bionic)
IMAGE="bionic"
# How many machines to create
SERVER_COUNT_MACHINE="1"
# How many machines to create
AGENT_COUNT_MACHINE="1"
# How many CPUs to allocate to each machine
SERVER_CPU_MACHINE="2"
# How much disk space to allocate to each machine
SERVER_DISK_MACHINE="15G"
# How much memory to allocate to each machine
SERVER_MEMORY_MACHINE="4096M"

## Nothing to change after this line
if [ -x "$(command -v multipass.exe)" > /dev/null 2>&1 ]; then
    # Windows
    MULTIPASSCMD="multipass.exe"
elif [ -x "$(command -v multipass)" > /dev/null 2>&1 ]; then
    # Linux/MacOS
    MULTIPASSCMD="multipass"
else
    echo "The multipass binary (multipass or multipass.exe) is not available or not in your \$PATH"
    exit 1
fi

# Check if name is given or create random string
if [ -z $NAME ]; then
    NAME=$(cat /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | fold -w 6 | head -n 1 | tr '[:upper:]' '[:lower:]')
    echo "No name given, generated name: ${NAME}"
fi

echo "Creating microk8s ${NAME} with ${SERVER_COUNT_MACHINE} servers and ${AGENT_COUNT_MACHINE} agents"

# Prepare cloud-init
# Cloud init template
read -r -d '' SERVER_CLOUDINIT_TEMPLATE << EOM
#cloud-config

runcmd:
 - '\sudo snap install --classic microk8s && sudo snap alias microk8s.kubectl kubectl && sudo usermod -a -G microk8s ubuntu'
EOM

echo "$SERVER_CLOUDINIT_TEMPLATE" > "${NAME}-cloud-init.yaml"
echo "Cloud-init is created at ${NAME}-cloud-init.yaml"

for i in $(eval echo "{1..$SERVER_COUNT_MACHINE}"); do
    echo "Running $MULTIPASSCMD launch --cpus $SERVER_CPU_MACHINE --disk $SERVER_DISK_MACHINE --mem $SERVER_MEMORY_MACHINE $IMAGE --name microk8s-server-$NAME-$i --cloud-init ${NAME}-cloud-init.yaml"                                                                                                                                           
    $MULTIPASSCMD launch --cpus $SERVER_CPU_MACHINE --disk $SERVER_DISK_MACHINE --mem $SERVER_MEMORY_MACHINE $IMAGE --name microk8s-server-$NAME-$i --cloud-init "${NAME}-cloud-init.yaml"
    if [ $? -ne 0 ]; then
        echo "There was an error launching the instance"
        exit 1
    fi
done

# Enable RBAC
echo "Enable RBAC"
$MULTIPASSCMD exec microk8s-server-$NAME-$i -- bash -c "/snap/bin/microk8s.enable rbac"
sleep 30

# Enable CNI
#echo "Enable CNI cilium"
#$MULTIPASSCMD exec microk8s-server-$NAME-$i -- bash -c "/snap/bin/microk8s.enable cilium"
#sleep 30

# Enable DNS
echo "Enable DNS service"
$MULTIPASSCMD exec microk8s-server-$NAME-$i -- bash -c "/snap/bin/microk8s.enable dns"

# Enable Storage class
echo "Enable storage class"
sleep 30
$MULTIPASSCMD exec microk8s-server-$NAME-$i -- bash -c "/snap/bin/microk8s.enable storage"

# Copy kubeconfig from instance
$MULTIPASSCMD exec microk8s-server-$NAME-$i -- bash -c "/snap/bin/microk8s.config > /tmp/kubeconfig.yaml && sudo chmod 655 /tmp/kubeconfig.yaml"
$MULTIPASSCMD copy-files microk8s-server-$NAME-$i:/tmp/kubeconfig.yaml $NAME-kubeconfig.yaml
echo "microk8s setup finished"
$MULTIPASSCMD exec microk8s-server-$NAME-$i -- /snap/bin/microk8s.kubectl get nodes
echo "You can now use the following command to connect to your cluster"
echo "$MULTIPASSCMD exec microk8s-server-$NAME-$i -- /snap/bin/microk8s.kubectl get nodes"
echo "Or use kubectl directly"
echo "kubectl --kubeconfig ${NAME}-kubeconfig.yaml get nodes"


