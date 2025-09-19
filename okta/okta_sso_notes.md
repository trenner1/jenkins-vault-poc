Okta → Jenkins SSO (humans)
- App: OIDC Web
- Redirect URI: http://localhost:8080/securityRealm/finishLogin
- Scopes: openid email profile groups
- In Jenkins: set Security Realm to your Okta OIDC app and confirm login works.

Note: The JWT used for Vault is issued by Jenkins in-pipeline (not the Okta token).
