#!/bin/bash
#Version 0.6.5
trap exit SIGINT SIGKILL SIGTERM
log=vrops-cluster-repair.log
read -p "This script will reset your vROps cluster to a known good state. 
It is not supported by VMware, and you should take a snapshot before running it.
Please note that SSH must be enabled on _ALL_ nodes for this to work, which is not the default.

Press enter to continue or CTRL-C to exit. # " nothing

echo -e "==========| Starting repair script at `date` |==========\n" >> $log
exec > >(tee -a $log );exec 2> >(tee -a $log >&2)
detected_nodes="$(grep -oiP '"ip_address":"[a-zA-Z0-9\.-_]+"' $STORAGE_DB_VCOPS/../casa/webapp/hsqldb/casa.db.script | cut -d '"' -f4 | tr '\n' ' ')"
if [ "$detected_nodes" = "" ]; then detected_nodes="localhost" ; fi

# You may enter a space-separated list of FQDNs or IPs for each node in the cluster in place of $detected_nodes between the quotes below.
# Use the following order for your nodes where applicable: Master, Master Replica, Data, Remote Collector
node_list="$detected_nodes"
stop_order="$(echo "$node_list" | tr ' ' '\n' | tac | tr '\n' ' ')"
read -p "Please verify that this is a complete list of all your nodes:

$node_list

If not, please edit this script to ensure that all cluster members are manually added.

Press enter to continue or CTRL-C to exit. # " nothing

echo -e "\nChecking SSH connectivity to nodes..."
	disconnect () { echo "Unable to connect to $1 on port 22, please ensure ssh is enabled on this host. Exiting."; exit 1; }
	for h in $node_list; do 
		timeout -k 3 2 echo "Port 22 is open on $h" 3> /dev/tcp/$h/22 || disconnect $h; 
	done

if [ ! -e "$HOME/.ssh/id_rsa.pub" ]; then 
	echo -e "\nNo SSH keys found. We will generate one now. Please accept all defaults."
		ssh-keygen -q || exit 1
fi

echo -e "\nWe will now push the SSH host-key out to the nodes. This will require logging in to each of the nodes one time each. Please follow the prompts as they appear and accept all defaults.\n"
for h in $node_list; do 
	ssh-copy-id -o StrictHostKeyChecking=no root@$h || exit 1
done

read -p "Clear out alarms and alerts from database? (optional, requires cluster to be online)
(y/N) # " yn
if [[ "$yn" =~ y|yes|1 ]]; then 
		echo "This will produce errors on remote collectors, please ignore them."
	for h in $node_list; do 
		echo -e "\nBacking up alerts and alarms database..."
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/pg_dumpall | gzip -9 > \$STORAGE/db/vcops/vpostgres/pg_dumpall-`date +%F_%I.%M.%S_%p_%Z`.gz"
		echo -e "\nTruncating alerts and alarms on $h..."
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/psql vcopsdb -c 'truncate alarm cascade;'"
			ssh -q root@$h "sudo -u postgres /opt/vmware/vpostgres/current/bin/psql vcopsdb -c 'truncate alert cascade;'"
done
fi

echo -e "\nWe will now perform the cluster repair. You may see some messages about services not stopping properly. This is expected.\n"
read -p "Press enter to continue or CTRL-C to exit. # " nothing
for h in $stop_order; do
	echo -e "\n==========| Performing cluster state repair on $h |=========="
	echo "Taking node offline..."
		ssh -q root@$h "\$VMWARE_PYTHON_BIN \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/bin/vcopsConfigureRoles.py --action bringSliceOffline --offlineReason \"repairing\""
	echo "Stopping services..."
		ssh -q root@$h "service vmware-vcops-web stop"
		ssh -q root@$h "service vmware-vcops stop"
		ssh -q root@$h "service vmware-casa stop"
	echo "Altering cluster state..."
		ssh -q root@$h "sed -ri.bak 's/sliceonline = \w+/sliceonline = false/g;s/failuredetected = \w+/failuredetected = false/g;s/offlinereason = \w+/offlinereason = /g' \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/data/roleState.properties"
		ssh -q root@$h "sed -ri.bak 's/\"onlineState\":\"\w+\"/\"onlineState\":\"OFFLINE\"/g;s/\"ha_transition_state\":\"\w+\"/\"ha_transition_state\":\"NONE\"/g;s/\"initialization_state\":\"\w+\"/\"initialization_state\":\"NONE\"/g;s/\"online_state\":\"\w+\"/\"online_state\":\"OFFLINE\"/g;s/\"online_state_reason\":\"[a-zA-Z0-9:,_\?\-\.]+\"/\"online_state_reason\":\"\"/g' \$STORAGE_DB_VCOPS/../casa/webapp/hsqldb/casa.db.script"
	#This should only be done as a last resort.
	#echo "Backing up and removing activities..."
	#	ssh -q root@$h "zip -r2mq \$STORAGE/db/vcops/activity-backup-`date +%F_%I.%M.%S_%p_%Z`.zip \$STORAGE/db/vcops/activity/*" 
	echo "Moving old upgrade pak files..."
		ssh -q root@$h "mkdir -p \$STORAGE/db/casa/pak/dist_pak_files_backup"
		ssh -q root@$h "mv \$STORAGE/db/casa/pak/dist_pak_files/* \$STORAGE/db/casa/pak/dist_pak_files_backup/"
	echo "Backing up and removing old upgrade state file..."
		ssh -q root@$h "zip -2mq vcops_upgrade_state-`date +%F_%I.%M.%S_%p_%Z`.zip \$STORAGE/log/var/log/vmware/vcops/vcops_upgrade_state.json"
	echo "Backing up and truncating migration blobs that break upgrades..."
		ssh -q root@$h "find \$STORAGE_DB_VCOPS/blob/migrationUpgrade/ -type f -size +31M -exec zip -2q \$STORAGE/db/xdb-migrationupgrade-{}-`date +%F_%I.%M.%S_%p_%Z`.zip {} \; -exec truncate -cs 0 {} \;"
done

echo -e "\nYou should see some messages about services refusing to start due to the cluster state being offline. This is expected.\n"
for h in $node_list; do
	echo -e "\n==========| Restarting services on $h |=========="
		ssh -q root@$h "service vmware-casa start"
		ssh -q root@$h "service vmware-vcops start"
		ssh -q root@$h "service vmware-vcops-web start"
done

for h in $node_list; do
	echo -e "\n==========| Bringing node $h online |=========="
	ssh -q root@$h "\$VMWARE_PYTHON_BIN \$VCOPS_BASE/../vmware-vcopssuite/utilities/sliceConfiguration/bin/vcopsConfigureRoles.py --action bringSliceOnline"
done 

echo -e "\n==========| Getting time of each node |=========="
for h in $node_list; do
	echo "Date/time on $h is `ssh -q root@$h date`"
done 
echo -e "\nIf any of the above times are more than 10 seconds out of sync, that can cause issues in the cluster services. Ensure they are using proper host or NTP time sync or set their clocks manually.\n"

echo -e "\n==========| Finished repair script at `date` |==========\n" | tee -a $log
