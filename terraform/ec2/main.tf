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

resource "aws_instance" "rhel_demo1" {
  ami                    = "ami-0dfc569a8686b9320"  
  instance_type          = "t3.xlarge"              
  key_name               = "ryan-key"
  iam_instance_profile   = "ryan_dev_lab_instance_role"
  vpc_security_group_ids = [data.aws_security_group.ryan_sg.id]

 
  root_block_device {
    volume_size           = 100  
    volume_type           = "gp3"
    delete_on_termination = true
  }
  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              dnf -y update
              dnf -y install git python3-pip podman podman-docker buildah skopeo runc shadow-utils util-linux-user

              useradd -m -s /bin/bash sapuser || true
              echo 'sapuser ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/sapuser
              chmod 440 /etc/sudoers.d/sapuser

              loginctl enable-linger sapuser || true

              mkdir -p /etc/containers
              cat <<EOC > /etc/containers/containers.conf
              [engine]
              runtime = "runc"
              default_runtime = "runc"
              EOC

              runuser -l sapuser -c 'mkdir -p ~/.config/containers ~/.local/share/containers'
              cat <<EOC > /home/sapuser/.config/containers/containers.conf
              [engine]
              runtime = "runc"
              default_runtime = "runc"
              EOC
              chown -R sapuser:sapuser /home/sapuser/.config /home/sapuser/.local

              echo "sapuser:100000:65536" >> /etc/subuid
              echo "sapuser:100000:65536" >> /etc/subgid

              mkdir -p /data/hxe
              chown -R sapuser:sapuser /data

              pip3 install --upgrade pip
              pip3 install ansible
              ansible-galaxy collection install community.general ansible.posix

              runuser -l sapuser -c 'podman info | grep -A2 "ociRuntime"' || true
              EOF

  tags = {
    Name    = "RHEL9-HANAExpress-Demo1"
    Project = "SAP-HANA-Express"
    Owner   = "ryandevlab"
  }
}


