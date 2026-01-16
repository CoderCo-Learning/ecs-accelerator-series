## enable DNS hostnames and support for EFS - hacky way...but for demo purposes

resource "null_resource" "enable_vpc_dns" {
  triggers = {
    vpc_id = data.aws_vpc.main.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws ec2 modify-vpc-attribute \
        --region us-east-1 \
        --vpc-id ${data.aws_vpc.main.id} \
        --enable-dns-hostnames "{\"Value\":true}"
      
      aws ec2 modify-vpc-attribute \
        --region us-east-1 \
        --vpc-id ${data.aws_vpc.main.id} \
        --enable-dns-support "{\"Value\":true}"
    EOT
  }
  depends_on = [data.aws_vpc.main]
}

resource "aws_efs_file_system" "app_efs" {
  creation_token = "scfdemo-efs"
  encrypted      = true

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }

  depends_on = [null_resource.enable_vpc_dns]

  tags = {
    Name = "scfdemo-efs"
  }
}

resource "aws_efs_mount_target" "app_efs_mount" {
  count = length(data.aws_ecs_service.existing.network_configuration[0].subnets)

  file_system_id  = aws_efs_file_system.app_efs.id
  subnet_id       = tolist(data.aws_ecs_service.existing.network_configuration[0].subnets)[count.index]
  security_groups = [aws_security_group.efs_sg.id]

  # depends_on = [
  #   aws_vpc_attribute.enable_dns_hostnames,
  #   aws_vpc_attribute.enable_dns_support
  # ]
}

resource "aws_security_group" "efs_sg" {
  name        = "scfdemo-efs-sg"
  description = "Allow NFS from ECS tasks"
  vpc_id      = data.aws_vpc.main.id

  ingress {
    description     = "NFS from ECS"
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [data.aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "scfdemo-efs-sg"
  }
}

# modify existing task definition to add EFS volume
resource "aws_ecs_task_definition" "app_with_efs" {
  family                   = data.aws_ecs_task_definition.existing.family
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = data.aws_ecs_task_definition.existing.cpu
  memory                   = data.aws_ecs_task_definition.existing.memory
  execution_role_arn       = data.aws_ecs_task_definition.existing.execution_role_arn
  task_role_arn            = data.aws_ecs_task_definition.existing.task_role_arn

  container_definitions = jsonencode([
    merge(
      jsondecode(data.aws_ecs_task_definition.existing.container_definitions)[0],
      {
        linuxParameters = {
          initProcessEnabled = true
        }
        mountPoints = [
          {
            sourceVolume  = "efs-storage"
            containerPath = "/mnt/efs"
            readOnly      = false
          }
        ]
      }
    )
  ])

  volume {
    name = "efs-storage"

    efs_volume_configuration {
      file_system_id     = aws_efs_file_system.app_efs.id
      transit_encryption = "ENABLED"
    }
  }

  depends_on = [aws_efs_mount_target.app_efs_mount]
}

resource "null_resource" "update_service" {
  triggers = {
    task_definition = aws_ecs_task_definition.app_with_efs.arn
    timestamp       = timestamp() # Forces run every time
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for EFS mount targets to be available..."
      
      # Wait for all mount targets to be available
      for i in {1..30}; do
        STATUS=$(aws efs describe-mount-targets \
          --file-system-id ${aws_efs_file_system.app_efs.id} \
          --region us-east-1 \
          --query "MountTargets[?LifeCycleState!='available'] | length(@)")
        
        if [ "$STATUS" == "0" ]; then
          echo "All mount targets available"
          break
        fi
        
        echo "Waiting for mount targets... ($i/30)"
        sleep 10
      done
      
      aws ecs update-service \
        --region us-east-1 \
        --cluster ${data.aws_ecs_cluster.existing.cluster_name} \
        --service ${data.aws_ecs_service.existing.service_name} \
        --task-definition ${aws_ecs_task_definition.app_with_efs.arn} \
        --enable-execute-command \
        --force-new-deployment
    EOT
  }

  depends_on = [
    aws_ecs_task_definition.app_with_efs,
    aws_efs_mount_target.app_efs_mount
  ]
}
