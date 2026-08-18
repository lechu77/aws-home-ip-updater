#!/bin/bash

set -euo pipefail

# ------------------------------------------------------------------------------
# update-home-ip.sh
# Updates the SG rule whose Description field starts with the given name.
# Usage: ./update-home-ip.sh <NAME>
# ------------------------------------------------------------------------------
# ------------------------------------------------------------------------------
# Configuration (Modify these to match your environment)
# ------------------------------------------------------------------------------
SG_ID=${AWS_SG_ID:-"sg-xxxxxxxxxxxxxxxxx"}
REGION=${AWS_REGION:-"us-east-1"}
# Comma-separated list of valid names
VALID_NAMES_STR=${VALID_NAMES:-"ALICE,BOB,CHARLIE"}
IFS=',' read -r -a VALID_NAMES <<< "$VALID_NAMES_STR"

# --- Validate parameter ---
if [ $# -ne 1 ]; then
  echo "Usage: $0 <NAME>"
  echo "Valid names: ${VALID_NAMES[*]}"
  exit 1
fi

NAME=$(echo "$1" | tr '[:lower:]' '[:upper:]')  # convert to uppercase

VALID=false
for n in "${VALID_NAMES[@]}"; do
  if [ "$NAME" = "$n" ]; then
    VALID=true
    break
  fi
done

if [ "$VALID" = false ]; then
  echo "Error: '$NAME' is not a valid name."
  echo "Valid names: ${VALID_NAMES[*]}"
  echo "You can override valid names using the VALID_NAMES environment variable (comma separated)."
  exit 1
fi

# --- Resolve AWS credentials ---
AWS_PROFILE_OPT=""

if [ -n "${AWS_PROFILE:-}" ]; then
  echo "Using profile from AWS_PROFILE env var: ${AWS_PROFILE}"
  AWS_PROFILE_OPT="--profile ${AWS_PROFILE}"
elif [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  echo "No AWS credentials found in environment variables (AWS_ACCESS_KEY_ID not set)."

  # List available profiles
  PROFILES=()
  if [ -f "$HOME/.aws/credentials" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^\[(.+)\]$ ]]; then
        PROFILES+=("${BASH_REMATCH[1]}")
      fi
    done < "$HOME/.aws/credentials"
  fi
  if [ -f "$HOME/.aws/config" ]; then
    while IFS= read -r line; do
      if [[ "$line" =~ ^\[profile\ (.+)\]$ ]]; then
        PROFILES+=("${BASH_REMATCH[1]}")
      fi
    done < "$HOME/.aws/config"
  fi

  # Deduplicate
  PROFILES=($(printf '%s\n' "${PROFILES[@]}" | sort -u))

  if [ ${#PROFILES[@]} -eq 0 ]; then
    echo "Error: no AWS profiles found in ~/.aws/credentials or ~/.aws/config."
    echo "Please configure your credentials with 'aws configure' or set AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
    exit 1
  fi

  echo ""
  echo "Available AWS profiles:"
  for i in "${!PROFILES[@]}"; do
    echo "  [$((i+1))] ${PROFILES[$i]}"
  done

  echo ""
  read -rp "Select a profile (number or name): " PROFILE_INPUT

  # Accept number or name
  if [[ "$PROFILE_INPUT" =~ ^[0-9]+$ ]]; then
    INDEX=$((PROFILE_INPUT - 1))
    if [ "$INDEX" -lt 0 ] || [ "$INDEX" -ge ${#PROFILES[@]} ]; then
      echo "Error: invalid selection."
      exit 1
    fi
    SELECTED_PROFILE="${PROFILES[$INDEX]}"
  else
    SELECTED_PROFILE="$PROFILE_INPUT"
  fi

  echo "Using profile: ${SELECTED_PROFILE}"
  AWS_PROFILE_OPT="--profile ${SELECTED_PROFILE}"
else
  echo "Using credentials from environment variables."
fi

# --- Get public IP ---
echo "Fetching public IP..."
MY_IP=$(curl -s https://ip.me)

if [ -z "$MY_IP" ]; then
  echo "Error: could not retrieve public IP."
  exit 1
fi

echo "Public IP: ${MY_IP}"

# --- Fetch all ingress rules for the SG (no jq, pure aws cli) ---
echo "Looking for rule with Description starting with '${NAME}'..."

# Retrieve rules as TSV: RuleId | Protocol | FromPort | ToPort | CidrIpv4 | Description | IsEgress
RULES_TSV=$(aws ec2 describe-security-group-rules \
  $AWS_PROFILE_OPT \
  --filters "Name=group-id,Values=${SG_ID}" \
  --region "${REGION}" \
  --query 'SecurityGroupRules[?IsEgress==`false`].[SecurityGroupRuleId,IpProtocol,FromPort,ToPort,CidrIpv4,Description]' \
  --output text)

if [ -z "$RULES_TSV" ]; then
  echo "Error: no ingress rules found for SG ${SG_ID}."
  exit 1
fi

RULE_ID=""
PROTOCOL=""
FROM_PORT=""
TO_PORT=""
CURRENT_IP=""
DESCRIPTION=""

while IFS=$'\t' read -r rid proto from to cidr desc; do
  DESC_UPPER=$(echo "$desc" | tr '[:lower:]' '[:upper:]')
  if [[ "$DESC_UPPER" == "${NAME}"* ]]; then
    RULE_ID="$rid"
    PROTOCOL="$proto"
    FROM_PORT="$from"
    TO_PORT="$to"
    CURRENT_IP="$cidr"
    DESCRIPTION="$desc"
    break
  fi
done <<< "$RULES_TSV"

if [ -z "$RULE_ID" ]; then
  echo "Error: no rule found with Description starting with '${NAME}'."
  exit 1
fi

echo "Rule ID     : ${RULE_ID}"
echo "Description : ${DESCRIPTION}"
echo "Current IP  : ${CURRENT_IP}"
echo "New IP      : ${MY_IP}/32"

if [ "${CURRENT_IP}" = "${MY_IP}/32" ]; then
  echo "IP is already up to date. No changes needed."
  exit 0
fi

# --- Update the rule ---
echo "Updating rule..."

aws ec2 modify-security-group-rules \
  $AWS_PROFILE_OPT \
  --group-id "${SG_ID}" \
  --region "${REGION}" \
  --security-group-rules "[{\"SecurityGroupRuleId\":\"${RULE_ID}\",\"SecurityGroupRule\":{\"IpProtocol\":\"${PROTOCOL}\",\"FromPort\":${FROM_PORT},\"ToPort\":${TO_PORT},\"CidrIpv4\":\"${MY_IP}/32\",\"Description\":\"${DESCRIPTION}\"}}]"

echo "Done. Rule ${RULE_ID} updated: ${CURRENT_IP} → ${MY_IP}/32"
