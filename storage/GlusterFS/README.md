# GlusterFS Dynamic Provisioning using Heketi as External Storage

We needed a highly available shared storage platform, so we turned to GlusterFS and Heketi — RESTful based volume management framework for GlusterFS. 
Heketi provides a convenient way to unleash the power of dynamically provisioned GlusterFS volumes. It is kind of glue between Glusterfs and Kubernetes. 
Without this access, you would have to manually create GlusterFS volumes and map them to k8s persistent volume.

## 1) Install GlusterFS Cluster

### Prerequisits:

1. 3 Virtual Machines with CentOS7
  - vm-gluster-01 (172.31.22.111)
  - vm-gluster-02 (172.31.22.112)
  - vm-gluster-03 (172.31.22.113)
2. Each VM must have an additional clear disk without partioning and filesystem (In my case is /dev/sdb)

### Configuration CentOS

Add the following line to the /etc/hosts on each VM

```
172.31.22.111  vm-gluster-01.example.com vm-gluster-01
172.31.22.112  vm-gluster-02.example.com vm-gluster-02
172.31.22.113  vm-gluster-03.example.com vm-gluster-03
```

### Install GlusterFS Server Packages On All Servers.

Run the following commands one after the another on all 3 servers:

```
yum install wget
yum install centos-release-gluster -y
yum install epel-release -y
yum install glusterfs-server -y
```

Start the GlusterFS Service:

```
systemctl start glusterd
systemctl enable glusterd
```

Allow the ports in the firewall so that servers can communicate and from glusterfs storage cluster (trusted pool).

```
firewall-cmd --add-port=24007-24008/tcp --permanent
firewall-cmd --add-port=24009/tcp --permanent
firewall-cmd --add-service=nfs --add-service=samba --add-service=samba-client --permanent
firewall-cmd --add-port=111/tcp --add-port=139/tcp --add-port=445/tcp --add-port=965/tcp --add-port=2049/tcp --add-port=38465-38469/tcp --add-port=631/tcp --add-port=111/udp --add-port=963/udp --add-port=49152-49251/tcp --permanent
firewall-cmd --reload
```

Change CentOS default configuration:

```
root@vm-gluster-01:# vi /etc/ssh/sshd_config
PermitRootLogin yes

root@vm-gluster-01:# vi /etc/selinux/config
SELINUX=disabled

root@vm-gluster-01:# setenforce 0
```

### Distribute Volume Setup

Create a trusted storage pool. On vm-gluster-01 use the following commands:

```
root@vm-gluster-01:# gluster peer probe vm-gluster-02.example.com
peer probe: success.

root@vm-gluster-01:# gluster peer probe vm-gluster-03.example.com
peer probe: success.
```

We can check the peer status using below command :

```
root@vm-gluster-01:#gluster peer status

Number of Peers: 2

Hostname: vm-gluster-02.example.com
State: Peer in Cluster (Connected)

Hostname: vm-gluster-03.example.com
State: Peer in Cluster (Connected)
```

## 2) Heketi Setup

Install Heketi on one of the Gluster VM (In my case on vm-gluster-01)
```
root@vm-gluster-01:# wget https://github.com/heketi/heketi/releases/download/v9.0.0/heketi-v9.0.0.linux.amd64.tar.gz
root@vm-gluster-01:# tar xzvf heketi-v9.0.0.linux.amd64.tar.gz
root@vm-gluster-01:# cd heketi
root@vm-gluster-01:# cp heketi heketi-cli /usr/local/bin/
root@vm-gluster-01:# heketi -v
```

Create the heketi user and the directory structures for the configuration:

```
root@vm-gluster-01:# groupadd -r -g 515 heketi
root@vm-gluster-01:# useradd -r -c "Heketi user" -d /var/lib/heketi -s /bin/false -m -u 515 -g heketi heketi
root@vm-gluster-01:# mkdir -p /var/lib/heketi && chown -R heketi:heketi /var/lib/heketi
root@vm-gluster-01:# mkdir -p /var/log/heketi && chown -R heketi:heketi /var/log/heketi
root@vm-gluster-01:# mkdir -p /etc/heketi
```
Heketi has several provisioners but here I will be using the ssh We need to set up password-less ssh login between the Gluster nodes so heketi can access them. Generate RSA key pair.

```
root@vm-gluster-01:# ssh-keygen -f /etc/heketi/heketi_key -t rsa -N ''
root@vm-gluster-01:# chown heketi:heketi /etc/heketi/heketi_key*
```

Change Permission for ssh key files in all 3 nodes for heketi access :

```
root@vm-gluster-01:# cd /root
root@vm-gluster-01:# mkdir .ssh
root@vm-gluster-01:# cd .ssh/
root@vm-gluster-01:# vi authorized_keys
paste public key file in this file

root@vm-gluster-01:# chmod 600 /root/.ssh/authorized_keys
root@vm-gluster-01:# chmod 700 /root/.ssh
root@vm-gluster-01:# service sshd restart
```

Create the Heketi config file in/etc/heketi/heketi.json

```
{
  "_port_comment": "Heketi Server Port Number",
  "port": "8080",
  "_use_auth": "Enable JWT authorization. Please enable for deployment",
  "use_auth": true,
  "_jwt": "Private keys for access",
  "jwt": 
  {
    "_admin": "Admin has access to all APIs",
    "admin": {
      "key": "your_admin_secret"
    },
    "_user": "User only has access to /volumes endpoint",
    "user": {
      "key": "PASSWORD"
    }
  },
 
  "_glusterfs_comment": "GlusterFS Configuration",
  "glusterfs": 
   {
    "_executor_comment": 
    [
      "Execute plugin. Possible choices: mock, ssh",
      "mock: This setting is used for testing and development.",
      "      It will not send commands to any node.",
      "ssh:  This setting will notify Heketi to ssh to the nodes.",
      "      It will need the values in sshexec to be configured.",
      "kubernetes: Communicate with GlusterFS containers over",
      "            Kubernetes exec api."
    ],
    
    "executor": "ssh",
    "_sshexec_comment": "SSH username and private key file information",
    "sshexec": 
    {
      "keyfile": "/etc/heketi/heketi_key",
      "user": "root",
      "port": "22",
      "fstab": "/etc/fstab"
    },
 
    "_kubeexec_comment": "Kubernetes configuration",
    "kubeexec": 
    {
      "host" :"https://kubernetes.host:8443",
      "cert" : "/path/to/crt.file",
      "insecure": false,
      "user": "kubernetes username",
      "password": "password for kubernetes user",
      "namespace": "OpenShift project or Kubernetes namespace",
      "fstab": "Optional: Specify fstab file on node.  Default is /etc/fstab"
    },
 
    "_db_comment": "Database file name",
    "db": "/var/lib/heketi/heketi.db",
    "brick_max_size_gb" : 1024,
    "brick_min_size_gb" : 1,
    "max_bricks_per_volume" : 33,
 
    "_loglevel_comment": 
    [
      "Set log level. Choices are:",
      "  none, critical, error, warning, info, debug",
      "Default is warning"
    ],
    
    "loglevel" : "debug"
  }
}
```

Create the following Heketi service file /etc/systemd/system/heketi.service

```
[Unit]
Description=Heketi Server
Requires=network-online.target
After=network-online.target
 
[Service]
Type=simple
User=heketi
Group=heketi
PermissionsStartOnly=true
PIDFile=/run/heketi/heketi.pid
Restart=on-failure
RestartSec=10
WorkingDirectory=/var/lib/heketi
RuntimeDirectory=heketi
RuntimeDirectoryMode=0755
ExecStartPre=[ -f "/run/heketi/heketi.pid" ] && /bin/rm -f /run/heketi/heketi.pid
ExecStart=/usr/local/bin/heketi --config=/etc/heketi/heketi.json
ExecReload=/bin/kill -s HUP $MAINPID
KillSignal=SIGINT
TimeoutStopSec=5
 
[Install]
WantedBy=multi-user.target
```

Start the heketi service

```
root@vm-gluster-01:# systemctl daemon-reload
root@vm-gluster-01:# systemctl start heketi
root@vm-gluster-01:# systemctl enable heketi
```

Create topology /etc/heketi/topology.json config file:

```
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-01"
              ],
              "storage": [
                "172.31.22.111"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/sdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-02"
              ],
              "storage": [
                "172.31.22.112"
              ]
            },
            "zone": 2
          },
          "devices": [
            "/dev/sdb"
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-03"
              ],
              "storage": [
                "172.31.22.113"
              ]
            },
            "zone": 3
          },
          "devices": [
            "/dev/sdb"
          ]
        }
      ]
    }
  ]
}
```

Where /dev/sdb is a raw block device attached to each gluster node. Then we load topology:

```
root@vm-gluster-01:# export HEKETI_CLI_SERVER=http://vm-gluster-01:8080
root@vm-gluster-01:# export HEKETI_CLI_USER=admin
root@vm-gluster-01:# export HEKETI_CLI_KEY=your_admin_secret

root@vm-gluster-01:# heketi-cli topology load --json=/etc/heketi/topology.json
```

## 3) Kubernetes Dynamic Provisioner

First you must install glusterfs-fuse package on all Kubernetes Worker Nodes

```
yum -y install glusterfs-fuse
```

gluster-client.json needs to be installed on all k8s nodes otherwise the mounting of the GlusterFS volumes will fail. Need to create DeamonSet likewise:

```
kubectl apply -f manifests/gluster-client.json
```

Create a kubernetes Secret for the admin user password in the following gluster-client-secret.yaml file:

```
kubectl apply -f manifests/gluster-admin-secret.yml
```

Kuberentes has built-in plugin for GlusterFS. We need to create a new glusterfs storage class that will use our Heketi service. Create YAML file storage-class.yml likewise:

```
kubectl apply -f manifests/storage-class.yml
```

To test it we create a PVC (Persistent Volume Claim) that should dynamically provision a 1GB volume for us in the Gluster storage. Create pvc.yaml likewise :

```
kubectl apply -f manifest/pvc.yml
```

To use the volume we reference the PVC in the YAML file of any Pod/Deployment like this for example:

```
kubectl apply -f manifests/pod.yml
```

## 4) Adding new disk to working cluster

Just change you topology.json with new added disks and run heketi-cli command:

```
{
  "clusters": [
    {
      "nodes": [
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-01"
              ],
              "storage": [
                "172.31.22.111"
              ]
            },
            "zone": 1
          },
          "devices": [
            "/dev/sdb",
            "/dev/sdc" << New disk
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-02"
              ],
              "storage": [
                "172.31.22.112"
              ]
            },
            "zone": 2
          },
          "devices": [
            "/dev/sdb",
            "/dev/sdc" << New disk
          ]
        },
        {
          "node": {
            "hostnames": {
              "manage": [
                "vm-gluster-03"
              ],
              "storage": [
                "172.31.22.113"
              ]
            },
            "zone": 3
          },
          "devices": [
            "/dev/sdb",
            "/dev/sdc" << New disk
          ]
        }
      ]
    }
  ]
}
```

```
root@vm-gluster-01:# export HEKETI_CLI_SERVER=http://vm-gluster-01:8080
root@vm-gluster-01:# export HEKETI_CLI_USER=admin
root@vm-gluster-01:# export HEKETI_CLI_KEY=your_admin_secret

root@vm-gluster-01:# heketi-cli topology load --json=/etc/heketi/topology.json
```

## How to find Kubernetes PV in Gluster Node FS

First get vol name from Kubernetes pv

```
root@ ~ () $ kubectl describe pv pvc-3bd6e9fd-02d8-4607-b227-e12bc4f5b425 
Name:            pvc-3bd6e9fd-02d8-4607-b227-e12bc4f5b425
Labels:          <none>
Annotations:     Description: Gluster-Internal: Dynamically provisioned PV
                 gluster.kubernetes.io/heketi-volume-id: 7b2725456116ee53cdef1fb60a31512e
                 gluster.org/type: file
                 kubernetes.io/createdby: heketi-dynamic-provisioner
                 pv.beta.kubernetes.io/gid: 2001
                 pv.kubernetes.io/bound-by-controller: yes
                 pv.kubernetes.io/provisioned-by: kubernetes.io/glusterfs
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:    gluster-heketi-external
Status:          Bound
Claim:           default/gluster-pvc2
Reclaim Policy:  Delete
Access Modes:    RWX
VolumeMode:      Filesystem
Capacity:        2Gi
Node Affinity:   <none>
Message:         
Source:
    Type:                Glusterfs (a Glusterfs mount on the host that shares a pod's lifetime)
    EndpointsName:       glusterfs-dynamic-3bd6e9fd-02d8-4607-b227-e12bc4f5b425
    EndpointsNamespace:  default
    Path:                vol_7b2725456116ee53cdef1fb60a31512e << This is your vol name
    ReadOnly:            false
Events:                  <none>
```

Now on Gluster Node:

```
root@vm-gluster-01:# export HEKETI_CLI_SERVER=http://vm-gluster-01:8080
root@vm-gluster-01:# export HEKETI_CLI_USER=admin
root@vm-gluster-01:# export HEKETI_CLI_KEY=your_admin_secret

root@vm-gluster-01:# heketi-cli volume list | grep vol_7b2725456116ee53cdef1fb60a31512e

Id:7b2725456116ee53cdef1fb60a31512e    Cluster:8b959511a1194d3cb5cc80d2163fb9ef    Name:vol_7b2725456116ee53cdef1fb60a31512e
```

Get Id from output and find mount point:

```
root@vm-gluster-01:# heketi-cli volume info 7b2725456116ee53cdef1fb60a31512e --json | jq '.bricks'

[
  {
    "id": "48b6907b49849561ad08c7d57c3797e5",
    "path": "/var/lib/heketi/mounts/vg_7d451447e99471ee25698a82e7d0a91c/brick_48b6907b49849561ad08c7d57c3797e5/brick",
    "device": "7d451447e99471ee25698a82e7d0a91c",
    "node": "6917ce84fa4a3d959717fda2ff4b0f78",
    "volume": "7b2725456116ee53cdef1fb60a31512e",
    "size": 2097152
  },
  {
    "id": "9e8ba15d02d201d3e06cf9d83e0fcafa",
    "path": "/var/lib/heketi/mounts/vg_856662043a0484e78fdcc0a2219cb871/brick_9e8ba15d02d201d3e06cf9d83e0fcafa/brick",
    "device": "856662043a0484e78fdcc0a2219cb871",
    "node": "dc8758aaf1accc3b1b1597bee87431aa",
    "volume": "7b2725456116ee53cdef1fb60a31512e",
    "size": 2097152
  },
  {
    "id": "bc8ad89224c3633e2ec165a52b1200aa",
    "path": "/var/lib/heketi/mounts/vg_9fb690f49bfdc18eda4d8a6dc7107489/brick_bc8ad89224c3633e2ec165a52b1200aa/brick",
    "device": "9fb690f49bfdc18eda4d8a6dc7107489",
    "node": "daceaa19f072643dc28d03e420b037e9",
    "volume": "7b2725456116ee53cdef1fb60a31512e",
    "size": 2097152
  }
]
```

You see all 3 Gluster Nodes with parameter "path", it's mount point of your brick-PV
