Adding Okta groups to Jenkins CASC
=================================

This project uses Configuration-as-Code (CASC) to declare Jenkins' global
security configuration. The authoritative file is `casc/jenkins.yaml` in the
repository. If you add a new group in Okta and you want that group to have
permissions in Jenkins, follow the steps below.

1) Decide the permission set for the Okta group
   - Common permissions are: `hudson.model.Hudson.Read`, `hudson.model.Item.Build`,
     `hudson.model.Item.Read`, `hudson.model.View.Read`, etc.
   - Be conservative by default: grant the minimum required permissions.

2) Edit `casc/jenkins.yaml`
   - Add entries under `jenkins.security.authorizationStrategy."hudson.security.GlobalMatrixAuthorizationStrategy".grantedPermissions`.
   - Use the exact Okta group name as it appears in the `groups` claim (case sensitive handling depends on your IdStrategy; this repo uses case-insensitive strategy but prefer exact match).

Example snippet (add to the `grantedPermissions` list):

  - "GROUP:hudson.model.Hudson.Read:example-okta-group"
  - "GROUP:hudson.model.Item.Build:example-okta-group"

3) Commit the change to git (recommended: create a branch and PR for review)

4) Apply changes
   - Option A (recommended for infra-managed repos): merge the PR and redeploy Jenkins so CASC is reloaded during startup.
   - Option B (quicker, local): restart the Jenkins container to force CASC to reload.

Commands (local dev):

```bash
# from project root
git add casc/jenkins.yaml
git commit -m "chore(casc): add Okta group 'example-okta-group' with limited permissions"
docker-compose restart jenkins
```

5) Verify the change
   - Check `data/jenkins_home/config.xml` for the new <permission> entries:

```bash
grep -n "GROUP:.*example-okta-group" data/jenkins_home/config.xml || true
```

   - Confirm in the Jenkins UI (Manage Jenkins → Configure Global Security → Matrix-based security).

Notes & best practices
- Keep CASC as the single source of truth for security. Avoid ad-hoc init groovy scripts that mutate global security on boot.
- If you need automation when Okta groups are created, automate changes to the CASC YAML in a controlled way (PRs, CI pipeline) rather than granting permissions dynamically at login-time.
- For emergency recovery, a breakglass admin user should be configured in the CASC so you can always log in and fix security.

 
Further reading
---------------

If you want to explore the full set of Configuration-as-Code options and examples, these resources are authoritative:

- Jenkins Configuration as Code (CASC) plugin (official plugin page) — https://plugins.jenkins.io/configuration-as-code/
- CASC plugin README and usage guide (GitHub) — https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/README.md
- CASC supported plugins / configuration reference — https://github.com/jenkinsci/configuration-as-code-plugin/blob/master/docs/supported_plugins.md
- Matrix-based security plugin (permission names reference) — https://plugins.jenkins.io/matrix-auth/

Tip: your running Jenkins also exposes a live schema and documentation at the Configuration as Code endpoints (for example: `http://<jenkins-host>/configuration-as-code/schema`) which can help discover available fields for the YAML.

