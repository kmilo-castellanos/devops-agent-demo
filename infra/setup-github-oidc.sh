#!/usr/bin/env bash
# Crea el repo ECR, el proveedor OIDC de GitHub, un rol para GitHub Actions
# y le da acceso al cluster EKS. Ejecutar DESPUÉS de crear el cluster.
#
# Uso: GH_REPO=<org>/<repo> ./infra/setup-github-oidc.sh
set -euo pipefail

: "${GH_REPO:?Define GH_REPO=<org>/<repo>}"
REGION="${AWS_REGION:-us-east-1}"
CLUSTER="${CLUSTER_NAME:-devops-agent-demo}"
ECR_REPO="${ECR_REPO:-demo-shop}"
ROLE_NAME="${ROLE_NAME:-gha-devops-agent-demo}"

ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
PROVIDER_ARN="arn:aws:iam::${ACCOUNT_ID}:oidc-provider/token.actions.githubusercontent.com"

echo ">> ECR repo"
aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$REGION" >/dev/null 2>&1 ||
  aws ecr create-repository --repository-name "$ECR_REPO" --region "$REGION" >/dev/null

echo ">> OIDC provider"
aws iam get-open-id-connect-provider --open-id-connect-provider-arn "$PROVIDER_ARN" >/dev/null 2>&1 ||
  aws iam create-open-id-connect-provider \
    --url https://token.actions.githubusercontent.com \
    --client-id-list sts.amazonaws.com >/dev/null

echo ">> IAM role ${ROLE_NAME}"
TRUST=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "${PROVIDER_ARN}" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:${GH_REPO}:*" }
    }
  }]
}
EOF
)
aws iam get-role --role-name "$ROLE_NAME" >/dev/null 2>&1 ||
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "$TRUST" >/dev/null

POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    { "Effect": "Allow", "Action": "ecr:GetAuthorizationToken", "Resource": "*" },
    { "Effect": "Allow",
      "Action": ["ecr:BatchCheckLayerAvailability","ecr:InitiateLayerUpload","ecr:UploadLayerPart",
                 "ecr:CompleteLayerUpload","ecr:PutImage","ecr:BatchGetImage","ecr:GetDownloadUrlForLayer"],
      "Resource": "arn:aws:ecr:${REGION}:${ACCOUNT_ID}:repository/${ECR_REPO}" },
    { "Effect": "Allow", "Action": "eks:DescribeCluster",
      "Resource": "arn:aws:eks:${REGION}:${ACCOUNT_ID}:cluster/${CLUSTER}" }
  ]
}
EOF
)
aws iam put-role-policy --role-name "$ROLE_NAME" --policy-name gha-deploy --policy-document "$POLICY"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

echo ">> EKS access entry"
aws eks create-access-entry --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$ROLE_ARN" >/dev/null 2>&1 || true
aws eks associate-access-policy --cluster-name "$CLUSTER" --region "$REGION" \
  --principal-arn "$ROLE_ARN" \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
  --access-scope type=cluster >/dev/null

cat <<EOF

Listo. Configura estos GitHub Secrets en ${GH_REPO}:
  AWS_ROLE_ARN                  = ${ROLE_ARN}
  DEVOPS_AGENT_WEBHOOK_URL      = (del Agent Space)
  DEVOPS_AGENT_WEBHOOK_SECRET   = (del Agent Space)
EOF
