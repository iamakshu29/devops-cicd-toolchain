#!/bin/bash
set -euo pipefail

###############################################################################
# Script Name : jenkins_nodes_setup.sh
# Description : Creates Jenkins Master Node Infra using Packer and Terraform
# Version     : 1.0.0
# Author      : Akshat Verma
# Created     : 2026-07-10
# Last Updated: 2026-07-10
# License     : MIT
# Usage       : 
# Requirements: 
###############################################################################

ACTION=${1:-}
DELETE_AMI=false

if [[ "${2:-}" == "--delete-ami" ]]; then
    DELETE_AMI=true
fi

if [[ -z "$ACTION" ]]; then
    read -rp "What do you want to do? (apply/destroy): " ACTION
fi

echo "=========================================================================================================================================="
echo "Checking for AWS"
if ! command -v aws >/dev/null 2>&1; then
    echo "AWS CLI not found."
    exit 1
fi

echo "=========================================================================================================================================="
echo "Checking for Packer"
if command -v packer >/dev/null 2>&1; then
    echo "Packer already present"
    packer version
    echo ""
else
    echo "Packer not present, Install Packer First"
    exit 1
fi

echo "=========================================================================================================================================="
echo "Checking for Terraform"
if command -v terraform >/dev/null 2>&1; then
    echo "Terraform already present"
    terraform version
    echo ""
else
    echo "Terraform not present, Install Terraform First"
    exit 1
fi

echo "=========================================================================================================================================="
echo "Initializing Packer..."
packer init ./packer

echo "=========================================================================================================================================="
echo "Initializing Terraform..."
terraform -chdir=./terraform init

case "$ACTION" in
    apply)
        AMI_ID=""

        if [[ -f manifest.json ]]; then
            AMI_ID=$(grep '"artifact_id"' manifest.json | tail -n 1 | cut -d'"' -f4 | cut -d':' -f2 | tr -d '\r')
        fi

        if [[ -n "$AMI_ID" ]] && [[ -n "$(aws ec2 describe-images --image-ids "$AMI_ID" --query 'Images[*].ImageId' --output text 2>/dev/null)" ]]; then
            echo "Using existing AMI: $AMI_ID"
        else
            echo "AMI not found, creating it..."

            echo "Validating Packer..."
            packer validate ./packer/jenkins_setup.pkr.hcl

            echo "Building AMI using Packer, Store the output to manifest.json"
            packer build ./packer/jenkins_setup.pkr.hcl

            AMI_ID=$(grep '"artifact_id"' manifest.json | tail -n 1 | cut -d'"' -f4 | cut -d':' -f2 | tr -d '\r')
        fi

        if [[ -z "$AMI_ID" ]]; then
            echo "Failed to create AMI"
            exit 1
        fi

        echo "Using AMI: $AMI_ID"

        echo "Validating Terraform..."
        terraform -chdir=./terraform validate

        echo "Planning Terraform..."
        terraform -chdir=./terraform plan -var="jenkins_master_ami_id=$AMI_ID" -out=tfplan

        echo "Applying Terraform..."
        terraform -chdir=./terraform apply tfplan
    ;;

    destroy)

        if [[ ! -f manifest.json ]]; then
            echo "manifest.json not found. Cannot determine AMI ID."
            exit 1
        fi

        AMI_ID=$(grep '"artifact_id"' manifest.json | tail -n 1 | cut -d'"' -f4 | cut -d':' -f2 | tr -d '\r')

        echo "Destroying Terraform infrastructure..."
        terraform -chdir=./terraform destroy -var="jenkins_master_ami_id=$AMI_ID"

        if [[ "$DELETE_AMI" == true ]]; then
            echo "AMI deletion requested."

            if [[ -n "$AMI_ID" ]]; then
                echo "Deleting AMI: $AMI_ID"

                SNAPSHOTS=$(aws ec2 describe-images \
                --image-ids "$AMI_ID" \
                --query 'Images[0].BlockDeviceMappings[*].Ebs.SnapshotId' \
                --output text)
                

                aws ec2 deregister-image --image-id "$AMI_ID"

                if [[ -n "$SNAPSHOTS" ]]; then
                    for SNAP in $SNAPSHOTS; do
                        aws ec2 delete-snapshot --snapshot-id "$SNAP"
                    done
                fi

                echo "Deleting manifest.json"
                rm -rf manifest.json

                echo "AMI cleanup completed."
            fi
        else
            echo "Keeping AMI for future use."
        fi
    ;;

    *)
        echo "Invalid option: $ACTION"
        echo "Please enter either 'apply' or 'destroy'."
        exit 1
    ;;
esac

# ./jenkins_nodes_setup.sh apply
# ./jenkins_nodes_setup.sh destroy
# ./jenkins_nodes_setup.sh destroy --delete-ami