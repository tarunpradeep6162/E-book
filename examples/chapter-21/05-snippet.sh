# Set these from the protected recovery inventory; token never goes in Git.
export DNS_ZONE_ID=REPLACE_ZONE_ID
export DNS_RECORD_ID=REPLACE_RECORD_ID
export DNS_API_TOKEN=RETRIEVE_FROM_SECRET_SOURCE
umask 077
header_file=$(mktemp)
trap 'rm -f "$header_file"' EXIT
printf 'Authorization: Bearer %s\n' "$DNS_API_TOKEN" > "$header_file"
unset DNS_API_TOKEN
cat > dns-change.json <<'JSON'
{
  "type": "CNAME",
  "name": "orders.example.com",
  "content": "recovery.example.net",
  "ttl": 60,
  "proxied": false
}
JSON
curl --fail-with-body --silent --show-error \
  --request PATCH \
  --header "@$header_file" \
  --header 'Content-Type: application/json' \
  --data @dns-change.json \
  "https://api.cloudflare.com/client/v4/zones/$DNS_ZONE_ID/dns_records/$DNS_RECORD_ID"
