# 01 — SonarQube: Code Quality Gate

> The most commonly asked about tool in DevOps pipeline interviews.
> "How did you set up SonarQube?" is a real question — and "I used the plugin" is not an answer.

---

## What It Is + Why It Matters

SonarQube is a **static code analysis server**. It reads your source code (not the running app), applies thousands of language-specific rules, and produces a report on bugs, vulnerabilities, code smells, and test coverage.

The critical part for pipelines is the **Quality Gate** — a set of thresholds you define (e.g. "zero Critical vulnerabilities", "coverage above 80%"). If the gate fails, the pipeline stops. This is how SonarQube becomes a mandatory checkpoint, not just a report.

**Why companies use it:** Every regulated industry (banking, insurance, healthcare) requires automated code quality checks before production deployments. SonarQube is the de facto standard.

---

## How It Works (The Flow — Critical to Understand)

This is what actually happens when your pipeline runs the SonarQube stage:

```
Jenkins Pipeline
      │
      │  1. withSonarQubeEnv() sets env vars: SONAR_HOST_URL, SONAR_AUTH_TOKEN
      │
      ▼
SonarQube Scanner (CLI or Maven plugin — runs on Jenkins agent)
      │
      │  2. Scanner reads source code, compiles analysis data
      │  3. Scanner sends analysis data to SonarQube Server (HTTP POST to port 9000)
      │
      ▼
SonarQube Server (separate machine/container)
      │
      │  4. Server processes analysis asynchronously (takes 10-60 seconds)
      │  5. Server evaluates Quality Gate rules
      │
      ▼
      │  6. Server sends HTTP POST to Jenkins webhook URL
      │     URL: http://jenkins:8080/sonarqube-webhook/
      │     Body: { "status": "OK" or "ERROR", "qualityGate": {...} }
      │
      ▼
Jenkins (waitForQualityGate() receives the webhook)
      │
      │  7. If status == OK → pipeline continues
      │  8. If status == ERROR → pipeline fails (abortPipeline: true)
```

**The key insight:** `waitForQualityGate()` does NOT poll SonarQube. It waits for SonarQube to call Jenkins back. If the webhook is not configured, Jenkins waits forever and then times out. This is the #1 error people hit.

---

## Components

| Component | What it is | Where it runs |
|-----------|-----------|---------------|
| SonarQube Server | The web app + analysis engine + database | Docker container (your machine or server) |
| SonarQube Scanner | CLI tool that sends code to the server | On the Jenkins agent (installed as Jenkins tool) |
| Quality Gate | Rules you configure in SonarQube UI | Stored in SonarQube Server |
| Webhook | HTTP callback from SonarQube → Jenkins | Configured in SonarQube UI |

---

## Infrastructure Setup

### Option A — Docker Compose (Recommended for Learning)

SonarQube needs PostgreSQL for production use (its default H2 database is for evaluation only and does not support concurrent users).

```yaml
# docker-compose.yml
version: "3.8"

services:
  sonarqube:
    image: sonarqube:26.8.0.126808-community
    container_name: sonarqube
    depends_on:
      - sonar-db
    ports:
      - "9000:9000"
    environment:
      SONAR_JDBC_URL: jdbc:postgresql://sonar-db:5432/sonar
      SONAR_JDBC_USERNAME: sonar
      SONAR_JDBC_PASSWORD: sonar_pass
    volumes:
      - sonarqube_data:/opt/sonarqube/data
      - sonarqube_logs:/opt/sonarqube/logs
      - sonarqube_extensions:/opt/sonarqube/extensions
    networks:
      - cicd-net

  sonar-db:
    image: postgres:15-alpine
    container_name: sonar-db
    environment:
      POSTGRES_USER: sonar
      POSTGRES_PASSWORD: sonar_pass
      POSTGRES_DB: sonar
    volumes:
      - sonar_pg_data:/var/lib/postgresql/data
    networks:
      - cicd-net

networks:
  cicd-net:
    name: cicd-net

volumes:
  sonarqube_data:
  sonarqube_logs:
  sonarqube_extensions:
  sonar_pg_data:
```

**Before running:** SonarQube requires a Linux kernel setting. Run this on the host machine:
```bash
# Required — SonarQube uses Elasticsearch which needs this
sudo sysctl -w vm.max_map_count=524288
sudo sysctl -w fs.file-max=131072
# Make it permanent:
echo "vm.max_map_count=524288" | sudo tee -a /etc/sysctl.conf
```

Start it:
```bash
docker compose up -d
# Wait 2-3 minutes for SonarQube to fully start
docker compose logs -f sonarqube   # watch logs, wait for "SonarQube is up"
```

**Resource requirement:** SonarQube + PostgreSQL together need at least 3GB RAM on the host.

---

## First-Time Configuration (Web UI)

Access at: `http://localhost:9000`

### Step 1 — Change admin password
Default: `admin` / `admin`
SonarQube forces a password change on first login. Set a new password and note it.

### Step 2 — Create a Project
1. Click **Create Project** → **Manually**
2. **Project display name:** `sample-app`
3. **Project Key:** `sample-app` (this is what your Jenkinsfile references — must match exactly)
4. **Main branch:** `main`
5. Click **Set Up**
6. Select **With Jenkins** → follow the token generation step

### Step 3 — Generate a Project Analysis Token
1. Go to **My Account** (top right) → **Security**
2. **Generate Tokens** section:
   - Name: `jenkins-token`
   - Type: **Project Analysis Token**
   - Project: `sample-app`
   - Expiration: No expiration (for learning) or 30 days (for production)
3. Click **Generate**
4. **Copy the token immediately — it will never be shown again**
   - Format: `sqp_60170905aa2bffbff00704ec6fbfeab8651ab278`

### Step 4 — Configure a Quality Gate
SonarQube ships with a default "Sonar way" gate. You can use it or create your own.

To see/modify: **Quality Gates** → **Sonar way**

Key conditions to understand:
| Condition | What it checks |
|-----------|---------------|
| Security Rating is worse than A | Any vulnerability that rates below A fails the gate |
| Reliability Rating is worse than A | Any bug that rates below A fails the gate |
| Coverage is less than 80% | Test coverage on new code must be ≥ 80% |
| Duplicated Lines is greater than 3% | Code duplication on new code |

> Note: "Sonar way" only checks **new code** (since last analysis). This is intentional — it prevents old legacy code from blocking every new PR.

To assign your gate to the project: **Project Settings** → **Quality Gate** → select "Sonar way"

### Step 5 — Configure the Webhook (The Step Everyone Forgets)
Without this, `waitForQualityGate()` in Jenkins hangs and times out.

1. **Administration** (top nav) → **Configuration** → **Webhooks**
2. Click **Create**
   - Name: `jenkins`
   - URL: `http://jenkins-instance-public-ip:8080/sonarqube-webhook/`
     - Use the Docker container name `jenkins` if both are on the same Docker network
     - Use the host IP if Jenkins is not in Docker: `http://192.168.1.x:8080/sonarqube-webhook/`
   - Secret: leave blank (or set one for security and reference it in Jenkins)
3. Click **Create**

---

## Jenkins Integration

### Step 1 — Install the Plugin
1. **Manage Jenkins** → **Plugins** → **Available plugins**
2. Search: `SonarQube Scanner`
3. Install (requires Jenkins restart)

### Step 2 — Add SonarQube Server in Jenkins
1. **Manage Jenkins** → **System** (scroll down to **SonarQube servers** section)
2. Check **Environment variables** checkbox first
3. Click **Add SonarQube**
   - Name: `SonarQube` ← this exact name is used in Jenkinsfile's `withSonarQubeEnv('SonarQube')`
   - Server URL: `http://sonarqube-instance-public-ip:9000` or (Docker container name) or `http://localhost:9000`
   - Server authentication token: Click **Add** → **Jenkins**
     - Kind: **Secret text**
     - Secret: paste the token from Step 3 above (`sqp_xxx...`)
     - ID: `sonarqube-token`
     - Description: `SonarQube Project Analysis Token`
   - Select the credential you just created
4. Save

### Step 3 — Install SonarQube Scanner Tool
1. **Manage Jenkins** → **Tools** → scroll to **SonarQube Scanner**
2. Click **Add SonarQube Scanner**
   - Name: `SonarQube Scanner` ← this name is referenced if you use `tool 'SonarQube Scanner'`
   - Check **Install automatically**
   - Version: pick the latest stable
3. Save

### Step 4 — Configure Maven Tool (Required for Java Projects)
Without this, Jenkins agents that do not have Maven pre-installed will throw `mvn: not found`.

1. **Manage Jenkins** → **Tools** → scroll to **Maven installations**
2. Click **Add Maven**
   - Name: `maven` ← this exact name is used in `tools { maven 'maven' }` in the Jenkinsfile
   - Check **Install automatically**
   - Version: pick the latest stable (e.g. 3.9.x)
3. Save

Then declare it at the top of your Jenkinsfile:
```groovy
tools {
    maven 'maven'
}
```

This makes the `mvn` binary available on `PATH` inside every stage of that pipeline.

---

## The Jenkinsfile Stages

Add both stages together — analysis and quality gate are always a pair.

> **Critical for Java projects:** SonarQube's Java analyzer requires compiled `.class` files. The Sonar stage MUST come after a Build stage that compiles the code. If you run Sonar on raw source files without compiling first, you get:
> ```
> ERROR: Your project contains .java files, please provide compiled classes
>        with sonar.java.binaries property
> ```
> Fix: add `stage('Build') { steps { sh 'mvn clean verify' } }` before the Sonar stage.

## IMPORTANT
- For SonarQube, the application must be compiled first so that the Java analyzer has access to the generated .class files.
- Since the application is already built during the SonarQube/Build stage, do not build it again when creating the Docker image.
- Use a lightweight JRE image for the runtime container and copy the already-built package (for example, the .jar) into it.
- This avoids redundant compilation and keeps the final Docker image smaller.

```groovy
tools {
    // Declare Maven tool — must match the name configured in Manage Jenkins → Tools → Maven
    maven 'maven'
}

stage('Build') {
    steps {
        // compile first — Sonar needs the .class files in target/classes
        sh 'mvn clean verify
    }
}

stage('SonarQube Analysis') {
    steps {
        // withSonarQubeEnv injects SONAR_HOST_URL and SONAR_AUTH_TOKEN as env vars
        withSonarQubeEnv('SonarQube') {
            // Use the fully qualified plugin if 'mvn sonar:sonar' fails with "No plugin found for prefix 'sonar'"
            sh 'mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=sample-app'
        }
    }
}

stage('Quality Gate') {
    steps {
        // waitForQualityGate blocks until SonarQube sends the webhook callback
        timeout(time: 5, unit: 'MINUTES') {
            waitForQualityGate abortPipeline: true
        }
    }
}
```

**Why `timeout` wraps `waitForQualityGate`:** If the webhook is misconfigured or SonarQube is down, without the timeout your pipeline hangs forever. 5 minutes is a reasonable upper bound for analysis to complete.

**`abortPipeline: true`:** Tells Jenkins to mark the build as FAILED if the gate returns ERROR. Without this, the pipeline continues even on a failed gate.

**`mvn sonar:sonar` vs fully qualified plugin:** `sonar:sonar` is a short prefix that Maven resolves via its plugin registry. On some environments this resolution fails. Use `org.sonarsource.scanner.maven:sonar-maven-plugin:sonar` — this always works and also pins you to a specific plugin group. You can optionally pin a version: `org.sonarsource.scanner.maven:sonar-maven-plugin:5.7.0.6970:sonar`.

**Debug logging:** If analysis fails and the error is not clear, add `-X` for full Maven debug output or `-Dsonar.verbose=true` for verbose Sonar scanner logs:
```bash
mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=sample-app -Dsonar.verbose=true
```

### Alternative commands for Python / Node.js

For Python (using sonar-scanner CLI):
```bash
sonar-scanner \
  -Dsonar.projectKey=sample-app \
  -Dsonar.sources=./src \
  -Dsonar.python.coverage.reportPaths=coverage.xml \
  -Dsonar.host.url=${SONAR_HOST_URL} \
  -Dsonar.token=${SONAR_AUTH_TOKEN}
```

For Node.js:
```bash
sonar-scanner \
  -Dsonar.projectKey=sample-app \
  -Dsonar.sources=./src \
  -Dsonar.javascript.lcov.reportPaths=coverage/lcov.info \
  -Dsonar.host.url=${SONAR_HOST_URL} \
  -Dsonar.token=${SONAR_AUTH_TOKEN}
```

Note: `${SONAR_HOST_URL}` and `${SONAR_AUTH_TOKEN}` are injected automatically by `withSonarQubeEnv()` — you do not set these manually in the Jenkinsfile.

---

## Verification — How to Confirm It's Working End-to-End

After running the pipeline:

1. Open SonarQube UI → `http://localhost:9000` → your project should appear
2. Click the project → you should see the analysis results (bugs, vulnerabilities, coverage)
3. The Quality Gate status should be green (Passed) or red (Failed) — not "Not Computed"
4. In Jenkins, check the build log — you should see:
   ```
   INFO: ANALYSIS SUCCESSFUL, you can find the results at: http://sonarqube:9000/dashboard?id=sample-app
   ```
   And then:
   ```
   Checking status of SonarQube task...
   SonarQube task 'xxxxx' status is 'SUCCESS'
   SonarQube task '...' completed. Quality gate is 'OK'
   ```

**If the quality gate line never appears:** the webhook is not configured correctly.

---

## Common Errors + Debugging

### 1. `waitForQualityGate` times out / hangs
**Error:** Pipeline stays on "Quality Gate" stage until timeout
**Cause:** Webhook is not configured in SonarQube
**Fix:** Administration → Webhooks → verify the webhook URL points to Jenkins. Test it by clicking "Test" in the SonarQube webhook config.

### 2. `ANALYSIS FAILED — 401 Unauthorized`
**Error:** Scanner returns HTTP 401 when trying to POST results
**Cause:** Token is wrong, expired, or the credential ID in Jenkins doesn't match what's being used
**Fix:** Regenerate the token in SonarQube. In Jenkins, delete the old credential and add the new token. Double-check the SonarQube server config points to the right credential.

### 3. Quality Gate always passes even with bugs
**Cause 1:** The Quality Gate is not assigned to the project
Fix: Project Settings → Quality Gate → assign "Sonar way"
**Cause 2:** All bugs are on old code, not new code — "Sonar way" only checks new code
Fix: Either create a custom gate that checks overall code, or reset the "new code" baseline in project settings

### 4. SonarQube starts but crashes after a few minutes
**Error:** Container exits, logs show `max virtual memory areas vm.max_map_count [65530] is too low`
**Fix:** Run `sudo sysctl -w vm.max_map_count=524288` on the host, then restart the container

### 5. `Connection refused` when scanner tries to reach server
**Error:** `ERROR: SonarQube server [http://localhost:9000] can not be reached`
**Cause:** Your Jenkinsfile or Jenkins config uses `localhost` — but from inside the Jenkins container, `localhost` is Jenkins itself, not SonarQube
**Fix:** Use the Docker container name: `http://sonarqube:9000`. Both containers must be on the same Docker network.

### 6. Analysis runs but project does not appear in SonarQube UI
**Cause:** `sonar.projectKey` in the scanner command does not match the project key created in the UI
**Fix:** Confirm the key in SonarQube: Project → Project Settings → key is shown there. It is case-sensitive.

### 7. `mvn: not found` — Maven binary not on PATH
**Error:** `mvn: not found` or `mvn: command not found`
**Cause:** The Jenkins agent does not have Maven pre-installed, and you did not declare a Maven tool in the Jenkinsfile.
**Fix:**
1. **Manage Jenkins** → **Tools** → **Maven installations** → Add Maven, name it `maven`, check **Install automatically**
2. Add to your Jenkinsfile at pipeline level:
   ```groovy
   tools {
       maven 'maven'
   }
   ```
Jenkins then downloads and injects Maven into PATH before any stage runs.

### 8. `No plugin found for prefix 'sonar'`
**Error:** `[ERROR] No plugin found for prefix 'sonar' in the current project and in the plugin groups`
**Cause:** Maven's plugin prefix registry lookup failed — common in restricted network environments or offline agents.
**Fix:** Replace the short prefix with the fully qualified plugin coordinates:
```bash
# Instead of:
mvn sonar:sonar

# Use:
mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar -Dsonar.projectKey=sample-app

# Or pin a specific version:
mvn org.sonarsource.scanner.maven:sonar-maven-plugin:5.7.0.6970:sonar -Dsonar.projectKey=sample-app
```

### 9. `sonar.java.binaries` error — Sonar ran before the build
**Error:** `Your project contains .java files, please provide compiled classes with sonar.java.binaries property`
**Cause:** The SonarQube Java analyzer does not analyze raw `.java` source files in isolation — it reads the compiled `.class` files from `target/classes`. If your pipeline runs Sonar before compiling (or skips the build stage entirely), this error fires.
**Fix:** Ensure the pipeline order is:
```
Checkout → Build (mvn clean verify -DskipTests) → SonarQube Analysis
```
`verify` compiles and runs tests, producing the `.class` files Sonar needs. Never run Sonar without a preceding build step on Java projects.

---

## Break It on Purpose

Do each one. Observe the exact error output. Then fix it. Do not skip these.

**1. Kill the webhook**
In SonarQube: Administration → Webhooks → edit your webhook → change the URL to `http://jenkins:9999/wrong/`.
Run the pipeline. The `Quality Gate` stage runs until your 5-minute timeout fires, then the build fails with "Timed out waiting for callback."
This is the most common real-world failure. You need to have seen it to diagnose it confidently.
Fix: restore the correct URL. Rerun.

**2. Wrong project key in the Jenkinsfile**
Change `-Dsonar.projectKey=sample-app` to `-Dsonar.projectKey=does-not-exist`.
Run the pipeline. Observe: analysis succeeds, a new orphan project `does-not-exist` appears in SonarQube, the quality gate passes (new project, no violations yet), Jenkins build is green.
This is why a "green pipeline" with SonarQube is not a proof the right gate ran.
Fix: correct the key. Keys are case-sensitive.

**3. Revoke the token then run the pipeline**
SonarQube UI → My Account → Security → revoke `jenkins-token`.
Run the pipeline. Observe the exact 401 error in the build log.
Fix: generate a new token, update the Jenkins credential (delete old, add new), rerun.

**4. Set an impossible quality gate condition**
Administration → Quality Gates → Sonar way → add condition: Coverage on New Code < 100%.
Run the pipeline. Gate fails unless every new line has a test.
This teaches you what "gate misconfigured" vs "real failure" looks like.
Fix: remove the condition.

---

## Scenarios

**Scenario 1 — Quality Gate shows "Not Computed," build is green**
Pipeline completes successfully. Jenkins shows green. SonarQube UI shows Quality Gate: "Not Computed" on the project.

What happened? Walk through your diagnosis before reading the answer.

*(Answer: `waitForQualityGate()` timed out before the webhook callback arrived. Jenkins moved on and the post-timeout behavior defaulted to passing. SonarQube finished its analysis after Jenkins gave up. Root cause: webhook URL wrong or SonarQube was slow. Fix: webhook + increase timeout OR verify SonarQube performance.)*

**Scenario 2 — Known SQL injection not caught by SonarQube**
A manual code review catches a SQL injection at line 88. SonarQube ran and did not flag it. The quality gate passed.

List the three most likely reasons and how you would verify each:

1. The SQL injection rule is disabled in the active quality profile → check: Quality Profiles → Java → search for "SQL injection" rule → is it Active?
2. The code path is dynamically constructed and SonarQube's static analysis cannot trace it → check: is the query built with string concatenation across multiple methods?
3. The language plugin version is outdated and does not cover this pattern → check: Administration → System → Plugins → Java plugin version

**Scenario 3 — Legacy module ported in, gate fails on coverage**
A developer migrates a 2000-line legacy class from an old system. Coverage is 0%. Quality gate fails.

Three options without disabling the gate:
1. **Exclude the file from analysis:** add `sonar.exclusions=**/legacy/**` in `pom.xml` properties. Useful temporarily while you plan test coverage.
2. **Adjust the new code baseline:** Project Settings → New Code → set baseline to a specific date before the migration commit. SonarQube then treats code before that date as "old" and ignores it for the gate.
3. **Correct approach:** write at minimum happy-path tests before porting legacy code. This is a process problem, not a SonarQube configuration problem.

---

## Interview Questions

**Q: How does SonarQube integrate with Jenkins?**
A: The Jenkins agent runs the SonarQube Scanner (a CLI tool), which sends analysis results to the SonarQube Server. The server analyzes the code asynchronously, evaluates the Quality Gate, then calls back Jenkins via a configured webhook with a pass or fail result. Jenkins waits for this callback using `waitForQualityGate()`.

**Q: What is a Quality Gate?**
A: A set of conditions you define in SonarQube (e.g., zero Critical vulnerabilities, coverage above 80%) that must all pass for the pipeline to continue. If any condition fails, the gate returns ERROR and the pipeline fails.

**Q: Why did the Quality Gate stage hang forever?**
A: The SonarQube webhook was not configured. `waitForQualityGate()` waits for SonarQube to POST to Jenkins at `/sonarqube-webhook/`. Without the webhook, Jenkins waits indefinitely.

**Q: What is the difference between SonarQube rules and a Quality Gate?**
A: Rules define what SonarQube detects and how it classifies issues. The Quality Gate defines the thresholds — how many of those issues are acceptable before the build fails. You can have 1000 rules active but a gate that only fails on Critical severity, so minor issues do not block the pipeline.

**Q: SonarQube ran and shows 50 bugs in the UI, but the Jenkins build passed. Why?**
A: Two possible reasons: (1) the Quality Gate is not assigned to the project — default behavior is no gate, so it always passes; (2) all 50 bugs are on old code and "Sonar way" gate only checks new code by default.

**Q: How do you configure SonarQube credentials in Jenkins securely?**
A: Generate a Project Analysis Token in SonarQube (not the admin password). Add it to Jenkins as a Secret Text credential. Reference it in the Jenkins SonarQube server configuration — Jenkins injects it as an environment variable during the pipeline. The token never appears in the Jenkinsfile itself.

**Q: Maven was available on my machine but Jenkins threw `mvn: not found`. Why?**
A: Jenkins pipeline stages run inside the Jenkins agent process, not your terminal. The agent does not inherit your shell `PATH`. You must declare Maven as a tool under **Manage Jenkins → Tools → Maven installations**, then reference it in the Jenkinsfile with `tools { maven 'maven' }`. Jenkins then injects the binary into PATH for every stage.

**Q: `mvn sonar:sonar` failed with "No plugin found for prefix 'sonar'." Why?**
A: Maven resolves short plugin prefixes (`sonar`) via the central plugin registry. In network-restricted environments or on offline agents this lookup fails. Always use the fully qualified coordinates: `mvn org.sonarsource.scanner.maven:sonar-maven-plugin:sonar`. This skips the registry lookup and works anywhere.

---

## What DevOps Actually Owns in SonarQube

This is the most common confusion: what does DevOps configure vs what does the development team own?

**DevOps / Platform Engineering owns:**
| Task | Where |
|------|-------|
| Run and maintain the SonarQube server (Docker, VM, or SaaS) | Infrastructure |
| Configure the SonarQube server in Jenkins (URL + token credential) | Manage Jenkins → System |
| Install the SonarQube Scanner Jenkins plugin | Manage Jenkins → Plugins |
| Configure Maven (or sonar-scanner CLI) as Jenkins tools | Manage Jenkins → Tools |
| Configure the SonarQube webhook pointing back to Jenkins | SonarQube UI → Administration → Webhooks |
| Write the `SonarQube Analysis` and `Quality Gate` stages in the shared Jenkinsfile or pipeline template | Jenkinsfile / shared library |
| Create project tokens and store them securely in Jenkins credentials | Jenkins Credentials store |

**Development team owns (or negotiates with DevOps):**
| Task | Where |
|------|-------|
| Define what Quality Gate conditions apply to their project | SonarQube UI → Quality Gates |
| Exclude generated code / vendor code from analysis | `sonar.exclusions` in `pom.xml` or `sonar-project.properties` |
| Fix or suppress findings (with justification) | SonarQube UI → Issues |
| Maintain test coverage above the gate threshold | Source code |

**In practice:** DevOps sets up the infrastructure and pipeline plumbing. The gate thresholds themselves are usually a conversation — DevOps proposes a baseline (e.g., "Sonar way"), the dev team agrees or requests adjustments for their project. Neither side should unilaterally disable the gate.

---

## Successful Pipeline Output Reference

This is what a correctly configured end-to-end run looks like in the Jenkins console. Use this as a baseline to compare your own runs against.

```
[INFO] Analysis total time: 21.248 s
[INFO] SonarScanner Engine completed successfully
[INFO] ------------------------------------------------------------------------
[INFO] BUILD SUCCESS
[INFO] ------------------------------------------------------------------------
[INFO] Total time:  39.187 s
[INFO] Finished at: 2026-08-12T18:48:18Z
[INFO] ------------------------------------------------------------------------
[Pipeline] // withSonarQubeEnv
[Pipeline] // stage
[Pipeline] stage
[Pipeline] { (Quality Gate)
[Pipeline] timeout
Timeout set to expire in 5 min 0 sec
[Pipeline] waitForQualityGate
Checking status of SonarQube task '32777cf6-...' on server 'SonarQube'
SonarQube task '32777cf6-...' status is 'IN_PROGRESS'
SonarQube task '32777cf6-...' status is 'SUCCESS'
SonarQube task '32777cf6-...' completed. Quality gate is 'OK'
[Pipeline] // timeout
```

Key lines to verify:
- `SonarScanner Engine completed successfully` — scanner finished, data sent to server
- `status is 'IN_PROGRESS'` → `status is 'SUCCESS'` — server processed the analysis asynchronously
- `Quality gate is 'OK'` — the webhook callback arrived and the gate passed
- If you never see `Quality gate is 'OK'` and the stage times out instead — the webhook is wrong