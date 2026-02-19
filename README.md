# Instructions

- Create a Deployment with 3 pods (i.e replicas)
    - Each pod containing
        - 1 MySQL container
        - 1 FastAPI Container
- Create a Service and an Ingress to enable access to the API

- Enable communication between the API + the Database:
    - Complete the code provided for the API
    - Rebuild the corresponding Docker image (+ upload it to DockerHub) 
    - Change the API code to retrieve the database password (atascientest1234) - this password cannot be hard-coded and must therefore be put in a Secret 

## Deliverables:

The expected output is a set of files, with a comment file if required:

the reworked main.py file
a my-deployment-eval.yml file containing the Deployment declaration
a my-service-eval.yml file containing the Service declaration
a my-ingress-eval.yml file containing the Ingress declaration
a my-secret-eval.yml file containing the Secret declaration