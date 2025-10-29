Prereq
For new domain run

sudo mkdir -p /opt/minikube
sudo chown ec2-user:ec2-user /opt/minikube
cd /opt/minikube
git clone https://github.com/rwirba/sample-sap.git
cd sample-sap
git checkout k8s-automation

cloudflared tunnel create global-tunnel

copy them over to s3

aws s3 cp ~/.cloudflared/685f93fc-fc7d-49cd-ae7a-231479572dbf.json s3://ryandevlab-bucket/cloudflare-tunnel.json


Authenticate once manually

cloudflared login


It will:

Open a browser link (copy-paste it into your browser)

Ask you to choose your Cloudflare domain (ryandemolab.app)

Download and save cert.pem to /root/.cloudflared/cert.pem

Create a cloudflare-tunnel.json descriptor for automation

Now create a simple metadata file that your automation scripts will read:


EOF
http://98.84.141.61:33871/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/