prefix=$(fgrep prefix terraform.tfvars | sed -Ee 's/.*"(.*)".*/\1/')

guid=$(ibmcloud dns instances --output json | jq -r ".[] | select(.name==\"$prefix-dns\") | .guid")
zoneid=$(ibmcloud dns zones -i "$prefix-dns" --output json | jq -r '.[0] | .id')

app_rec=$(ibmcloud dns resource-records $zoneid -i "$prefix-dns" --output json | jq -r '.resource_records | .[] | select(.name=="app.example.com") | .id')
primary_rec=$(ibmcloud dns resource-records $zoneid -i "$prefix-dns" --output json | jq -r '.resource_records | .[] | select(.name=="db-primary.example.com") | .id')
standby_rec=$(ibmcloud dns resource-records $zoneid -i "$prefix-dns" --output json | jq -r '.resource_records | .[] | select(.name=="db-standby.example.com") | .id')

echo "Run the following import commands after initializing your terraform workspace:"
echo "  terraform import ibm_dns_resource_record.app $guid/$zoneid/$app_rec"
echo "  terraform import ibm_dns_resource_record.db_primary $guid/$zoneid/$primary_rec"
echo "  terraform import ibm_dns_resource_record.db_standby $guid/$zoneid/$standby_rec"

