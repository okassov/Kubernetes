# Kubernetes authentication with LDAP (dex + gangway)

This tutorial is create for private bare metal cluster which produces some limitations as servers are in a private network so we can’t depend on public DNS to publish the dex and gangway domains and we will depend on LDAP for this task also we can’t depend on Letsencrypt or another public certificates so will use self-signed cert-manager generated certificates.

## Workflow

So as the "workflow.png" diagram shows the user will first use url ‘kube-login.example.com’ then he will be rediected to dex to enter LDAP username and password then dex will verify this data with LDAP depending on what LDAP return dex should decide whether generating token or not.

## Prerequisits

- LDAP Server for managing Users and DNS
- Kubernetes Ingress Controller
- Enabled RBAC in cluster

Created DNS records for dex and gangway:

- dex.example.com
- kube-login.example.com

Both dex.example.com and kube-login.example.com records should points to your ingress nodes.

## Configuring

### Deploying DEX

1. Create Namespace

```
kubectl create ns auth-system
```

2. Apply RBAC for dex deployment

```
kubectl create -f manifests/dex-rbac.yaml
```

3. Configure dex configmap with your  and apply it

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: dex
  namespace: auth-system
data:
  config.yaml: |
    issuer: https://dex.example.com/
    web:
      http: 0.0.0.0:5556
    frontend:
      theme: "coreos"
      issuer: "kube-dtln"
      issuerUrl: "https://login.ash.dtln.cloud"
    telemetry:
      http: 0.0.0.0:5558
    staticClients:
    - id: oidc-auth-client
      redirectURIs:
      - 'https://kuge-login.example.com/callback'
      - 'http://dashboard.example.com/oauth2/callback'
      name: 'oidc-auth-client'
      secret: XmT7EHo27skGchX0yLQNTYXibm3aNkx5
    connectors:
    - type: ldap
      id: ldap
      name: LDAP
      config:
        host: <LDAP FQDN/IP>:389
        insecureNoSSL: true
        insecureSkipVerify: true
        bindDN: CN=kube_ldap_user,OU=Users,DC=example,DC=com
        bindPW: 'pass'
        userSearch:
          baseDN: OU=Users,DC=example,DC=com
          filter: (objectClass=person)
          username: sAMAccountName
          idAttr: sAMAccountName
          emailAttr: mail
          nameAttr: name
        groupSearch:
          baseDN: OU=Groups,DC=example,DC=com
          filter: "(objectClass=group)"
          userAttr: DN
          groupAttr: member
          nameAttr: name
    oauth2:
      skipApprovalScreen: true
    storage:
      type: kubernetes
      config:
        inCluster: true
        
kubectl create -f manifests/dex-configmap.yaml
```

4. Create dex deployment

```
kubectl create -f manifests/dex-deploy.yaml
```

Note: If using PROXY, then add to deployment's init container env with https_proxy for git cloning or pod stacked in ContainerCreating state.

5. Create dex service

```
kubectl create -f manifests/dex-service.yaml
```

6. Create dex ingress rule (I use Istio Ingress, therefore create Virtual Service)

```
kubectl create -f dex-ingress.yaml
```
Wait till the Dex certificate generated then browse this link to check that Dex is deployed properly https://dex.example.com/.well-known/openid-configuration

### Kubernetes API configurations

Note: If you have mutli master cluster you need to apply this to all of them

```
sudo vim /etc/kubernetes/manifests/kube-apiserver.yaml

spec:
  containers:
  - command:
    - kube-apiserver
    ....
    - --oidc-issuer-url=https://dex.example.com/
    - --oidc-client-id=oidc-auth-client
    - --oidc-username-claim=email
    - --oidc-groups-claim=groups
```

### Deploy Gangway

This is the portal the user will access. It generates a user friendly instruction to how setup your token.

1. Generate a secret key for Gangway.

```
kubectl -n auth-system create secret generic gangway-key --from-literal=sesssionkey=$(openssl rand -base64 32)
```

2. Configure and create a Gangway configmap.

```
apiVersion: v1
kind: ConfigMap
metadata:
  name: gangway
  namespace: auth-system
data:
  gangway.yaml: |
    clusterName: "<CLUSTER NAME>"
    apiServerURL: "https://<API SERVER URL>:6443"
    authorizeURL: "https://dex.exmaple.com/auth"
    tokenURL: "https://dex.exmaple.com/token"
    clientID: "oidc-auth-client"
    clientSecret: "XmT7EHo27skGchX0yLQNTYXibm3aNkx5"
    redirectURL: "https://kube-login.exmaple.com/callback"
    scopes: ["openid", "profile", "email", "groups", "offline_access"]
    usernameClaim: "email"
    emailClaim: "email"
    trustedCAPath: "/cacerts/tls.crt"

kubectl create -f manifests/gangway-configmap.yaml
```

3. Create secret with kubernetes ca.crt and ca.key 

```
kubectl -n auth-system create secret tls dex --key ca.key --cert ca.crt
```

4. Create a Gangway deployment

```
kubectl create -f manifests/gangway-deployment.yaml
```

5. Create a Gangway service

```
kubectl apply -f manifests/gangway-service.yaml
```

6. Create Gangway ingress role

```
kubectl apply -f manifests/gangway-ingress.yaml
```

Wait till Gangway certificate generated then browse kube-login.example.com. 

7. And login with your LDAP account.

8. Follow the generated instruction to configure your kubectl and kubeconfig file

9. Check your configuration

```
kubectl get pods

Error from server (Forbidden): pods is forbidden: User "your_ldap_account@example.com" cannot list resource "pods" in API group "" in the namespace "default"
```

Note: You get ERROR message, because your LDAP user not binding to Role or ClusterRole

### Create RBAC

1. Create Role or ClusterRole and bind User or Group to this Role (In this example we use default pre-creating ClusterRole with view permissions, therefore we create only ClsuterRoleBinding)

```
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: group-binding
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: Group
  name: "your_ldap_group"

or

apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: user-binding
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: view
subjects:
- kind: User
  name: "your_ldap_user@example.com"
```

2. Check your configuration

```
kubectl get pods

Cool. It works!!!
```
