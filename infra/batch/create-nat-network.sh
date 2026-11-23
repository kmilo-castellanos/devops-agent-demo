#!/usr/bin/env bash
# Crea una subred privada con salida por NAT gateway en la VPC por defecto.
# Necesario porque la cuenta tiene VPC Block Public Access en modo block-ingress:
# el tráfico por internet gateway está bloqueado, pero el de NAT gateway no.
# No modifica la tabla de rutas principal ni las subredes existentes.
#
# Uso: AWS_PROFILE=aidlc-workshop ./infra/batch/create-nat-network.sh
# Imprime PRIVATE_SUBNET_ID para usarlo en launch-batch-ec2.sh.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
VPC_ID="${VPC_ID:-vpc-26617b5c}"
PUBLIC_SUBNET_ID="${PUBLIC_SUBNET_ID:-subnet-9d1c82d0}"   # us-east-1b, ruta al IGW
PRIVATE_CIDR="${PRIVATE_CIDR:-172.31.112.0/20}"
TAGS='{Key=Project,Value=devops-agent-demo}'

AZ="$(aws ec2 describe-subnets --region "$REGION" --subnet-ids "$PUBLIC_SUBNET_ID" --query 'Subnets[0].AvailabilityZone' --output text)"

echo ">> Subred privada ${PRIVATE_CIDR} en ${AZ}"
PRIVATE_SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" Name=cidr-block,Values="$PRIVATE_CIDR" --query 'Subnets[0].SubnetId' --output text)"
if [ "$PRIVATE_SUBNET_ID" = "None" ]; then
  PRIVATE_SUBNET_ID="$(aws ec2 create-subnet --region "$REGION" --vpc-id "$VPC_ID" --cidr-block "$PRIVATE_CIDR" --availability-zone "$AZ" \
    --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=devops-agent-demo-private},${TAGS}]" \
    --query 'Subnet.SubnetId' --output text)"
fi
echo "   ${PRIVATE_SUBNET_ID}"

echo ">> NAT gateway en ${PUBLIC_SUBNET_ID}"
NAT_ID="$(aws ec2 describe-nat-gateways --region "$REGION" --filter Name=tag:Name,Values=devops-agent-demo-nat Name=state,Values=pending,available --query 'NatGateways[0].NatGatewayId' --output text)"
if [ "$NAT_ID" = "None" ]; then
  ALLOC_ID="$(aws ec2 allocate-address --region "$REGION" --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=devops-agent-demo-nat},${TAGS}]" \
    --query AllocationId --output text)"
  NAT_ID="$(aws ec2 create-nat-gateway --region "$REGION" --subnet-id "$PUBLIC_SUBNET_ID" --allocation-id "$ALLOC_ID" \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=devops-agent-demo-nat},${TAGS}]" \
    --query 'NatGateway.NatGatewayId' --output text)"
fi
echo "   ${NAT_ID} (esperando a que esté disponible)"
aws ec2 wait nat-gateway-available --region "$REGION" --nat-gateway-ids "$NAT_ID"

echo ">> Tabla de rutas privada"
RT_ID="$(aws ec2 describe-route-tables --region "$REGION" --filters Name=tag:Name,Values=devops-agent-demo-private --query 'RouteTables[0].RouteTableId' --output text)"
if [ "$RT_ID" = "None" ]; then
  RT_ID="$(aws ec2 create-route-table --region "$REGION" --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=devops-agent-demo-private},${TAGS}]" \
    --query 'RouteTable.RouteTableId' --output text)"
fi
aws ec2 create-route --region "$REGION" --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" >/dev/null 2>&1 ||
  aws ec2 replace-route --region "$REGION" --route-table-id "$RT_ID" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID"
aws ec2 associate-route-table --region "$REGION" --route-table-id "$RT_ID" --subnet-id "$PRIVATE_SUBNET_ID" >/dev/null 2>&1 || true
echo "   ${RT_ID} (0.0.0.0/0 -> ${NAT_ID})"

echo
echo "PRIVATE_SUBNET_ID=${PRIVATE_SUBNET_ID}"
