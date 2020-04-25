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



