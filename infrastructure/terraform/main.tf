locals {
  name = "${var.project_name}-${var.environment}"
  services = {
    frontend = { port = 3000, health_path = "/api/health" }
    backend  = { port = 4000, health_path = "/api/health" }
    payment  = { port = 4200, health_path = "/health" }
    cart     = { port = 4300, health_path = "/health" }
    product  = { port = 4500, health_path = "/health" }
    api      = { port = 4600, health_path = "/health" }
    search   = { port = 5000, health_path = "/health" }
  }
  catalog_seed = {
    "1" = { name = "Laptop Pro", description = "High-performance laptop", price = 1299.99, stock = 50, category = "electronics" }
    "2" = { name = "Wireless Mouse", description = "Ergonomic wireless mouse", price = 29.99, stock = 200, category = "accessories" }
    "3" = { name = "USB-C Hub", description = "7-in-1 USB-C hub", price = 49.99, stock = 150, category = "accessories" }
    "4" = { name = "Monitor 27-inch", description = "4K IPS monitor", price = 399.99, stock = 75, category = "electronics" }
    "5" = { name = "Mechanical Keyboard", description = "RGB mechanical keyboard", price = 89.99, stock = 120, category = "accessories" }
  }
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.common_tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = merge(local.common_tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  tags                    = merge(local.common_tags, { Name = "${local.name}-public-${count.index + 1}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = merge(local.common_tags, { Name = "${local.name}-public" })
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "alb" {
  name        = "${local.name}-alb"
  description = "Public HTTP access to the application load balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.allowed_http_cidrs
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${local.name}-alb" })
}

resource "aws_security_group" "ecs" {
  name        = "${local.name}-ecs"
  description = "Only the ALB can reach the public frontend container"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Frontend from ALB"
    from_port       = local.services.frontend.port
    to_port         = local.services.frontend.port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(local.common_tags, { Name = "${local.name}-ecs" })
}

resource "aws_ecr_repository" "service" {
  for_each             = local.services
  name                 = "${var.project_name}/${each.key}"
  image_tag_mutability = "MUTABLE"
  force_delete         = var.allow_repository_force_delete

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
  tags = local.common_tags
}

resource "aws_ecr_lifecycle_policy" "service" {
  for_each   = aws_ecr_repository.service
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the latest 20 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 20
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_cloudwatch_log_group" "service" {
  for_each          = local.services
  name              = "/ecs/${local.name}/${each.key}"
  retention_in_days = var.log_retention_days
  tags              = local.common_tags
}

resource "aws_ecs_cluster" "main" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  tags = local.common_tags
}

resource "aws_dynamodb_table" "products" {
  name         = "${local.name}-products"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }

  point_in_time_recovery {
    enabled = var.enable_database_point_in_time_recovery
  }

  server_side_encryption { enabled = true }
  deletion_protection_enabled = var.enable_database_deletion_protection
  tags                        = local.common_tags
}

resource "aws_dynamodb_table_item" "catalog_seed" {
  for_each   = local.catalog_seed
  table_name = aws_dynamodb_table.products.name
  hash_key   = aws_dynamodb_table.products.hash_key
  item = jsonencode({
    id          = { S = each.key }
    name        = { S = each.value.name }
    description = { S = each.value.description }
    price       = { N = tostring(each.value.price) }
    stock       = { N = tostring(each.value.stock) }
    category    = { S = each.value.category }
  })
}

resource "aws_iam_role" "ecs_execution" {
  name = "${local.name}-ecs-execution"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role" "ecs_task" {
  name = "${local.name}-ecs-task"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = local.common_tags
}

resource "aws_iam_role_policy" "ecs_task" {
  name = "TaskRuntimePermissions"
  role = aws_iam_role.ecs_task.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadProductCatalog"
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.products.arn
      },
      {
        Sid    = "EcsExecuteCommand"
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_ecs_task_definition" "app" {
  family                   = local.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    for service_name, config in local.services : {
      name              = service_name
      image             = "${aws_ecr_repository.service[service_name].repository_url}:${var.image_tag}"
      essential         = true
      cpu               = 128
      memoryReservation = 256
      portMappings = [{
        containerPort = config.port
        hostPort      = config.port
        protocol      = "tcp"
      }]
      environment = concat(
        [{ name = "NODE_ENV", value = "production" }, { name = "PORT", value = tostring(config.port) }],
        service_name == "frontend" ? [
          { name = "BACKEND_URL", value = "http://127.0.0.1:4000" },
          { name = "SEARCH_URL", value = "http://127.0.0.1:5000" }
        ] : [],
        service_name == "api" ? [
          { name = "FRONTEND_URL", value = "http://127.0.0.1:3000" },
          { name = "BACKEND_URL", value = "http://127.0.0.1:4000" },
          { name = "PAYMENT_URL", value = "http://127.0.0.1:4200" },
          { name = "CART_URL", value = "http://127.0.0.1:4300" },
          { name = "PRODUCT_URL", value = "http://127.0.0.1:4500" },
          { name = "SEARCH_URL", value = "http://127.0.0.1:5000" }
        ] : [],
        service_name == "product" ? [
          { name = "PRODUCTS_TABLE", value = aws_dynamodb_table.products.name }
        ] : [],
        service_name == "search" ? [
          { name = "PRODUCT_URL", value = "http://127.0.0.1:4500" }
        ] : []
      )
      healthCheck = {
        command     = ["CMD-SHELL", "wget -q --spider http://127.0.0.1:${config.port}${config.health_path} || exit 1"]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 15
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.service[service_name].name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = service_name
        }
      }
    }
  ])
  depends_on = [aws_iam_role_policy.ecs_task]
  tags = local.common_tags
}

resource "aws_lb" "main" {
  name               = substr("${local.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id
  tags               = local.common_tags
}

resource "aws_lb_target_group" "frontend" {
  name        = substr("${local.name}-frontend", 0, 32)
  port        = local.services.frontend.port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = local.services.frontend.health_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }
}

resource "aws_ecs_service" "app" {
  name                               = local.name
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.app.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  platform_version                   = "LATEST"
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  enable_execute_command             = true
  health_check_grace_period_seconds  = 60

  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend.arn
    container_name   = "frontend"
    container_port   = local.services.frontend.port
  }

  depends_on = [aws_lb_listener.http, aws_iam_role_policy_attachment.ecs_execution]

  lifecycle { ignore_changes = [desired_count] }
  tags = local.common_tags
}

resource "aws_appautoscaling_target" "ecs" {
  max_capacity       = var.max_count
  min_capacity       = var.min_count
  resource_id        = "service/${aws_ecs_cluster.main.name}/${aws_ecs_service.app.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.name}-cpu"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs.service_namespace
  target_tracking_scaling_policy_configuration {
    predefined_metric_specification { predefined_metric_type = "ECSServiceAverageCPUUtilization" }
    target_value       = 60
    scale_in_cooldown  = 120
    scale_out_cooldown = 60
  }
}
