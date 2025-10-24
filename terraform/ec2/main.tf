provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "ryandevlab-bucket"
    key    = "ec2/rhel9-instance.tfstate"
    region = "us-east-1"
  }
}

data "aws_security_group" "ryan_sg" {
  name = "ryan-dev-sg"
}

resource "aws_instance" "rhel9_ec2" {
  ami                    = "ami-0dfc569a8686b9320"
  instance_type          = "t2.medium"
  key_name               = "ryan-key"
  iam_instance_profile   = "ryan_dev_lab_instance_role"
  vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

  tags = {
    Name = "RHEL9-EC2"
  }
}