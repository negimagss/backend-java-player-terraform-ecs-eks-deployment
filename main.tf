terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  default = "us-east-2"
}

variable "app_name" {
  default = "player-service"
}

######### NETWORKING #########

data "aws_availability_zones" "available" {}

resource "aws_vpc" "player_service_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.app_name}-vpc"
  }
}

resource "aws_internet_gateway" "player_service_igw" {
  vpc_id = aws_vpc.player_service_vpc.id

  tags = {
    Name = "${var.app_name}-igw"
  }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.player_service_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.player_service_vpc.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.app_name}-public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.player_service_vpc.id
  cidr_block        = cidrsubnet(aws_vpc.player_service_vpc.cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.app_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.player_service_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.player_service_igw.id
  }

  tags = {
    Name = "${var.app_name}-public-rt"
  }
}

resource "aws_route_table_association" "public_assoc" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  count = 1
  vpc   = true
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id

  tags = {
    Name = "${var.app_name}-nat"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.player_service_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = {
    Name = "${var.app_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_assoc" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

######### ECR #########

resource "aws_ecr_repository" "player_service" {
  name = var.app_name

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }
}

######### IAM ROLES #########

data "aws_iam_policy_document" "ecs_task_execution_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "ecs_task_execution_role" {
  name               = "${var.app_name}-ecs-task-execution-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_execution_assume_role.json
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["codebuild.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "codebuild_role" {
  name               = "${var.app_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_role_policy_attachment" "codebuild_ecr" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

resource "aws_iam_role_policy_attachment" "codebuild_s3" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "codebuild_cloudwatch" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}
######### CLOUDWATCH LOG GROUP #########

resource "aws_cloudwatch_log_group" "player_service" {
  name              = "/ecs/${var.app_name}"
  retention_in_days = 7
}

######### CODEBUILD #########

resource "aws_codebuild_project" "player_service_build" {
  name         = "${var.app_name}-build"
  service_role = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_MEDIUM"
    image           = "aws/codebuild/standard:6.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "REPOSITORY_URI"
      value = aws_ecr_repository.player_service.repository_url
    }
  }

  source {
    type            = "GITHUB"
    location        = "https://github.com/negimagss/backend-java-player-service.git"
    git_clone_depth = 1
    buildspec       = <<EOF
version: 0.2

phases:
  pre_build:
    commands:
      - echo Logging in to Amazon ECR...
      - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $REPOSITORY_URI
  build:
    commands:
      - echo Build started on `date`
      - ./mvnw clean package -DskipTests
      - docker build -t $REPOSITORY_URI:latest .
  post_build:
    commands:
      - echo Build completed on `date`
      - docker push $REPOSITORY_URI:latest
EOF
  }
}

######### SECURITY GROUPS #########

resource "aws_security_group" "alb_sg" {
  name        = "${var.app_name}-alb-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.player_service_vpc.id

  ingress {
    description = "Allow HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-alb-sg"
  }
}

resource "aws_security_group" "ecs_sg" {
  name        = "${var.app_name}-ecs-sg"
  description = "Allow inbound from ALB"
  vpc_id      = aws_vpc.player_service_vpc.id

  ingress {
    description     = "Allow traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.app_name}-ecs-sg"
  }
}

######### ECS CLUSTER #########

resource "aws_ecs_cluster" "player_service_cluster" {
  name = "${var.app_name}-cluster"
}

######### ECS TASK DEFINITION #########

resource "aws_ecs_task_definition" "player_service_task" {
  family                   = "${var.app_name}-task"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "512"
  memory                   = "1024"
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([
    {
      name      = "player-service"
      image     = "${aws_ecr_repository.player_service.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "OLLAMA_HOST"
          value = "http://localhost:11434"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.app_name}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "player-service"
        }
      }
    },
    {
      name      = "ollama"
      image     = "ollama/ollama"
      essential = true
      portMappings = [
        {
          containerPort = 11434
          protocol      = "tcp"
        }
      ]
      mountPoints = [
        {
          sourceVolume  = "ollama-data"
          containerPath = "/root/.ollama"
          readOnly      = false
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/${var.app_name}"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ollama"
        }
      }
    }
  ])

  volume {
    name = "ollama-data"
  }
}

######### ECS SERVICE #########

resource "aws_ecs_service" "player_service" {
  name            = "${var.app_name}-service"
  cluster         = aws_ecs_cluster.player_service_cluster.id
  task_definition = aws_ecs_task_definition.player_service_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    subnets         = aws_subnet.private[*].id
    security_groups = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.player_service_tg.arn
    container_name   = "player-service"
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.player_service_listener]
}

######### ALB #########

resource "aws_lb" "player_service_alb" {
  name               = "${var.app_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
}

resource "aws_lb_target_group" "player_service_tg" {
  name        = "${var.app_name}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.player_service_vpc.id
  target_type = "ip"

  health_check {
    path                = "/v1/players"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "player_service_listener" {
  load_balancer_arn = aws_lb.player_service_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.player_service_tg.arn
  }
}

######### OUTPUTS #########

output "alb_dns_name" {
  description = "The DNS name of the ALB"
  value       = aws_lb.player_service_alb.dns_name
}

output "ecr_repository_url" {
  description = "ECR repository URL for player service docker image"
  value       = aws_ecr_repository.player_service.repository_url
}

output "ecs_cluster_name" {
  description = "ECS cluster name"
  value       = aws_ecs_cluster.player_service_cluster.name
}

output "ecs_service_name" {
  description = "ECS service name"
  value       = aws_ecs_service.player_service.name
}

output "codebuild_project_name" {
  description = "CodeBuild project name"
  value       = aws_codebuild_project.player_service_build.name
}

