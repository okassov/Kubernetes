#!/bin/bash

export GOVC_USERNAME='kube-pv@technodom.kz'
export GOVC_INSECURE=1
export GOVC_PASSWORD='pass'
export GOVC_URL='vcsa-co.technodom.kz'
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
  kubectl patch node $VM_NAME.technodom.kz -p "{\"spec\":{\"providerID\":\"vsphere://$VM_UUID\"}}"
done
