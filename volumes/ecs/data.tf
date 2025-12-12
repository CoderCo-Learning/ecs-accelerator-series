data "aws_subnet" "ecs_subnet" {
  id = tolist(data.aws_ecs_service.existing.network_configuration[0].subnets)[0]
}

data "aws_vpc" "main" {
  id = data.aws_subnet.ecs_subnet.vpc_id
}

data "aws_subnets" "all" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main.id]
  }
}

data "aws_ecs_cluster" "existing" {
  cluster_name = "scfdemo-dev"
}

data "aws_ecs_service" "existing" {
  service_name = "scfdemo-dev-api"
  cluster_arn  = data.aws_ecs_cluster.existing.arn
}

data "aws_ecs_task_definition" "existing" {
  task_definition = data.aws_ecs_service.existing.task_definition
}

data "aws_security_group" "ecs_tasks" {
  id = tolist(data.aws_ecs_service.existing.network_configuration[0].security_groups)[0]
}