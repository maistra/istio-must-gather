Istio must-gather
=================

`Istio must-gather` is a tool built on top of [OpenShift must-gather](https://github.com/openshift/must-gather) that expands its capabilities to gather Service Mesh information.

### Usage
```sh
oc adm must-gather --image=quay.io/maistra/istio-must-gather
```

The command above will create a local directory with a dump of the OpenShift Service Mesh state. Note that this command will only get data related to the Service Mesh part of the OpenShift cluster.

You will get a dump of:
- The Istio Operator namespace (and its children objects)
- All Control Plane namespaces (and their children objects)
- All namespaces (and their children objects) that belong to any service mesh
- All Istio CRD's definitions
- All Istio CRD's objects (VirtualServices in a given namespace, etc)
- All Istio Webhooks

In order to get data about other parts of the cluster (not specific to service mesh) you should run just `oc adm must-gather` (without passing a custom image). Run `oc adm must-gather -h` to see more options.
