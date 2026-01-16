## Lab 

We will:

- create an ECR repo

- build and tag images properly

- push immutable + mutable tags

- understand promotion mechanics

## prepare for ECS usage

Step 1 – Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name my-app \
  --region eu-west-2
```

Verify:

`aws ecr describe-repositories`

## Step 2 – Authenticate Docker to ECR

```bash
aws ecr get-login-password \
  --region eu-west-2 \
| docker login \
  --username AWS \
  --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com
```

Explain:

- short-lived auth
- IAM-controlled
- no static creds

## Step 3 – Build Image (Once)

```bash
GIT_SHA=$(git rev-parse --short HEAD)

docker build \
  -t my-app:$GIT_SHA \
  .
```

- No env-specific builds.
- No “prod Dockerfile”.

## Step 4 – Tag for ECR + Environment

```bash
docker tag my-app:$GIT_SHA \
  <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:$GIT_SHA

docker tag my-app:$GIT_SHA \
  <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:dev
```

So we have:s

- SHA = immutable
- dev = pointer

## Step 5 – Push to ECR

```bash
docker push <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:$GIT_SHA
docker push <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:dev
```

Confirm in AWS console.

## Step 6 – Simulate Promotion (No Rebuild)

```bash
docker tag \
  <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:$GIT_SHA \
  <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:prod

docker push <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com/my-app:prod
```

- “Same image. New function or app change.”

## Step 7 – Add Lifecycle Policy (Mandatory)

Policy example:

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Expire untagged images",
      "selection": {
        "tagStatus": "untagged",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
```

```bash
## create policy.json and include above policy

aws ecr put-lifecycle-policy \
  --repository-name my-app \
  --lifecycle-policy-text file://policy.json
```

### Or via TF

```go
resource "aws_ecr_repository" "app" {
  name = "my-app"
}

resource "aws_ecr_lifecycle_policy" "app" {
  repository = aws_ecr_repository.app.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images"
        selection = {
          tagStatus     = "untagged"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

```