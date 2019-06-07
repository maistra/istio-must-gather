Istio must-gather
=================

`Istio must-gather` is a tool built on top of [OpenShift must-gather](https://github.com/openshift/must-gather) that expands its capabilities to gather Service Mesh information.

### Usage
```sh
oc adm must-gather --image=quay.io/maistra/istio-must-gather:latest -- /usr/bin/gather_istio
```

The command above will create a local directory with a dump of the OpenShift cluster state, including Service Mesh data. Run `oc adm must-gather -h` to see more options.
