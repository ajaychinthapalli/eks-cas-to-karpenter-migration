---
id: tag-resources
title: "Step 2: Tag Resources"
sidebar_label: "2. Tag Resources"
sidebar_position: 3
---

# Step 2: Tag Resources

## Goal

Tag subnets and the node security group so Karpenter's `EC2NodeClass`
discovery selectors can find them (`karpenter.sh/discovery: <cluster-name>`).

## Pre-check: identify private vs public subnets and the real node SG

```bash
for SUBNET in <SUBNET_ID_A> <SUBNET_ID_B> <SUBNET_ID_C>; do
  aws ec2 describe-route-tables --region $AWS_REGION \
    --filters "Name=association.subnet-id,Values=$SUBNET" \
    --query "RouteTables[].Routes[?GatewayId!=null].{Gateway:GatewayId,Dest:DestinationCidrBlock}" \
    --output table
done

aws ec2 describe-subnets --region $AWS_REGION \
  --filters "Name=vpc-id,Values=<VPC_ID>" \
  --query "Subnets[].{ID:SubnetId,AZ:AvailabilityZone,CIDR:CidrBlock,Name:Tags[?Key=='Name']|[0].Value,Public:MapPublicIpOnLaunch}" \
  --output table

aws ec2 describe-instances --instance-ids <INSTANCE_ID_A> \
  --region $AWS_REGION --query "Reservations[].Instances[].SecurityGroups"
```

**Finding:** all 3 subnets in this VPC route `0.0.0.0/0` directly to an
Internet Gateway and auto-assign public IPs — **there are no private subnets
in this VPC at all**. Not a blocker for Karpenter, but nodes get public IPs by
default. Flagged as a follow-up in the top-level README; not fixed as part of
this migration.

Node security group in use: `<NODE_SECURITY_GROUP_ID>`
(`achin16nodegroupstack-NodeSecurityGroup-957lCLUx4j8G`).

## Commands run

```bash
# Tag subnets
aws ec2 create-tags \
  --region $AWS_REGION \
  --resources <SUBNET_ID_A> <SUBNET_ID_B> <SUBNET_ID_C> \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME

# Tag the node security group
aws ec2 create-tags \
  --region $AWS_REGION \
  --resources <NODE_SECURITY_GROUP_ID> \
  --tags Key=karpenter.sh/discovery,Value=$CLUSTER_NAME

# Verify
aws ec2 describe-tags --region $AWS_REGION \
  --filters "Name=key,Values=karpenter.sh/discovery" \
  --query "Tags[].{Resource:ResourceId,Value:Value}" --output table
```

## Verified result

```
---------------------------------------------------
|                  DescribeTags                   |
+---------------------------+---------------------+
|         Resource          |        Value        |
+---------------------------+---------------------+
|  <SUBNET_ID_C> |  achin16-workspace  |
|  <SUBNET_ID_B> |  achin16-workspace  |
|  <SUBNET_ID_A> |  achin16-workspace  |
|  <NODE_SECURITY_GROUP_ID>     |  achin16-workspace  |
+---------------------------+---------------------+
```

All 4 resources tagged successfully.
