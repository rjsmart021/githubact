terraform {
  backend "s3" {
    bucket = "my-terraform-tfstates"
    key    = "terraform.tfstate"
    region = "us-east-2"
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.74.3"
    }
  }

  required_version = ">= 0.14.9"
}


variable "key_name" {
  default = "aws_key"
  type    = string
}


provider "aws" {
  #profile = "default"
  region = "us-east-2"
}

resource "tls_private_key" "key" {
  algorithm = "ED25519"
}

resource "aws_key_pair" "generated_key" {
  key_name   = var.key_name
  public_key = tls_private_key.key.public_key_openssh
  provisioner "local-exec" {
    command = "echo '${tls_private_key.key.private_key_pem}' > C:/Users/алексей/Desktop/myKey.pem"
  }
}


resource "aws_instance" "server" {
  ami                    = "ami-0eea504f45ef7a8f7"
  availability_zone      = "us-east-2c"
  instance_type          = "t2.micro"
  vpc_security_group_ids = [aws_security_group.mywebserver.id]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = self.public_ip
    private_key = tls_private_key.key.private_key_pem
  }

  user_data = file("userdata.sh")

  key_name = var.key_name

  tags = {
    Name = "server"
  }
}


resource "aws_default_vpc" "default" {
  tags = {
    name = "Default_VPC"
  }
}

resource "aws_security_group" "mywebserver" {
  name        = "webserver security group"
  description = "Allow all inbound traffic"
  vpc_id      = aws_default_vpc.default.id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "all"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }


}

data "aws_subnet_ids" "subnet" {
  vpc_id = aws_default_vpc.default.id
}

resource "aws_lb_target_group" "target_group" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  name        = "tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_default_vpc.default.id
}

resource "aws_lb" "aws_alb" {
  name     = "my-aws-alb"
  internal = false
  security_groups = [
    "${aws_security_group.mywebserver.id}",
  ]
  subnets = data.aws_subnet_ids.subnet.ids
  tags = {
    name = "alb"
  }
  ip_address_type    = "ipv4"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "lb_listener_http" {
  load_balancer_arn = aws_lb.aws_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
     type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "lb_listener_https" {
  load_balancer_arn = aws_lb.aws_alb.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = aws_acm_certificate.acm_certificate.arn
  default_action {
    target_group_arn = aws_lb_target_group.target_group.arn
    type             = "forward"
  }
}

resource "aws_alb_target_group_attachment" "ec-2_attach" {
  count            = length(aws_instance.server)
  target_group_arn = aws_lb_target_group.target_group.arn
  target_id        = aws_instance.server.id
}


resource "aws_acm_certificate" "acm_certificate" {
  domain_name       = "dribble-getup.online"
  validation_method = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

data "aws_route53_zone" "private_zone" {
  name = "dribble-getup.online"
  private_zone = false

}


resource "aws_route53_record" "cert-validations" {
  count = length(aws_acm_certificate.acm_certificate.domain_validation_options)

  zone_id = data.aws_route53_zone.private_zone.zone_id
  name    = element(aws_acm_certificate.acm_certificate.domain_validation_options.*.resource_record_name, count.index)
  type    = element(aws_acm_certificate.acm_certificate.domain_validation_options.*.resource_record_type, count.index)
  records = [element(aws_acm_certificate.acm_certificate.domain_validation_options.*.resource_record_value, count.index)]
  ttl     = 60
}

resource "aws_route53_record" "attach_lb" {
  zone_id = data.aws_route53_zone.private_zone.zone_id
  name    = "dribble-getup.online"
  type    = "A"
  alias {
    name                   = aws_lb.aws_alb.dns_name
    zone_id                = aws_lb.aws_alb.zone_id
    evaluate_target_health = true
  }
}


resource "aws_acm_certificate_validation" "acm_certificate_validation" {
  certificate_arn = aws_acm_certificate.acm_certificate.arn
  validation_record_fqdns = aws_route53_record.cert-validations.*.fqdn
}
output "private_key" {
  value     = tls_private_key.key.private_key_pem
  sensitive = true
}
