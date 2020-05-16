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

