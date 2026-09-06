# Kubernetes Deployment Report

## Spring PetClinic Application with PostgreSQL

### 1. Scope

This report documents only the Kubernetes aspects of the Spring PetClinic deployment. It focuses on the Kubernetes resources used to run the application and PostgreSQL and Kubernetes troubleshooting.

### 2. Kubernetes Architecture

> The final deployment follows this architecture:

```text
   User
    |
    v
  PetClinic Service / Application Pod
    |
    | JDBC: "jdbc:postgresql://postgres-svc:5432/petclinic"
    v
  postgres-svc
    |
    v
  PostgreSQL StatefulSet (postgres-0)
    |
    v
  PersistentVolumeClaim
    |
    v
  Persistent Storage
```

- The PetClinic application runs in a Kubernetes workload and communicates with PostgreSQL through the Kubernetes Service named `postgres-svc`.
- PostgreSQL runs as a StatefulSet so that its identity and persistent storage can be associated with the database instance.

### 3. PostgreSQL StatefulSet

PostgreSQL was deployed as a StatefulSet. This is appropriate for a stateful database because the database needs stable identity and persistent storage.

- The Username, DB-name, Password should be `petclinic` only. As per the App configuration.
  > NOTE - To change the configuration you have to update the app config files as they are hardcoded

```yaml
containers:
  - name: postgres
    image: postgres:15
    env:
      - name: POSTGRES_USER
        value: petclinic

      - name: POSTGRES_DB
        value: petclinic

      - name: POSTGRES_PASSWORD
        valueFrom:
          secretKeyRef:
            name: postgres-secret
            key: POSTGRES_PASSWORD

    volumeMounts:
      - name: db-data
        mountPath: /var/lib/postgresql/data
```

### 4. Persistent Storage with volumeClaimTemplates

The PostgreSQL StatefulSet uses a volumeClaimTemplate to create persistent storage for the database. The requested storage was 1 GiB with ReadWriteOnce access and the standard StorageClass.

```yaml
volumeClaimTemplates:
  - metadata:
      name: db-data
    spec:
      accessModes:
        - ReadWriteOnce
      storageClassName: standard
      resources:
        requests:
          storage: 1Gi
```

- The PostgreSQL volume is mounted at /var/lib/postgresql/data, which is the database data directory.

### 5. Kubernetes Secret

The PostgreSQL password is stored in a Kubernetes Secret. The Secret is referenced by both the PostgreSQL container and the PetClinic application.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: postgres-secret
type: Opaque
data:
  POSTGRES_PASSWORD: <base64-encoded-password> # petclinic
```

### 6. PetClinic Application Configuration

The PetClinic Pod receives its database configuration through Kubernetes environment variables.

```yaml
env:
  - name: SPRING_DATASOURCE_URL
    value: jdbc:postgresql://postgres-svc:5432/petclinic

  - name: SPRING_DATASOURCE_USERNAME
    value: petclinic

  - name: SPRING_DATASOURCE_PASSWORD
    valueFrom:
      secretKeyRef:
        name: postgres-secret
        key: POSTGRES_PASSWORD

  - name: SPRING_JPA_HIBERNATE_DDL_AUTO
    value: update
```

- The important Kubernetes point is that the application uses the PostgreSQL Service DNS name `postgres-svc` instead of a Pod IP. This allows the application to continue using a stable endpoint even if the PostgreSQL Pod is recreated.
- `SPRING_JPA_HIBERNATE_DDL_AUTO=update` is an application-level setting delivered through the Kubernetes environment. It allows Hibernate to create/update the database schema after the application establishes a database connection.
  - Without this variable, we are unable to create or view the DB table data.

### 7. Kubernetes Troubleshooting

#### 7.1 Persistent storage and PostgreSQL initialization

A key Kubernetes behavior was observed when the PostgreSQL environment variables were changed. POSTGRES_USER and POSTGRES_DB are used during PostgreSQL initialization of an empty data directory. If a persistent volume already contains an initialized PostgreSQL cluster, changing these environment variables does not recreate the user or database.
This caused:
`FATAL: role "petclinic" does not exist`
The PostgreSQL workload and its persistent data were recreated when a fresh database initialization was required. After that, the petclinic role and database were available.

#### 7.2 Database schema not initially available

After connectivity was fixed, the application initially reported that the owners relation did not exist. This demonstrated that successful Pod-to-Service connectivity is separate from having the required application schema/data.
`ERROR: relation "owners" does not exist`
After the schema was initialized with the env variable:

```yaml
- name: SPRING_JPA_HIBERNATE_DDL_AUTO
  value: update
```

the PostgreSQL database contained the expected PetClinic tables.

### 8. Kubernetes Verification Commands

The following commands were useful for checking the Kubernetes deployment:

```sh
kubectl get pods
kubectl get svc
kubectl get statefulset
kubectl get pvc
kubectl get pv
kubectl describe pod <pod-name>
kubectl logs <pod-name>
kubectl logs postgres-0
kubectl exec -it postgres-0 -- sh
```

### 9. Insert the type values (Automated)

The `types` table is required reference data for the PetClinic app — `pet_type` is a required field when adding a pet. Hibernate (`DDL_AUTO=update`) creates the table schema but does not seed it with data.

This is now **automated** via [`db-seed-job.yml`](./db-seed-job.yml). Apply it once after the StatefulSet is running:

```sh
kubectl apply -f db-seed-job.yml
```

**How it works:**

- A **ConfigMap** (`db-seed-sql`) holds the idempotent seed SQL using `ON CONFLICT DO NOTHING` — safe to re-apply.
- An **init container** in the Job polls `pg_isready` until PostgreSQL accepts connections.
- The **seed container** then runs `psql` to execute the SQL, inserting: `cat`, `dog`, `lizard`, `snake`, `bird`, `hamster`.

**Monitor the job:**

```sh
kubectl get job db-seed -n petclinic-dev
kubectl logs -l app=db-seed -n petclinic-dev
```

**Re-seed after a full DB wipe:**

```sh
# Delete the completed job first, then re-apply
kubectl delete job db-seed -n petclinic-dev
kubectl apply -f db-seed-job.yml
```

> **Manual fallback** (if needed):
>
> ```sh
> kubectl exec -it postgres-0 -n petclinic-dev -- psql -U petclinic -d petclinic
> INSERT INTO types (name) VALUES ('cat'), ('dog'), ('lizard'), ('snake'), ('bird'), ('hamster') ON CONFLICT (name) DO NOTHING;
> SELECT * FROM types;
> ```

### 10. PostgreSQL Verification from Kubernetes

The PostgreSQL container was accessed directly from its Pod:

```sh
kubectl exec -it postgres-0 -- sh

# The database was then accessed with:

psql -U petclinic -d petclinic

# The following PostgreSQL commands were used to verify the database:

\l      # list databases
\dn     # list schemas
\dt     # list tables
\d owners  # describe owners table

To Check the data
select * from owners
select * from pets
```

### 11. Access

Add petclinic.local to hosts file

```bash
curl -k https://petclinic.local

# Web
https://petclinic.local
```

### 11. Final Kubernetes State

The final Kubernetes deployment achieved the following:

- PetClinic application runs as a Kubernetes workload.
- PostgreSQL runs as a StatefulSet.
- PostgreSQL is reachable through the postgres-svc Kubernetes Service.
- Database credentials are provided through postgres-secret.
- PostgreSQL data is stored on persistent storage using a PVC created from volumeClaimTemplates.
- PetClinic receives datasource configuration through environment variables.
- Hibernate schema management is enabled with SPRING_JPA_HIBERNATE_DDL_AUTO=update.
- The application successfully establishes a JDBC connection to PostgreSQL.
- PostgreSQL can be inspected from inside the database Pod using kubectl exec.

### 12. Key Kubernetes Lessons

- Remember that PostgreSQL initialization environment variables are not retroactive when an existing data directory is mounted.
- A successful database connection does not guarantee that the required schema or reference data exists.
- Use kubectl logs, describe, exec, get pods, get svc, and get pvc systematically when troubleshooting.
