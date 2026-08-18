# AWS Home IP Updater

A simple, dependency-free bash script that allows team members to securely update their home IP addresses in an AWS Security Group rule without requiring full EC2/VPC admin permissions.

## Features
- **Zero Dependencies**: Requires only `curl` and `aws-cli`.
- **Self-Service**: Developers can run it locally whenever their dynamic home IP changes.
- **Secure**: Designed to work with least-privilege IAM policies.

## Setup

### 1. Configuration
Modify the script or use environment variables to point it to your specific AWS environment:

```bash
export AWS_SG_ID="sg-0123456789abcdef0"
export AWS_REGION="us-east-1"
export VALID_NAMES="ALICE,BOB,CHARLIE"
```

### 2. IAM Policy
Your users should have an IAM policy that allows them to modify only the specified rules. See `example-iam-policy.json` for a least-privilege example.

## Usage

Run the script by passing your assigned name. Your name must match the beginning of the `Description` field on your specific Security Group rule.

```bash
chmod +x update-home-ip.sh
./update-home-ip.sh ALICE
```

### AWS Profile Selection
The script will auto-detect your AWS credentials. If you have multiple profiles configured in `~/.aws/credentials`, it will interactively ask you which one to use. Alternatively, you can bypass the prompt by exporting it:

```bash
AWS_PROFILE=my-profile ./update-home-ip.sh BOB
```
