# Creating Image for petclinic

- Using nexus:8082/ as the registry address to later push the image to Nexus Docker Repository on port 8082 instead of Docker Hub.
- Update the image tag in k8s/petclinic.yml

```bash
    cd Reference_Project/spring-petclinic
    docker build -t nexus:8082/petclinic:1

    docker image
```

# Scanning Using Trivy

### Trying without Flags

```bash
    trivy image nexus:8082/petclinic:1
```

**Insights**

- As first scan will take time, as it downloads its vulnerability DB
- Then the Report Summary will get Generated in CLI only
- Always using --cache-dir flag in pipeline to speed up the DB download process.
- `Common Error + Debugging, Point 2.`

```bash
# OUTPUT

$ trivy image nexus:8082/petclinic:1

2026-08-08T03:05:45+05:30       INFO    [vulndb] Need to update DB
2026-08-08T03:05:45+05:30       INFO    [vulndb] Downloading vulnerability DB...
2026-08-08T03:05:45+05:30       INFO    [vulndb] Downloading artifact...        repo="mirror.gcr.io/aquasec/trivy-db:2"
...
2026-08-08T03:06:00+05:30       INFO    [javadb] Downloading Java DB...
2026-08-08T03:06:00+05:30       INFO    [javadb] Downloading artifact...        repo="mirror.gcr.io/aquasec/trivy-java-db:1"

```

### Trying with Flags

```bash
    trivy image --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed --output trivy-report.txt nexus:8082/petclinic:1
```

**Insights**

- `--exit-code 1 / --exit-code 0`
- The exit code will change that's it (we use it to pass or fail the pipeline, if there are any vuln.)
  - 0 means pass
  - 1 means fail
- echo $?
