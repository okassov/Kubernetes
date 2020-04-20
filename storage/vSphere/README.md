# Configuration vSphere Dynamic Storage Provisioning for Kubernetes

## 1) Prerequisites

### Kubernetes

- Kubernetes version v1.6.5+

### VMWare vSphere

- vSphere version 6.0.x
- vSAN, VMFS and NFS supported.

### Permissions

- vCenter user with required set of privileges.

### VMs

- All node must be placed in a vSphere VM folder + 

- Create a VM folder for kubernetes cluster vm's and move them to this folder

- The disk.EnableUUID parameter must be set to TRUE for each Node VM
  
- Download govc and install: 

```
wget https://github.com/vmware/govmomi/releases/download/v0.22.1/govc_linux_amd64.gz && gunzip -c govc_linux_amd64.gz > /usr/local/bin/govc && chmod +x /usr/local/bin/govc
```

Export GOVC envs for connect to VCSA

```
export GOVC_URL='vCenter IP OR FQDN'
export GOVC_USERNAME='vCenter User with admin permissions'
export GOVC_PASSWORD='vCenter Password'
export GOVC_INSECURE=1
```

Export additional vars and set enabled to disk UUID

```
export CLUSTER=VSPHERE_CLUSTER_NAME
export FOLDER=CREATED_FOLDER

for i in $(govc ls /$CLUSTER/vm/$FOLDER); do govc vm.change -e="disk.enableUUID=1" -vm=$i; done
```  

## 2) Configuration

### On each master nodes create vsphere.conf in the /etc/kubernetes/pki/vsphere.conf

```
[Global]
secret-name = "vsphere-creds"
secret-namespace = "kube-system"
port = "443"
insecure-flag = "1"

[VirtualCenter "172.16.0.178"]
datacenters = "TD"

[Workspace]
server = "172.16.0.178"
datacenter = "TD"
default-datastore = "DX200S4_LUN19"
resourcepool-path = "Kubernetes/stage-kube-cluster"
folder = "stage-kube"

[Disk]
scsicontrollertype = pvscsi
```

### Create base64 encode string for username and password and apply new secret
```
echo -n 'kube-pv@vsphere.local' | base64

echo -n 'dG$p8JgBP4#X' | base64

cat > vsphere-creds.yml <<EOF
apiVersion: v1
kind: Secret
metadata:
 name: vsphere-creds
 namespace: kube-system
type: Opaque
data:
   172.16.0.178.username: a3ViZS1wdkB2c3BoZXJlLmxvY2Fs
   172.16.0.178.password: ZEckcDhKZ0JQNCNY
EOF

kubectl apply -f vsphere-creds.yml
```

### Enable the vSphere Cloud Provider

On the Kubernetes Masters:

Add following flags to the kubelet service configuration /etc/systemd/system/kubelet.service.d/10-kubeadm.conf or env

```
--cloud-provider=vsphere
--cloud-config=/etc/kubernetes/pki/vsphere.conf
```

Add following extra args for /etc/kubernetes/manifests/kube-apiserver.yml and /etc/kubernetes/manifests/kube-controller-manager.yml

```
  - --cloud-provider=vsphere
  - --cloud-config=/etc/kubernetes/pki/vsphere.conf
```

On the Kubernetes workers:

Add following flags to the kubelet service configuration /etc/systemd/system/kubelet.service.d/10-kubeadm.conf or env

```
--cloud-provider=vsphere
```

### Update all node ProviderID fields

```
kubectl get nodes -o json | jq '.items[]|[.metadata.name, .spec.providerID, .status.nodeInfo.systemUUID]'
```

If the output is null, you will need to run the following script (vsphere-uuid-script.sh):

On a machine with govc jq, and kubectl installed, run the following script to set the ProviderID from vCenter to each node:

```
#!/bin/bash

export GOVC_USERNAME='kube-pv@vsphere.local'
export GOVC_INSECURE=1
export GOVC_PASSWORD='pass'
export GOVC_URL='172.16.0.178'
DATACENTER='TD'
FOLDER='stage-kube'
IFS=$'\n'
for vm in $(govc ls "/$DATACENTER/vm/$FOLDER"); do
  MACHINE_INFO=$(govc vm.info -json -dc=$DATACENTER -vm.ipath="/$vm" -e=true)
  # My VMs are created on vmware with upper case names, so I need to edit the names with awk
  VM_NAME=$(jq -r ' .VirtualMachines[] | .Name' <<< $MACHINE_INFO | awk '{print tolower($0)}')
  # UUIDs come in lowercase, upper case then
  VM_UUID=$( jq -r ' .VirtualMachines[] | .Config.Uuid' <<< $MACHINE_INFO | awk '{print toupper($0)}')
  echo "Patching $VM_NAME with UUID:$VM_UUID"
  # This is done using dry-run to avoid possible mistakes, remove when you are confident you got everything right.
  kubectl patch node $VM_NAME -p "{\"spec\":{\"providerID\":\"vsphere://$VM_UUID\"}}"
done
```

Check result

```
kubectl get nodes -o json | jq '.items[]|[.metadata.name, .spec.providerID, .status.nodeInfo.systemUUID]'
```

Restart services on Master and Worker nodes

```
systemctl daemon-reload
systemctl restart kubelet
```

Get kube-api pods ID and stop it

```
docker ps | grep POD | grep api 
docker stop <pod_id>
```

Get kube-controller pods ID and stop it

```
docker ps | grep POD | grep controller 
docker stop <pod_id>
```

## 3) Dynamic Provisioning Configuration

### Create StorageClass for our vSphere

```
cat > vsphere-storageclass.yml <<EOF
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: vsphere-storageclass
provisioner: kubernetes.io/vsphere-volume
parameters:
    diskformat: zeroedthick
    datastore: "DX200S4_LUN19"
EOF

kubectl apply -f vsphere-storageclass.yml
```

### Now check your provisioning 

```
cat > test-pv.yml <<EOF
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: pvc-test
  annotations:
    volume.beta.kubernetes.io/storage-class: vsphere-storageclass
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pod
spec:
  containers:
    - name: web-server
      image: nginx
      volumeMounts:
        - name: test-pv
          mountPath: /var/lib/www
  volumes:
    - name: test-pv
      persistentVolumeClaim:
        claimName: pvc-test
        readOnly: false
EOF

kubectl apply -f test-pv.yml
```