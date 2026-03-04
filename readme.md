# Digital School Moodle

This repository contains the source code for **Moodle LMS** used in the **CYBE Digital School platform**.

The project is containerized using **Docker** and integrated with **CI/CD pipelines** through **GitHub Actions** to automatically build and publish container images.

The generated Docker image is deployed to a **Kubernetes (k3s) cluster** using **ArgoCD** with a **GitOps workflow**.

## Purpose

This repository is used to:

* Store the Moodle source code
* Build Docker images for Moodle
* Run CI pipelines via GitHub Actions
* Provide container images for Kubernetes deployment

Kubernetes deployment manifests are maintained in a separate GitOps repository.

## CI/CD Workflow

1. Code is pushed to this repository.
2. GitHub Actions builds the Docker image.
3. The image is pushed to GitHub Container Registry (GHCR).
4. ArgoCD deploys the updated image to the Kubernetes cluster.

## Maintained By

CYBE Digital School Engineering Team
