kubectl -n orders port-forward service/orders-api 8080:80
# In another terminal:
curl --fail http://127.0.0.1:8080/readyz
