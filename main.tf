provider "aws" {
  region = var.aws_region
}

# VPC
resource "aws_vpc" "ecs_vpc" {
  cidr_block           = var.vpc_cidr
  instance_tenancy = var.instance_tenancy
  enable_dns_hostnames = var.enable_dns_hostname
  enable_dns_support = var.enable_dns_support

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

# Public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  count                   = length(var.public_subnets_cidr)
  cidr_block              = element(var.public_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.environment}" 
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id                  = aws_vpc.ecs_vpc.id
  count                   = length(var.private_subnets_cidr)
  cidr_block              = element(var.private_subnets_cidr, count.index)
  availability_zone       = element(var.availability_zones, count.index)
  map_public_ip_on_launch = false

  tags = {
    Name        = "${var.environment}"
  }
}

#Internet gateway
resource "aws_internet_gateway" "pro-igw" {
  vpc_id = aws_vpc.ecs_vpc.id
  tags = {
    "Name"        = "${var.environment}-igw"
    "Environment" = "${var.environment}"
  }
}


# Routing tables to route traffic for Private Subnet
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.ecs_vpc.id
  tags = {
    Name        = "${var.environment}-private-route-table"
    Environment = "${var.environment}"
  }
}

# Routing tables to route traffic for Public Subnet
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ecs_vpc.id

  tags = {
    Name        = "${var.environment}-public-route-table"
    Environment = "${var.environment}"
  }
}

# Route for Internet Gateway
resource "aws_route" "public_internet_gateway" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.pro-igw.id
}



# Route table associations for both Public & Private Subnets
resource "aws_route_table_association" "public" {
  count          = length(var.public_subnets_cidr)
  subnet_id      = element(aws_subnet.public_subnet.*.id, count.index)
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(var.private_subnets_cidr)
  subnet_id      = element(aws_subnet.private_subnet.*.id, count.index)
  route_table_id = aws_route_table.private.id
}

# ECS CLUSTER
resource "aws_ecs_cluster" "cluster" {
  name = "ecs_cluster"
}

resource "aws_ecs_cluster_capacity_providers" "terraformecs" {
  cluster_name = aws_ecs_cluster.cluster.id

  capacity_providers = ["FARGATE"]

  default_capacity_provider_strategy {
    base              = 1
    weight            = 100
    capacity_provider = "FARGATE"
  }
}

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecs-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "ecs-tasks.amazonaws.com",
        },
      },
    ],
  })
}

 resource "aws_ecs_task_definition" "ecs_task" {
  family = "ecs"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu = "256"
  memory = "512"

execution_role_arn = aws_iam_role.ecs_execution_role.arn


  container_definitions = jsonencode([
    {
      name      = "nginxpro"
      image     = "nginx"
      cpu       = 10
      memory    = 512
      essential = true
      portMappings = [
        {
          containerPort = 80
          hostPort      = 80
        }
      ]
    },
   
  ])

}


resource "aws_db_instance" "my_database" {
identifier= "my-db-instance"
allocated_storage= 20
storage_type= "gp2"
engine= "mysql"
engine_version= "5.7"
instance_class= "db.t2.micro"
username= "adminecs"
password= "adminadmin12"
parameter_group_name= "default.mysql5.7"
publicly_accessible= true
multi_az= false
backup_retention_period = 7
skip_final_snapshot= true

tags = {
Name = "MyDatabase"
}
}

resource "aws_security_group" "alb_sg" {
name= "alb_sg"
description = "Security group for ALB"
vpc_id= aws_vpc.ecs_vpc.id

ingress {
from_port= 80
to_port= 80
protocol= "tcp"
cidr_blocks = ["0.0.0.0/0"]
ipv6_cidr_blocks = ["::/0"]
}

ingress {
from_port= 80
to_port= 80
protocol= "tcp"
cidr_blocks = ["0.0.0.0/0"]
ipv6_cidr_blocks = ["::/0"]
}

egress {
from_port= 0
to_port= 0
protocol= "-1"
cidr_blocks = ["0.0.0.0/0"]
ipv6_cidr_blocks = ["::/0"]
}

tags = {
Name = "alb-sg"
}
 }

# Traffic to the ECS cluster should only come from the ALB
resource "aws_security_group" "ecs_tasks" {
  name        = "ecs-tasks"
  description = "allow inbound access from the ALB only"
  vpc_id      = aws_vpc.ecs_vpc.id

  ingress {
    protocol        = "tcp"
    from_port       = 80
    to_port         = 80
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

resource "aws_alb" "ecs_alb" {
 name= "ecs-alb"
 internal= false
 load_balancer_type = "application"
 security_groups= [aws_security_group.alb_sg.id]

 enable_deletion_protection = false

 subnets = (aws_subnet.public_subnet.*.id)

 enable_http2= true
 idle_timeout= 60

 enable_cross_zone_load_balancing = true

 tags = {
 Name = "ecs-alc"
 }
 }


# Redirect all traffic from the ALB to the target group
resource "aws_alb_listener" "front_end" {
  load_balancer_arn = aws_alb.ecs_alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    target_group_arn = aws_alb_target_group.ecs_alb_tg.arn
    type             = "forward"
  }
}


 resource "aws_alb_target_group" "ecs_alb_tg" {
 name= "ecs-alb-tg"
 port= 80
 protocol= "HTTP"
 vpc_id= aws_vpc.ecs_vpc.id
 target_type = "ip"

health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "200"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }

 }

resource "aws_ecs_service" "ecs_alb_service" {
 name= "ecs-alb-service"
 cluster= aws_ecs_cluster.cluster.id
 task_definition = aws_ecs_task_definition.ecs_task.arn
 launch_type= "FARGATE"
 desired_count= 1

network_configuration {
 subnets        = (aws_subnet.public_subnet.*.id)
 security_groups = [aws_security_group.alb_sg.id]
  assign_public_ip = true 
 }

load_balancer {
    target_group_arn = aws_alb_target_group.ecs_alb_tg.arn
    container_name   = "nginxpro"
    container_port   = 80
  }

 depends_on = [aws_alb_listener.front_end]

}


output "alb_hostname" {
  value = aws_alb.ecs_alb.dns_name
}


