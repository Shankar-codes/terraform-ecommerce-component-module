#/bin/bash

component=$1
dnf install ansible -y
#pip3 install boto3 botocore
#ansible-pull -U https://github.com/Shankar-codes/ansible-roles-terraform.git -e component=$component main.yaml

REPO_URL=https://github.com/Shankar-codes/ansible-roles-terraform.git
REPO_DIR=/opt/ellamma-roboshop/ansible
ANSIBLE_DIR=ansible-roles-terraform

mkdir -p $REPO_DIR
mkdir -p /var/log/roboshop/
touch ansible.log

cd $REPO_DIR

if [ -d $ANSIBLE_DIR ]; then
  cd $ANSIBLE_DIR
  git pull
else
  git clone $REPO_URL
  cd $ANSIBLE_DIR
fi

ansible-playbook -e component=$component main.yaml