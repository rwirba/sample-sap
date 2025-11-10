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

# resource "aws_instance" "rhel_demo1" {
#   ami                    = "ami-0dfc569a8686b9320"  # RHEL 9 AMI
#   instance_type          = "t2.medium"
#   key_name               = "ryan-key"
#   iam_instance_profile   = "ryan_dev_lab_instance_role"
#   vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

  # user_data = <<-EOF
  #             #!/bin/bash
  #             dnf -y update
  #             dnf -y install git python3-pip
  #             pip3 install ansible
  #             echo 'export PATH=$PATH:/usr/local/bin' >> /home/ec2-user/.bashrc
  #             chown ec2-user:ec2-user /home/ec2-user/.bashrc
  #             /usr/local/bin/ansible-galaxy collection install community.general
  #             /usr/local/bin/ansible-galaxy collection install ansible.posix
  #             EOF

#   tags = {
#     Name = "RHEL9-Demo1"
#   }
# }

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

resource "aws_instance" "rhel_demo1" {
  ami                    = "ami-0dfc569a8686b9320"  # RHEL 9 AMI
  instance_type          = "t3.2xlarge"
  key_name               = "ryan-key"
  iam_instance_profile   = "ryan_dev_lab_instance_role"
  vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

  user_data = <<-EOF
              #!/bin/bash
              set -e

              # ==== Base setup ====
              dnf -y update
              dnf -y install git python3-pip

              # Always upgrade pip first
              /usr/bin/python3 -m pip install --upgrade pip

              # ==== Install Ansible and dependencies ====
              /usr/bin/python3 -m pip install --user ansible kubernetes openshift requests requests-oauthlib oauthlib

              # Ensure PATH includes user bin
              echo 'export PATH=$PATH:/home/ec2-user/.local/bin' >> /home/ec2-user/.bashrc
              echo 'export PYTHONPATH=/home/ec2-user/.local/lib/python3.9/site-packages:$PYTHONPATH' >> /home/ec2-user/.bashrc
              chown ec2-user:ec2-user /home/ec2-user/.bashrc

              # ==== Install Ansible Collections ====
              sudo -u ec2-user /home/ec2-user/.local/bin/ansible-galaxy collection install \
                community.general ansible.posix kubernetes.core

              # ==== Verification (log to /var/log/bootstrap.log) ====
              {
                echo "Python path: $(which python3)"
                python3 -m pip show ansible kubernetes openshift
              } >> /var/log/bootstrap.log 2>&1

              EOF

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name    = "RHEL9-HANAExpress-Demo1"
    Project = "SAP-HANA-Express"
    Owner   = "ryandevlab"
  }
}
