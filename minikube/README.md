Prereq

Authenticate once manually

cloudflared login


It will:

Open a browser link (copy-paste it into your browser)

Ask you to choose your Cloudflare domain (ryandemolab.app)

Download and save cert.pem to /root/.cloudflared/cert.pem

Then re-run:

cloudflare.sh script for ach app

http://98.84.141.61:33871/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/