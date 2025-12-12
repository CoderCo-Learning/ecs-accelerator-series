# EFS Validation

## Key Concepts

### Why Volumes?

- Containers are **ephemeral** - data lost on restart
- Volumes provide **persistent storage**
- EFS enables **shared** storage across tasks

### EFS vs Other Options

| Feature | EFS | EBS | S3 |
|---------|-----|-----|-----|
| Shared | ✅ Multiple tasks | ❌ Single instance | ✅ API access |
| Performance | Network (slower) | Local (fast) | API (slowest) |
| Use case | Shared configs/uploads | DB data, logs | Object storage |
| Cost | Per GB + transfer | Per GB provisioned | Per GB + requests |

```bash

# once tf is applied

aws ec2 describe-vpc-attribute \
  --region us-east-1 \
  --vpc-id vpc-<> \
  --attribute enableDnsHostnames


then check > http://api.lab.moabukar.co.uk/info and you should see the EFS mounted

# Get ALB URL
ALB_URL=$(aws elbv2 describe-load-balancers \
  --query 'LoadBalancers[?contains(LoadBalancerName, `scfdemo`)].DNSName' \
  --output text)

# Check EFS is mounted
curl http://$ALB_URL/info

# Write from task 1
curl "http://$ALB_URL/write?msg=hello-from-task-1"

# Scale to 2 tasks
aws ecs update-service \
  --cluster scfdemo \
  --service scfdemo-api \
  --desired-count 2

# Wait a bit for second task
sleep 30

# Read from whichever task ALB routes to (might be task 2)
curl http://$ALB_URL/read

# Write from another task
curl "http://$ALB_URL/write?msg=hello-from-task-2"

# Read again – should see both files
curl http://$ALB_URL/read
```

## Endpoints

```bash
# Health check
curl http://api.lab.moabukar.co.uk/health

# Basic hello
curl http://api.lab.moabukar.co.uk/

# Task/EFS info
curl http://api.lab.moabukar.co.uk/info

# Write data
curl "http://api.lab.moabukar.co.uk/write?msg=your-message-here"
curl "http://api.lab.moabukar.co.uk/write?msg=hello-from-task-1"
curl "http://api.lab.moabukar.co.uk/write?msg=hello-from-task-2"
curl "http://api.lab.moabukar.co.uk/write?msg=hello-from-task-3"

# Read all files
curl http://api.lab.moabukar.co.uk/read
```

## Demo flow

```bash
# 1. Show empty EFS
curl http://api.lab.moabukar.co.uk/read

# 2. Write from "user upload"
curl "http://api.lab.moabukar.co.uk/write?msg=user-uploaded-file"

# 3. Show it persists through restart
TASK_ID=$(aws ecs list-tasks --region us-east-1 --cluster scfdemo-dev --service scfdemo-dev-api --query 'taskArns[0]' --output text)
aws ecs stop-task --region us-east-1 --cluster scfdemo-dev --task $TASK_ID
sleep 30
curl http://api.lab.moabukar.co.uk/read  # Still there!

# 4. Scale and show shared
aws ecs update-service --region us-east-1 --cluster scfdemo-dev --service scfdemo-dev-api --desired-count 3
sleep 45

# 5. Show all tasks see same data
for i in {1..10}; do
    curl http://api.lab.moabukar.co.uk/info | grep "Task ID"
done

curl http://api.lab.moabukar.co.uk/read  # All files visible from all tasks
```

## Exec into and check EFS mount


SSM Perm to ECS Task role::

```json
## Add SSM perm:

```json
{
	"Version": "2012-10-17",
	"Statement": [
		{
			"Effect": "Allow",
			"Action": [
				"ssmmessages:CreateControlChannel",
				"ssmmessages:CreateDataChannel",
				"ssmmessages:OpenControlChannel",
				"ssmmessages:OpenDataChannel"
			],
			"Resource": "*"
		}
	]
}
```

### ECS Exec

```bash
# enable exec command
aws ecs update-service \
  --cluster scfdemo-dev \
  --service scfdemo-dev-api \
  --enable-execute-command \
  --region us-east-1

aws ecs update-service \
  --cluster scfdemo-dev \
  --service scfdemo-dev-api \
  --force-new-deployment \
  --region us-east-1

# exec into running task
aws ecs execute-command \
  --cluster scfdemo-dev \
  --task 6a9b4afa048142199e759958136ae24c \
  --container scfdemo-dev-api \
  --interactive \
  --command "/bin/sh" \
  --region us-east-1

aws ecs execute-command \
  --cluster scfdemo-dev \
  --task de14cf5124ea4131bc2353424008a649 \
  --container scfdemo-dev-api \
  --interactive \
  --command "/bin/sh" \
  --region us-east-1

# inside container, check EFS mount
mkdir -p /mnt/efs/uploads
ls -la /mnt/efs
echo "test" > /mnt/efs/test.txt
cat /mnt/efs/test.txt

# Exec into different task
cat /mnt/efs/test.txt  # Should see "test" from first task
```