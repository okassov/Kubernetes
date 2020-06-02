# Backup with Velero

## Overview

Velero gives you tools to back up and restore your Kubernetes cluster resources and persistent volumes. 
You can run Velero with a cloud provider or on-premises. Velero lets you:

Take backups of your cluster and restore in case of loss.
Migrate cluster resources to other clusters.
Replicate your production cluster to development and testing clusters.

Velero consists of:

1. A server that runs on your cluster
2. A command-line client that runs locally

## Install Velero Client

Download and install Velero Client binary on your machine with access to Kubernetes cluster

```
wget https://github.com/vmware-tanzu/velero/releases/download/v1.4.0/velero-v1.4.0-linux-amd64.tar.gz
chmod +x velero
mv velero /usr/local/bin/
```

## Install Velero Server Side

Before Install:

- You must have s3 storage for keep backup files (In our case - Minio)
- Create s3 bucket for backup
- Create credentials-velero file with your S3 access_key and secret

Create credentials-velero file

```
[default]
aws_access_key_id = your_access_key
aws_secret_access_key = your_secret_key
```

Install Velero in your Kubernetes cluster

```
velero install \
    --provider aws \
    --plugins velero/velero-plugin-for-aws:v1.0.0 \
    --bucket velero-stage \
    --secret-file ./credentials-velero \
    --use-volume-snapshots=false \
    --use-restic \
    --backup-location-config region=minio,s3ForcePathStyle="true",s3Url=https://minio-s3.example.com
```

***Note:** key --use-restic allow to snapshot PersistentVolume data for non-cloud storages*

## Backup Create

First create test app with velero annotation

```
apiVersion: v1
kind: Service
metadata:
  name: wordpress-mysql
  namespace: test
  labels:
    app: wordpress
spec:
  ports:
    - port: 3306
      nodePort: 30306
  selector:
    app: wordpress
    tier: mysql
  type: NodePort
  
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mysql-pv-claim
  namespace: test
  labels:
    app: wordpress
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wordpress-mysql
  namespace: test
  labels:
    app: wordpress
spec:
  selector:
    matchLabels:
      app: wordpress
      tier: mysql
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: wordpress
        tier: mysql
      annotations:
        backup.velero.io/backup-volumes: mysql-persistent-storage # << Add annotations for velero backup
    spec:
      containers:
      - image: mysql:5.6
        name: mysql
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-pass
              key: password
        ports:
        - containerPort: 3306
          name: mysql
        volumeMounts:
        - name: mysql-persistent-storage
          mountPath: /var/lib/mysql
      volumes:
      - name: mysql-persistent-storage
        persistentVolumeClaim:
          claimName: mysql-pv-claim
```

Create schedule backup that run every 24 hour and keep in s3 storage 2 week (336h)

```
velero schedule create test-backup --schedule="* */24 * * *" --ttl 336h0m0s --include-namespaces test
```

## Backup Restore

Delete deployment and pv

```
kubectl -n test delete deployment wordpress-mysql
kubectl -n test delete pvc mysql-pv-claim
kubectl -n test delete pv ...
```

Get active backups

```
root@  () (⎈ |k8s-stage:test)# velero backup get

NAME                         STATUS      CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
test-backup-20200601055427   Completed   2020-06-01 11:54:27 +0600 +06   14m       default            <none>
test-backup-20200601055127   Completed   2020-06-01 11:51:27 +0600 +06   11m       default            <none>
test-backup-20200601054827   Completed   2020-06-01 11:48:27 +0600 +06   8m        default            <none>
```

Restore backup with velero

```
velero restore create --from-backup <your_backup_name>
```

## Throubleshooting

Check that schedule created

```
root@  () (⎈ |k8s-stage:test)# velero schedule get

NAME          STATUS    CREATED                         SCHEDULE      BACKUP TTL   LAST BACKUP   SELECTOR
test-backup   Enabled   2020-05-29 16:48:42 +0600 +06   * */24 * * *   336h0m0s        39s ago       <none>
```

Describe schedule for more information 

```
root@  () (⎈ |k8s-stage:test)# velero schedule describe test-backup

Name:         test-backup
Namespace:    velero
Labels:       <none>
Annotations:  <none>

Phase:  Enabled

Schedule:  * */24 * * *

Backup Template:
  Namespaces:
    Included:  test
    Excluded:  <none>
  
  Resources:
    Included:        *
    Excluded:        <none>
    Cluster-scoped:  auto
  
  Label selector:  <none>
  
  Storage Location:  
  
  Velero-Native Snapshot PVs:  auto
  
  TTL:  336h0m0s
  
  Hooks:  <none>

Last Backup:  2020-06-01 11:51:27 +0600 +06
```

Get all backups

```
root@  () (⎈ |k8s-stage:test)# velero backup get

NAME                         STATUS      CREATED                         EXPIRES   STORAGE LOCATION   SELECTOR
test-backup-20200601055427   Completed   2020-06-01 11:54:27 +0600 +06   14m       default            <none>
test-backup-20200601055127   Completed   2020-06-01 11:51:27 +0600 +06   11m       default            <none>
test-backup-20200601054827   Completed   2020-06-01 11:48:27 +0600 +06   8m        default            <none>
test-backup-20200601054527   Completed   2020-06-01 11:45:27 +0600 +06   5m        default            <none>
test-backup-20200601054227   Completed   2020-06-01 11:42:27 +0600 +06   2m        default            <none>
test-backup-20200601053927   Completed   2020-06-01 11:39:27 +0600 +06   49s ago   default            <none>
test-backup-20200601053627   Completed   2020-06-01 11:36:27 +0600 +06   3m ago    default            <none>
wordpress-backup             Completed   2020-05-29 14:16:17 +0600 +06   27d       default            <none>
wordpress-backup-2           Completed   2020-05-29 14:18:34 +0600 +06   27d       default            <none>
```

Describe backup for more information

```
root@  () (⎈ |k8s-stage:test)# velero backup describe test-backup-20200601055427

Name:         test-backup-20200601055427
Namespace:    velero
Labels:       velero.io/schedule-name=test-backup
              velero.io/storage-location=default
Annotations:  velero.io/source-cluster-k8s-gitversion=v1.17.0
              velero.io/source-cluster-k8s-major-version=1
              velero.io/source-cluster-k8s-minor-version=17

Phase:  Completed

Namespaces:
  Included:  test
  Excluded:  <none>

Resources:
  Included:        *
  Excluded:        <none>
  Cluster-scoped:  auto

Label selector:  <none>

Storage Location:  default

Velero-Native Snapshot PVs:  auto

TTL:  15m0s

Hooks:  <none>

Backup Format Version:  1

Started:    2020-06-01 11:54:27 +0600 +06
Completed:  2020-06-01 11:54:35 +0600 +06

Expiration:  2020-06-01 12:09:27 +0600 +06

Total items to be backed up:  27
Items backed up:              27

Velero-Native Snapshots: <none included>

Restic Backups (specify --details for more information):
  Completed:  1
```
