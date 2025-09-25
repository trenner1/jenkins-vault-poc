#!/usr/bin/env bash
set -euo pipefail

# Bootstrap Jenkins with admin user setup
# This script configures Jenkins with an initial admin user and basic security

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
JENKINS_HOME="${REPO_ROOT}/data/jenkins_home"

echo "Jenkins Bootstrap Setup"
echo "=========================="

# Check if Jenkins container is running
if ! docker ps --format '{{.Names}}' | grep -q '^jenkins$'; then
    echo "Jenkins container is not running!"
    echo "   Please run './scripts/start.sh' first to start the containers."
    exit 1
fi

# Check if Jenkins is ready
echo "Waiting for Jenkins to be ready..."
JENKINS_URL="http://localhost:8080"
MAX_RETRIES=30
RETRY_COUNT=0

while ! curl -s "${JENKINS_URL}" >/dev/null 2>&1; do
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "Jenkins did not start within expected time"
        exit 1
    fi
    echo "   Waiting for Jenkins... (${RETRY_COUNT}/${MAX_RETRIES})"
    sleep 5
    ((RETRY_COUNT++))
done

echo "Jenkins is ready!"

# Check if Jenkins is already configured
if [[ -f "${JENKINS_HOME}/config.xml" ]] && grep -q '<useSecurity>true</useSecurity>' "${JENKINS_HOME}/config.xml" 2>/dev/null; then
    echo "Jenkins appears to be already configured with security enabled."
    echo "   If you want to reconfigure, you'll need to reset Jenkins data."
    read -p "   Continue anyway? (y/N): " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "   Bootstrap cancelled."
        exit 0
    fi
fi

# Get admin credentials
echo ""
echo "Admin User Setup"
echo "==================="
read -p "Enter admin username [admin]: " ADMIN_USERNAME
ADMIN_USERNAME=${ADMIN_USERNAME:-admin}

# Read password securely
while true; do
    read -s -p "Enter admin password: " ADMIN_PASSWORD
    echo
    if [[ -z "$ADMIN_PASSWORD" ]]; then
        echo "Password cannot be empty. Please try again."
        continue
    fi
    read -s -p "Confirm admin password: " ADMIN_PASSWORD_CONFIRM
    echo
    if [[ "$ADMIN_PASSWORD" == "$ADMIN_PASSWORD_CONFIRM" ]]; then
        break
    else
        echo "Passwords don't match. Please try again."
    fi
done

read -p "Enter admin full name [Administrator]: " ADMIN_FULLNAME
ADMIN_FULLNAME=${ADMIN_FULLNAME:-Administrator}

read -p "Enter admin email [admin@example.com]: " ADMIN_EMAIL
ADMIN_EMAIL=${ADMIN_EMAIL:-admin@example.com}

echo ""
echo "Configuring Jenkins..."

# Create Jenkins configuration script
JENKINS_SCRIPT=$(cat << 'EOF'
import jenkins.model.*
import hudson.security.*
import hudson.security.csrf.DefaultCrumbIssuer
import hudson.model.*
import org.jenkinsci.plugins.scriptsecurity.scripts.ScriptApproval

def instance = Jenkins.getInstance()

// Create local admin user (for emergency access)
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount("${ADMIN_USERNAME}", "${ADMIN_PASSWORD}")
instance.setSecurityRealm(hudsonRealm)

// Set up Global Matrix Authorization Strategy (matching CASC)
def strategy = new GlobalMatrixAuthorizationStrategy()

// Grant admin permissions to the created admin user
strategy.add(Hudson.ADMINISTER, "${ADMIN_USERNAME}")

// Grant team-based permissions (matching CASC configuration)
// Group: backend-developers
strategy.add(Hudson.READ, "backend-developers")
strategy.add(Item.BUILD, "backend-developers")
strategy.add(Item.CANCEL, "backend-developers")
strategy.add(Item.DISCOVER, "backend-developers")
strategy.add(Item.READ, "backend-developers")
strategy.add(Item.WORKSPACE, "backend-developers")
strategy.add(Run.REPLAY, "backend-developers")
strategy.add(View.READ, "backend-developers")

// Group: devops-team
strategy.add(Hudson.READ, "devops-team")
strategy.add(Item.BUILD, "devops-team")
strategy.add(Item.CANCEL, "devops-team")
strategy.add(Item.DISCOVER, "devops-team")
strategy.add(Item.READ, "devops-team")
strategy.add(Item.WORKSPACE, "devops-team")
strategy.add(Run.REPLAY, "devops-team")
strategy.add(View.READ, "devops-team")

// Group: frontend-developers
strategy.add(Hudson.READ, "frontend-developers")
strategy.add(Item.BUILD, "frontend-developers")
strategy.add(Item.CANCEL, "frontend-developers")
strategy.add(Item.DISCOVER, "frontend-developers")
strategy.add(Item.READ, "frontend-developers")
strategy.add(Item.WORKSPACE, "frontend-developers")
strategy.add(Run.REPLAY, "frontend-developers")
strategy.add(View.READ, "frontend-developers")

// Group: mobile-developers
strategy.add(Hudson.READ, "mobile-developers")
strategy.add(Item.BUILD, "mobile-developers")
strategy.add(Item.CANCEL, "mobile-developers")
strategy.add(Item.DISCOVER, "mobile-developers")
strategy.add(Item.READ, "mobile-developers")
strategy.add(Item.WORKSPACE, "mobile-developers")
strategy.add(Run.REPLAY, "mobile-developers")
strategy.add(View.READ, "mobile-developers")

// Apply the authorization strategy
instance.setAuthorizationStrategy(strategy)

// Set admin user details
def user = User.get("${ADMIN_USERNAME}")
def email = new hudson.tasks.Mailer.UserProperty("${ADMIN_EMAIL}")
user.addProperty(email)

def fullName = new hudson.model.UserProperty() {
    @Override
    public String getDisplayName() { return "Full Name" }
    @Override
    public String getFullName() { return "${ADMIN_FULLNAME}" }
}

// Enable CSRF protection
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// Disable setup wizard
System.setProperty("hudson.model.UpdateCenter.never", "true")
System.setProperty("jenkins.install.runSetupWizard", "false")

// Skip initial setup
def initialSetup = instance.getExtensionList(jenkins.install.InstallState.class)[0]
initialSetup.setInitialSetupCompleted(true)

// Save configuration
instance.save()

println "Jenkins configured with admin user '${ADMIN_USERNAME}' and team-based permissions!"
EOF
)

# Replace variables in the script
JENKINS_SCRIPT=$(echo "$JENKINS_SCRIPT" | sed "s/\${ADMIN_USERNAME}/$ADMIN_USERNAME/g")
JENKINS_SCRIPT=$(echo "$JENKINS_SCRIPT" | sed "s/\${ADMIN_PASSWORD}/$ADMIN_PASSWORD/g")
JENKINS_SCRIPT=$(echo "$JENKINS_SCRIPT" | sed "s/\${ADMIN_FULLNAME}/$ADMIN_FULLNAME/g")
JENKINS_SCRIPT=$(echo "$JENKINS_SCRIPT" | sed "s/\${ADMIN_EMAIL}/$ADMIN_EMAIL/g")

# Execute the script in Jenkins
echo "   Creating admin user..."
CRUMB=$(curl -s "${JENKINS_URL}/crumbIssuer/api/xml?xpath=concat(//crumbRequestField,\":\",//crumb)" 2>/dev/null || true)

if [[ -n "$CRUMB" ]]; then
    CRUMB_HEADER="-H $CRUMB"
else
    CRUMB_HEADER=""
fi

# Try to execute the script
RESPONSE=$(curl -s -w "%{http_code}" -o /tmp/jenkins_response.txt \
    $CRUMB_HEADER \
    -d "script=${JENKINS_SCRIPT}" \
    "${JENKINS_URL}/scriptText" || true)

HTTP_CODE="${RESPONSE: -3}"

if [[ "$HTTP_CODE" == "200" ]]; then
    echo "Jenkins admin user created successfully!"
    cat /tmp/jenkins_response.txt 2>/dev/null || true
elif [[ "$HTTP_CODE" == "403" ]]; then
    echo "Jenkins setup wizard may still be active or security is already configured."
    echo "   You can complete the setup manually at: ${JENKINS_URL}"
    echo "   Or reset Jenkins data and try again."
else
    echo "Script execution returned HTTP code: $HTTP_CODE"
    echo "   Response:"
    cat /tmp/jenkins_response.txt 2>/dev/null || echo "   (no response body)"
    echo ""
    echo "   You may need to complete Jenkins setup manually at: ${JENKINS_URL}"
fi

# Clean up
rm -f /tmp/jenkins_response.txt

echo ""
echo "Bootstrap Complete!"
echo "====================="
echo "   Jenkins URL: ${JENKINS_URL}"
echo "   Admin Username: ${ADMIN_USERNAME}"
echo "   Admin Email: ${ADMIN_EMAIL}"
echo ""
echo "Next Steps:"
echo "   1. Visit ${JENKINS_URL} to verify login"
echo "   2. Install additional plugins if needed"
echo "   3. Configure Vault integration using the HashiCorp Vault plugin"
echo "   4. Set up team-based pipeline jobs"
echo ""
echo "Security Note:"
echo "   Your admin credentials are now active. Store them securely!"