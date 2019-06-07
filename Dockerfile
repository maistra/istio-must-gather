FROM quay.io/openshift/origin-must-gather:latest
COPY gather_istio /usr/bin/
ENTRYPOINT /usr/bin/gather_istio
