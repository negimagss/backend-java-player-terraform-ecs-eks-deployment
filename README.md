# ⚾ Terraform and ECS and EKS exercise

# Exercise Overview

The exercise will do the following:

1. Create a VPC, subnets and load balancer on AWS  
2. Create a CodeBuild pipeline and also pick the image from this repo to ECR  
3. Once image is captured, it will be deployed to ECS  
4. Publish terraform output and get the URL  

Publish the Ollama model as a sidecr java application in ECS.  
If any changes are made, publish the changes to Git, push, and CodeBuild will pick it from the ECR to rebuild a new instance with zero downtime.

## Steps to recreate

1. `cd /terraform`  
2. Run `terraform init`  
3. Run `terraform plan`  
4. Run `terraform apply`  

---

Player Service is a backend application that serves baseball player data.  
In addition, Player Service integrates with Ollama, which allows us to run the tinyllama LLM locally.

Find the URL from your Load Balancer:  
`http://player-service-alb-291170883.us-east-2.elb.amazonaws.com/v1/chat/list-models`

The LLM is running as a sidecar in this deployment.


The exercise focusos on AWS deployment to ECS automating the process of deployment process and understanding the sidecar for ECS deployments. 

terraform destory after validation. 

### Next: 
EKS


### EKS Deployment Guide

This guide explains how to deploy your Kubernetes workloads using EKS. Reference the main-eks.tf file for deploying the EKS cluster.

### Step 1: 
Deploy the EKS Cluster with NGNIX Pod

Use main-eks.tf to create the EKS cluster.

This deployment will automatically create an NGNIX pod as part of the cluster setup.

### Step 2: 
Deploy Additional Services

The next two pods need to be deployed using your YAML manifests:

Go-lang Pod

Java-intuit Pod

### To deploy:

cd yaml
kubectl apply -f <yaml-file-name>


This will configure the new service files in your Kubernetes cluster and start the pods.

### Notes:

### ECR Images:

Ensure both Docker images have been pushed to your ECR repository.

The ECR locations are specified in the YAML files. Replace the placeholder text with your actual image URIs.

Refer to the ECR documentation for instructions on pushing images.

### Load Balancer & Networking:

EKS will create new EC2 instances to host the pods.

A new Load Balancer (LB) will be automatically provisioned and attached to one of the public subnets defined (currently, two public subnets are defined).

The new LB will provide external access to your services.

Service Availability:

Once deployed, the new URL for your services will be live and accessible externally.

### Step 3: 
Verify Pods

Check that the Java-intuit pods are running:

kubectl get pods -l app=java-intuit


### Example output:

NAME                           READY   STATUS    RESTARTS   AGE
java-intuit-7cf9ddb8b4-bhtlx   1/1     Running   0          45m
java-intuit-7cf9ddb8b4-kc6wq   1/1     Running   0          45m


Check all pods in the cluster:

kubectl get pods


### Example output:

NAME                            READY   STATUS    RESTARTS      AGE
go-pod-clock-778fc987f7-q5nhj   1/1     Running   7 (43m ago)   171m
go-pod-clock-778fc987f7-r9bxz   1/1     Running   0             11h
hello-world-57fb685494-plml8    1/1     Running   0             11h
java-intuit-7cf9ddb8b4-bhtlx    1/1     Running   0             45m
java-intuit-7cf9ddb8b4-kc6wq    1/1     Running   0             45m
ollama-644fdffdf7-2v274         1/1     Running   0             45m

### Step 4: 
Test the New Deployment

Test the Java-intuit service using the Load Balancer URL:

curl --location 'http://<ELB-DNS-NAME>.us-east-2.elb.amazonaws.com/v1/players/zychto01'


Replace <ELB-DNS-NAME> with the actual DNS name of your ELB.



## Dependencies

- [Java 17](https://www.oracle.com/java/technologies/javase/jdk17-archive-downloads.html)
- [maven.apache.org](https://maven.apache.org/install.html)
- Spring Boot 3.3.4 (with Spring Web MVC, Spring Data JPA)
- [H2 Database](https://www.h2database.com/html/main.html)
- [Docker](https://www.docker.com/) or [Podman](https://podman.io/)

## 🛠️ Setup Instructions

1. Verify system dependencies
   1. Java 17
      - Verify installation: `java -version`
   2. Maven
      - Download and install from [maven.apache.org](https://maven.apache.org/install.html)
      - Verify installation, run: `mvn --version`
      - Verify java version linked to maven is Java 17 `Java version: 17.x.x`
   3. Container Manager
      - Download and install from [docker.com](https://www.docker.com/)(recommended) or [podman](https://podman.io/) (alternative)
      - Verify installation, run: `docker --version` for docker

2. Clone this repository or Download the code as zip
   - run `git clone https://github.com/Intuit-A4A/backend-java-player-service.git`

## Run the application

### Part 1: Application Dependencies

1. Install application dependencies
    - From the project's root directory, run: `mvn clean install -DskipTests`

### Part 2: Run Player Service (without LLM)

1. Start the Player service

   ```shell
   mvn spring-boot:run
   ```

2. Verify the Player service is running
      1. Open your browser and visit `http://localhost:8080/v1/players`
      2. If the application is running successfully, you will see player data appear in the browser

### Part 3: Start LLM Docker Container

Player service integrates with Ollama 🦙, which allows us to run LLMs locally. This app runs [tinyllama](https://ollama.com/library/tinyllama) model.

- [Ollama API documentation](https://github.com/ollama/ollama/blob/main/docs/api.md)
- [Ollama4J SDK](https://ollama4j.github.io/ollama4j/intro)

1. Pull and run Ollama docker image and download `tinyllama` model
   - Pull Ollama docker image

    ```shell
    docker pull ollama/ollama
    ```

2. Run Ollama docker image on port 11434 as a background process

    ```shell
    docker run -d -v ollama:/root/.ollama -p 11434:11434 --name ollama ollama/ollama
    ```

3. Download and run `tinyllama` model

    ```shell
    docker exec -it ollama ollama run tinyllama
    ```

4. Test Ollama API server

    ```curl
    curl -v --location 'http://localhost:11434/api/generate' --header 'Content-Type: application/json' --data '{"model": "tinyllama","prompt": "why is the sky blue?", "stream": false}'
    ```
Having trouble with docker? Try using podman as an alternative. Instructions [here](https://github.com/Intuit-A4A/backend-java-player-service/wiki/Supplemental-Materials:-Set-up-help#alternative-set-up-instructions)


### Part 4: Verify Player Service and LLM Integration

1. Ensure Player Service is running from previous instructions. If not:

    ```shell
    mvn spring-boot:run
    ```

2. Open your browser and visit `http://localhost:8080/v1/chat/list-models`
   - If the application is running successfully, you will see a json response that include information about tinyllama
