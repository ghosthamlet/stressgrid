variable "region" {
  type = "string"
}

variable "vpc_id" {
  type = "string"
}

variable "key_name" {
  type = "string"
}

variable "capacity" {
  type = "string"
}

provider "aws" {
  region = "${var.region}"
}

data "aws_ami" "coordinator" {
  most_recent = true
  name_regex  = "^stressgrid-coordinator-.*"
  owners      = ["198789150561"]
}

data "aws_ami" "generator" {
  most_recent = true
  name_regex  = "^stressgrid-generator-.*"
  owners      = ["198789150561"]
}

data "template_file" "coordinator_init" {
  template = "${file("${path.module}/coordinator_init.sh")}"

  vars {
    region = "${var.region}"
  }
}

data "template_file" "generator_init" {
  template = "${file("${path.module}/generator_init.sh")}"

  vars {
    coordinator_dns = "${aws_instance.coordinator.private_dns}"
  }
}

data "aws_subnet_ids" "subnets" {
  vpc_id = "${var.vpc_id}"
}

resource "aws_security_group" "coordinator" {
  name   = "stressgrid-coordinator"
  vpc_id = "${var.vpc_id}"

  ingress {
    from_port   = 8000
    to_port     = 8000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 9696
    to_port         = 9696
    protocol        = "tcp"
    security_groups = ["${aws_security_group.generator.id}"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "generator" {
  name   = "stressgrid-generator"
  vpc_id = "${var.vpc_id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "coordinator_cloudwatch" {
  statement {
    actions   = ["cloudwatch:PutMetricData"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "coordinator_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "coordinator" {
  name               = "stressgrid-coordinator"
  assume_role_policy = "${data.aws_iam_policy_document.coordinator_assume_role.json}"
}

resource "aws_iam_role_policy" "coordinator_cloudwatch" {
  name   = "stressgrid-coordinator-cloudwatch"
  role   = "${aws_iam_role.coordinator.id}"
  policy = "${data.aws_iam_policy_document.coordinator_cloudwatch.json}"
}

resource "aws_iam_instance_profile" "coordinator" {
  name = "stressgrid-coordinator"
  role = "${aws_iam_role.coordinator.name}"
}

resource "aws_instance" "coordinator" {
  ami                         = "${data.aws_ami.coordinator.id}"
  instance_type               = "t2.micro"
  key_name                    = "${var.key_name}"
  user_data                   = "${data.template_file.coordinator_init.rendered}"
  iam_instance_profile        = "${aws_iam_instance_profile.coordinator.id}"
  security_groups             = ["${aws_security_group.coordinator.id}"]
  associate_public_ip_address = true
  subnet_id                   = "${data.aws_subnet_ids.subnets.ids[0]}"

  tags {
    Name = "stressgrid-coordinator"
  }
}

output "coordinator_url" {
  value = "http://${aws_instance.coordinator.public_dns}:8000"
}

resource "aws_launch_configuration" "generator" {
  name                        = "stressgrid-generator"
  image_id                    = "${data.aws_ami.generator.id}"
  instance_type               = "c5.2xlarge"
  key_name                    = "${var.key_name}"
  user_data                   = "${data.template_file.generator_init.rendered}"
  security_groups             = ["${aws_security_group.generator.id}"]
  associate_public_ip_address = false
}

resource "aws_autoscaling_group" "generator" {
  name                 = "stressgrid-generator"
  launch_configuration = "${aws_launch_configuration.generator.name}"
  min_size             = 0
  max_size             = "${var.capacity}"
  desired_capacity     = "${var.capacity}"
  vpc_zone_identifier  = ["${data.aws_subnet_ids.subnets.ids}"]

  lifecycle {
    create_before_destroy = true
  }

  tag {
    key                 = "Name"
    value               = "stressgrid-generator"
    propagate_at_launch = true
  }
}
