function deployIngressController() {
  if [[ "$(readConfig ".ingress.controller.enabled" "true")" == "false" ]]; then
    return
  fi

  echo ""
  echo "================= DEPLOYING INGRESS CONTROLLER ================="

  keyPath=$(readConfig ".ingress.certs.key" "./certs/key.pem")
  certPath=$(readConfig ".ingress.certs.bundle" "./certs/cert-bundle.pem")

  kubectl create namespace ingress-nginx || true
  kubectl create secret tls --namespace ingress-nginx ingress-tls \
    --key="$keyPath" --cert="$certPath" || true
  helm upgrade --install ingress-nginx ingress-nginx \
    --repo https://kubernetes.github.io/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.extraArgs.default-ssl-certificate=ingress-nginx/ingress-tls \
    --set controller.service.type=NodePort \
    --set controller.service.nodePorts.https=32443 \
    --set controller.watchIngressWithoutClass=true
}

event on onClusterDependencies deployIngressController