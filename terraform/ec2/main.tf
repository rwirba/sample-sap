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

resource "aws_instance" "rhel_demo1" {
  ami                    = "ami-0dfc569a8686b9320"  # RHEL 9 AMI
  instance_type          = "t2.medium"
  key_name               = "ryan-key"
  iam_instance_profile   = "ryan_dev_lab_instance_role"
  vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              dnf -y update
              dnf -y install git python3-pip
              pip3 install ansible
              echo 'export PATH=$PATH:/usr/local/bin' >> /home/ec2-user/.bashrc
              chown ec2-user:ec2-user /home/ec2-user/.bashrc
              /usr/local/bin/ansible-galaxy collection install community.general
              /usr/local/bin/ansible-galaxy collection install ansible.posix
              EOF

  tags = {
    Name = "RHEL9-Demo1"
  }
}

# resource "aws_instance" "rhel_demo2" {
#   ami                    = "ami-0dfc569a8686b9320"
#   instance_type          = "t2.medium"
#   key_name               = "ryan-key"
#   iam_instance_profile   = "ryan_dev_lab_instance_role"
#   vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

#   user_data = <<-EOF
#               #!/bin/bash
#               dnf -y update
#               dnf -y install git
#               EOF

#   tags = {
#     Name = "RHEL9-Demo2"
#   }
# }
#