#!/bin/bash
#################################################################
# Setup datastax repo and install opscenter
#################################################################
echo "[datastax]" > /etc/yum.repos.d/datastax.repo
echo "name = DataStax Repo for Apache Cassandra" >> /etc/yum.repos.d/datastax.repo
echo "baseurl = http://rpm.datastax.com/community" >> /etc/yum.repos.d/datastax.repo
echo "enabled = 1" >> /etc/yum.repos.d/datastax.repo
echo "gpgcheck = 0" >> /etc/yum.repos.d/datastax.repo
yum install -y opscenter

