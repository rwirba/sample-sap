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

#   user_data = <<-EOF
#               #!/bin/bash
#               dnf -y update
#               dnf -y install git python3-pip
#               pip3 install ansible
#               echo 'export PATH=$PATH:/usr/local/bin' >> /home/ec2-user/.bashrc
#               chown ec2-user:ec2-user /home/ec2-user/.bashrc
#               /usr/local/bin/ansible-galaxy collection install community.general
#               /usr/local/bin/ansible-galaxy collection install ansible.posix
#               EOF

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
###############################################
# SAP HANA Express RHEL9 EC2 Instance (Podman)
###############################################
resource "aws_instance" "rhel_demo1" {
  ami                    = "ami-0dfc569a8686b9320"  # ✅ Official RHEL 9 AMI (update if region differs)
  instance_type          = "t3.xlarge"              # ✅ 4 vCPUs, 16 GB RAM (SAP HANA Express minimum)
  key_name               = "ryan-key"
  iam_instance_profile   = "ryan_dev_lab_instance_role"
  vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

  # Root volume: use gp3 for better performance and throughput
  root_block_device {
    volume_size = 80        # ✅ at least 80 GB disk for HANA base image + runtime
    volume_type = "gp3"
    delete_on_termination = true
  }

  ###############################################
  # Cloud-init: base system + runtime + ansible
  ###############################################
  user_data = <<-EOF
              #!/bin/bash
              set -eux

              # --- System updates & base packages ---
              dnf -y update
              dnf -y install git python3-pip podman podman-docker buildah skopeo runc

              # --- Configure Podman to always use runc ---
              mkdir -p /etc/containers
              cat <<EOC > /etc/containers/containers.conf
              [engine]
              runtime = "runc"
              default_runtime = "runc"
              EOC

              # Rootless config for ec2-user
              sudo -u ec2-user mkdir -p /home/ec2-user/.config/containers
              cat <<EOC > /home/ec2-user/.config/containers/containers.conf
              [engine]
              runtime = "runc"
              default_runtime = "runc"
              EOC
              chown -R ec2-user:ec2-user /home/ec2-user/.config

              # --- Install and prepare Ansible ---
              pip3 install --upgrade pip
              pip3 install ansible
              /usr/local/bin/ansible-galaxy collection install community.general
              /usr/local/bin/ansible-galaxy collection install ansible.posix

              # --- Set environment for ec2-user ---
              echo 'export PATH=$PATH:/usr/local/bin' >> /home/ec2-user/.bashrc
              chown ec2-user:ec2-user /home/ec2-user/.bashrc

              # --- Verify runtime for debugging ---
              podman info | grep -A2 "ociRuntime" >> /var/log/podman-runtime.log 2>&1 || true
              EOF

  ###############################################
  # Metadata / Tagging
  ###############################################
  tags = {
    Name = "RHEL9-HANAExpress-Demo1"
    Project = "SAP-HANA-Express"
    Owner   = "ryandevlab"
  }
}
