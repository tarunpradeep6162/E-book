gcloud config get-value project
gcloud container clusters get-credentials orders-autopilot \
  --region asia-south1 --project APPROVED_PROJECT
kubectl config current-context
kubectl auth can-i get pods -n orders
