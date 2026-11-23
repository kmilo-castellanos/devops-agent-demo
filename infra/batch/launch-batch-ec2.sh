#!/usr/bin/env bash
# Crea la EC2 del batch Java legado (D2): Java 17, CloudWatch Agent y cron cada 5 min.
# Requiere que el repo sea PÚBLICO (la instancia descarga los archivos de raw.githubusercontent.com).
#
# Uso: AWS_PROFILE=aidlc-workshop ./infra/batch/launch-batch-ec2.sh
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
GH_REPO="${GH_REPO:-kmilo-castellanos/devops-agent-demo}"
BRANCH="${BRANCH:-main}"
INSTANCE_PROFILE="${INSTANCE_PROFILE:-AmazonEC2RoleForLaunchWizard}"   # perfil de instancia con el rol indicado
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
RAW_BASE="https://raw.githubusercontent.com/${GH_REPO}/${BRANCH}/batch"

echo ">> Comprobando que el repo es accesible públicamente"
curl -fsS -o /dev/null "${RAW_BASE}/src/LegacyBatchJob.java" || {
  echo "No se pudo descargar ${RAW_BASE}/src/LegacyBatchJob.java. ¿El repo es público y el push está hecho?" >&2
  exit 1
}

VPC_ID="$(aws ec2 describe-vpcs --region "$REGION" --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)"
SUBNET_ID="$(aws ec2 describe-subnets --region "$REGION" --filters Name=vpc-id,Values="$VPC_ID" Name=default-for-az,Values=true --query 'Subnets[0].SubnetId' --output text)"
AMI_ID="$(aws ssm get-parameter --region "$REGION" --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 --query Parameter.Value --output text)"

echo ">> Security group sin reglas de entrada"
SG_ID="$(aws ec2 describe-security-groups --region "$REGION" --filters Name=group-name,Values=legacy-batch-demo Name=vpc-id,Values="$VPC_ID" --query 'SecurityGroups[0].GroupId' --output text)"
if [ "$SG_ID" = "None" ]; then
  SG_ID="$(aws ec2 create-security-group --region "$REGION" --group-name legacy-batch-demo \
    --description "Demo batch Java legado, sin entrada" --vpc-id "$VPC_ID" --query GroupId --output text)"
fi

USER_DATA="$(mktemp)"
cat > "$USER_DATA" <<EOF
#!/bin/bash
set -x
dnf install -y java-17-amazon-corretto-devel amazon-cloudwatch-agent cronie
mkdir -p /opt/batch/{src,config,data,bin,classes,out} /var/log/batch
for f in src/LegacyBatchJob.java config/batch.properties data/orders.csv bin/run-job.sh cloudwatch-agent.json; do
  curl -fsS "${RAW_BASE}/\$f" -o "/opt/batch/\$f"
done
chmod +x /opt/batch/bin/run-job.sh
javac -d /opt/batch/classes /opt/batch/src/LegacyBatchJob.java
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/batch/cloudwatch-agent.json
echo "RAW_BASE=${RAW_BASE}" > /etc/batch.env
echo "*/5 * * * * root . /etc/batch.env && export RAW_BASE && /opt/batch/bin/run-job.sh" > /etc/cron.d/legacy-batch
systemctl enable --now crond
EOF

echo ">> Lanzando instancia ${INSTANCE_TYPE} con el perfil ${INSTANCE_PROFILE}"
INSTANCE_ID="$(aws ec2 run-instances --region "$REGION" \
  --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
  --subnet-id "$SUBNET_ID" --security-group-ids "$SG_ID" --associate-public-ip-address \
  --iam-instance-profile Name="$INSTANCE_PROFILE" \
  --metadata-options HttpTokens=required,HttpEndpoint=enabled \
  --user-data "file://${USER_DATA}" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=legacy-batch-demo},{Key=Project,Value=devops-agent-demo}]' \
  --query 'Instances[0].InstanceId' --output text)"
rm -f "$USER_DATA"

echo "Instancia: ${INSTANCE_ID}"
echo "En ~3 min el cron empieza a escribir en el log group /demo/legacy-batch."
echo "Limpieza: aws ec2 terminate-instances --instance-ids ${INSTANCE_ID} --region ${REGION}"
