Terraform setup

Everything will run inside podman container

create
az login --use-device-code 
To sign in, use a web browser to open the page https://microsoft.com/devicelogin and enter the code xxxxxxxx to authenticate
## To deploy demo:

```bash 
cd terraform/infra
terraform init
terraform plan -var-file="../config/demo.tfvars"
terraform apply
```

## To deploy dev:

```bash 
cd terraform/config/dev
terraform init
terraform apply
```
