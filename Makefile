# Copyright 2018 The KubeSphere Authors. All rights reserved.
# Use of this source code is governed by a Apache license
# that can be found in the LICENSE file.

# The binary to build 
BIN ?= ks-apiserver

# Produce CRDs that work back to Kubernetes 1.11 (no version conversion)
CRD_OPTIONS ?= "crd:trivialVersions=true"

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif


IMG ?= kubespheredev/ks-apiserver
OUTPUT_DIR=bin
GOFLAGS=-mod=vendor
define ALL_HELP_INFO
# Build code.
#
# Args:
#   WHAT: Directory names to build.  If any of these directories has a 'main'
#     package, the build will produce executable files under $(OUT_DIR).
#     If not specified, "everything" will be built.
#   GOFLAGS: Extra flags to pass to 'go' when building.
#   GOLDFLAGS: Extra linking flags passed to 'go' when building.
#   GOGCFLAGS: Additional go compile flags passed to 'go' when building.
#
# Example:
#   make
#   make all
#   make all WHAT=cmd/ks-apiserver
#     Note: Use the -N -l options to disable compiler optimizations an inlining.
#           Using these build options allows you to subsequently use source
#           debugging tools like delve.
endef
.PHONY: all
all: test ks-apiserver ks-apigateway ks-iam controller-manager clientset

# Build ks-apiserver binary
ks-apiserver: test
	hack/gobuild.sh cmd/ks-apiserver

# Build ks-apigateway binary
ks-apigateway: test
	hack/gobuild.sh cmd/ks-apigateway

# Build ks-iam binary
ks-iam: test
	hack/gobuild.sh cmd/ks-iam

# Build controller-manager binary
controller-manager: test
	hack/gobuild.sh cmd/controller-manager

# Run go fmt against code 
fmt: generate
	go fmt ./pkg/... ./cmd/...

# Run go vet against code
vet: generate
	go vet ./pkg/... ./cmd/...

# Generate manifests e.g. CRD, RBAC etc.
manifests:
	go run ./vendor/sigs.k8s.io/controller-tools/cmd/controller-gen/main.go all

deploy: manifests
	kubectl apply -f config/crds
	kustomize build config/default | kubectl apply -f -

# generate will generate crds' deepcopy & go openapi structs
# Futher more about go:genreate . https://blog.golang.org/generate
generate:
	GO111MODULE=on go install -mod=vendor k8s.io/code-generator/cmd/deepcopy-gen
	go generate ./pkg/... ./cmd/...

# Build the docker image
docker-build: all
	docker build . -t ${IMG}

# Run tests
test: fmt vet
	export KUBEBUILDER_CONTROLPLANE_START_TIMEOUT=1m; go test ./pkg/... ./cmd/... -coverprofile cover.out

.PHONY: clean
clean:
	-make -C ./pkg/version clean
	@echo "ok"

# find or download controller-gen
# download controller-gen if necessary
clientset: 
	./hack/generate_client.sh


# Currently in the upgrade phase of controller tools.
# But the new controller tools are not compatible with the old version.
# With these commands you may need to manually modify the generated code
# So don't use it unless you know it very deeply
internal-crds:
	$(CONTROLLER_GEN) $(CRD_OPTIONS) rbac:roleName=manager-role webhook paths="./pkg/apis/network/..." output:crd:artifacts:config=config/crd/bases

internal-generate-apis: internal-controller-gen
	$(CONTROLLER_GEN) object:headerFile=./hack/boilerplate.go.txt paths=./pkg/apis/network/...

internal-controller-gen:
ifeq (, $(shell which controller-gen))
	go get sigs.k8s.io/controller-tools/cmd/controller-gen@v0.2.0-beta.4
CONTROLLER_GEN=$(GOBIN)/controller-gen
else
CONTROLLER_GEN=$(shell which controller-gen)
endif
