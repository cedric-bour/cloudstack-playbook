#!/bin/bash

cli=cmk

server_ip=192.168.0.254
server_net=192.168.0.0/24
dns_ext=8.8.8.8
dns_int=172.16.0.1
hpvr=KVM

guestInt=cloudbr0
MgmtInt=cloudbr1

pod_start=192.168.0.100
pod_end=192.168.0.200
pod_gw=192.168.0.1
pod_nmask=255.255.255.0

guest_start=172.16.0.100
guest_end=172.16.0.200
guest_gw=172.16.0.1
guest_nmask=255.255.0.0

host_ips=$server_ip
host_user=exploit
host_passwd=toor

sec_storage=nfs://$server_ip/export/secondary
prm_storage=nfs://$server_ip/export/primary

zone_id=`$cli create zone dns1=$dns_ext internaldns1=$dns_int name=MyZone networktype=Basic localstorageenabled=false | jq '.zone.id'`
echo "Created zone" $zone_id

phy_id=`$cli create physicalnetwork name=phy-network zoneid=$zone_id | jq '.physicalnetwork.id'`
echo "Created physical network" $phy_id

$cli add traffictype traffictype=Guest kvmnetworklabel=$guestInt physicalnetworkid=$phy_id
echo "Added guest traffic"

$cli add traffictype traffictype=Management kvmnetworklabel=$MgmtInt physicalnetworkid=$phy_id
echo "Added mgmt traffic"

$cli update physicalnetwork state=Enabled id=$phy_id
echo "Enabled physicalnetwork"

nsp_id=`$cli list networkserviceproviders name=VirtualRouter physicalnetworkid=$phy_id | jq '.networkserviceprovider[0].id'`
vre_id=`$cli list virtualrouterelements nspid=$nsp_id | jq '.virtualrouterelement[0].id'`
$cli configure virtualRouterElement enabled=true id=$vre_id
$cli update networkserviceprovider state=Enabled id=$nsp_id
echo "Enabled virtual router element and network service provider"

netoff_id=`$cli list networkofferings name=DefaultSharedNetworkOffering | jq '.networkoffering[0].id'`
net_id=`$cli create network zoneid=$zone_id name=guestNetworkForBasicZone displaytext=guestNetworkForBasicZone networkofferingid=$netoff_id | jq '.network.id'`
echo "Created network $net_id for zone" $zone_id

pod_id=`$cli create pod name=MyPod zoneid=$zone_id gateway=$pod_gw netmask=$pod_nmask startip=$pod_start endip=$pod_end | jq '.pod.id'`
echo "Created pod"

$cli create vlaniprange podid=$pod_id networkid=$net_id gateway=$guest_gw netmask=$guest_nmask startip=$guest_start endip=$guest_end forvirtualnetwork=false
echo "Created IP ranges for instances"

cluster_id=`$cli add cluster zoneid=$zone_id hypervisor=$hpvr clustertype=CloudManaged podid=$pod_id clustername=MyCluster | jq '.cluster[0].id'`
echo "Created cluster" $cluster_id

echo "Configuration management IP"
$cli update configuration name=management.network.cidr value=$server_net
$cli update configuration name=host value=$server_ip

for host_ip in $host_ips;
do
  $cli add host zoneid=$zone_id podid=$pod_id clusterid=$cluster_id hypervisor=$hpvr username=$host_user password=$host_passwd url=http://$host_ip;
  echo "Added host" $host_ip;
done;

#$cli create storagepool zoneid=$zone_id podid=$pod_id clusterid=$cluster_id name=MyNFSPrimary url=$prm_storage
#echo "Added primary storage"

$cli add secondarystorage zoneid=$zone_id url=$sec_storage
echo "Added secondary storage"

$cli update zone allocationstate=Enabled id=$zone_id
echo "Basic zone deloyment completed!"
