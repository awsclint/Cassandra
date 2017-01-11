#!/bin/bash
#################################################################
# Install cfn and xfs packages
#################################################################
yum update -y aws-cfn-bootstrap
yum -y install xfsprogs
#################################################################
# Set limits
#################################################################
echo "cassandra - memlock unlimited\ncassandra - nofile 100000\ncassandra - nproc 32768\ncassandra - as unlimited" >> /etc/security/limits.d/cassandra.conf
echo "* - nproc 32768" >> /etc/security/limits.d/90-nproc.conf
echo "vm.max_map_count = 131072" >> /etc/sysctl.conf
sysctl -p
#################################################################
# Configuration to manage node replacements and record node changes in dynamodb
#################################################################
instanceid=$(curl -s curl http://169.254.169.254/latest/meta-data/instance-id/)
commitlogvolume=$(cat /tmp/describec2instance.data|grep -A 5 "/dev/xvdbb"|grep VolumeId|cut -d':' -f2|cut -d'"' -f2)
datavolume=$(cat /tmp/describec2instance.data|grep -A 5 "/dev/xvdba"|grep VolumeId|cut -d':' -f2|cut -d'"' -f2)
az=$(curl -s curl http://169.254.169.254/latest/meta-data/placement/availability-zone)
python -c "import boto; from boto.dynamodb2.table import Table; table = Table('cassandraasgreplace'); table.put_item(data = { 'instanceid' : '$instanceid', 'privateIP' : '$(cat /tmp/eip.data)', 'datavolumeinfo' : '$datavolume', 'commitlogvolumeinfo' : '$commitlogvolume', 'availabilityzone' : '$az', 'status' : 'current', 'role' : 'Seed' }); "
newlaunch=$(cat /tmp/asgactivity.data|grep Description|head -1|grep -c Launching)
terminateold=$(cat /tmp/asgactivity.data|grep Description|head -2|tail -1|grep -ic Terminating) 
if [[ $newlaunch -eq 1 && $terminateold -eq 1 ]]; then 
	oldinstanceid=$(cat /tmp/asgactivity.data|grep Description|head -2|tail -1|grep -i Terminating|cut -d':' -f3|cut -d'"' -f1|cut -d' ' -f2); 
else oldinstanceid="none"; 
fi
if [[ $oldinstanceid != "none" ]]; then 
	dollar='$'; 
	python -c "import boto; from boto.dynamodb2.table import Table; table = Table('cassandraasgreplace'); privateip = table.get_item(instanceid = '$oldinstanceid',availabilityzone='$az'); privateip['status'] = 'Terminated'; privateip['replacementnode'] = '$instanceid'; privateip.save();"; 
fi
#################################################################
# Setup Filesystem, directories and permissions
#################################################################
for mntpnt in `cat /proc/mounts|grep xvd[b-z]|awk '{print $1}'`; 
do 
	umount $mntpnt; 
done
mkfs -t xfs /dev/xvdba
mkfs -t xfs /dev/xvdbb
mkdir -p /data
mkdir -p /commitlog
mount -t xfs -o noatime /dev/xvdba /data
mount -t xfs -o noatime /dev/xvdbb /commitlog
chmod 777 /etc/fstab
echo "/dev/xvdba /data xfs noatime 0 0" | tee -a /etc/fstab
echo "/dev/xvdbb /commitlog xfs noatime 0 0" | tee -a /etc/fstab
mkdir -p /data/saved_caches
adduser cassandra
chown -R cassandra:cassandra /data
chown -R cassandra:cassandra /commitlog
