# VM Scale Set
###    Template Deployment Details:
    **Deployed to Private Virtual Network
    SSL Cert Imported to VM Instances from KeyVault 
    Binding SSL to IIS port 443 on VM Instances through Custom Script Extension
    Internal Load Balancer**

_Note: This template was designed to be used in typical scenario where many of these resources are managed by separate groups._

**Prerequisites to Using this Template:**

These resources are not included in this template but required:
* Virtual Network w/ Subnet for deploying the VM Instances and Internal Load Balancer
    Same Vnet required for VMSS w/ LB, but allows for separate subnets
* Key Vault used by the VM Instances for: 
    Admin Password Secret
    SSL Certificate Resource - follow steps [here:](https://docs.microsoft.com/en-us/azure/virtual-machines/windows/tutorial-secure-web-server#generate-a-certificate-and-store-in-key-vault) or use Azure Portal. 
* Storage Account with Blob Container for PowerShell Script used by the CSE
    Upload BindSSLToIIS.ps1 to Container prior to running template
