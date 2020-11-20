FROM quay.io/openshift/origin-must-gather:4.6

# Save original gather script
RUN mv /usr/bin/gather /usr/bin/gather_original

# Use our gather script in place of the original one
COPY gather_istio /usr/bin/gather

ENTRYPOINT /usr/bin/gather
